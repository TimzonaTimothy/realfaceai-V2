import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account_status.dart';
import '../models/user.dart';
import '../utils/maintenance_exception.dart';
import 'api_service.dart';
import 'app_gate.dart';

class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  // Maintenance state — set when the server responds with 503 maintenance.
  // The router reads this to decide whether to send the user to /maintenance.
  MaintenanceException? _maintenanceException;

  // Exposed so the app shell can show a "retrying…" indicator on startup.
  bool _isInitialising = false;

  Timer? _pollTimer;
  Timer? _retryTimer;

  // How many times we've retried _loadProfile on this cold-start.
  int _profileRetryCount = 0;
  static const int _maxProfileRetries = 4;
  // Back-off delays in seconds: 2s → 4s → 8s → 16s
  static const List<int> _retryDelays = [2, 4, 8, 16];

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;

  /// Tokens are stored even if the profile hasn't loaded (e.g. the account
  /// was suspended at start-up).
  bool get hasSession => _user != null || ApiService.instance.isLoggedIn;
  bool get isInitialising => _isInitialising;
  String? get error => _error;
  double get credits => _user?.credits ?? 0.0;
  MaintenanceException? get maintenanceException => _maintenanceException;
  bool get isInMaintenance => _maintenanceException != null;

  // ── First-run onboarding ──────────────────────────────────────────────────
  static const _kOnboardingDone = 'onboarding_done';
  bool _onboardingDone = true;
  bool get onboardingDone => _onboardingDone;

  /// Clears the last auth error (e.g. when switching sign in / register).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Marks the welcome tour as seen so it never shows again on this device.
  Future<void> completeOnboarding() async {
    _onboardingDone = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingDone, true);
    } catch (_) {}
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    AppGate.instance.onAccountStatus = _applyAccountStatus;
    AppGate.instance.addListener(_onGateChanged);

    // Show splash immediately — set initialising before any async work.
    _isInitialising = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _onboardingDone = prefs.getBool(_kOnboardingDone) ?? false;
    } catch (_) {
      _onboardingDone = true;
    }

    await ApiService.instance.loadTokens();

    if (ApiService.instance.isLoggedIn) {
      await _loadProfile();
      // _loadProfile sets _isInitialising = false once it either
      // succeeds, exhausts retries, or detects invalid tokens.
    } else {
      // Not logged in — done initialising, router will redirect to /login.
      _isInitialising = false;
      notifyListeners();
    }
  }

  // ── Lifecycle — stop polling when app minimised ───────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // If we came back online after a failed cold-start, try again once.
      if (!isLoggedIn && ApiService.instance.isLoggedIn) {
        _profileRetryCount = 0;
        _isInitialising = true;
        notifyListeners();
        _loadProfile();
      } else if (isLoggedIn) {
        _startPolling();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopPolling();
      _retryTimer?.cancel();
    }
  }

  // ── Auth Actions ──────────────────────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.instance.login(email, password);
      if (data['statusCode'] == 200) {
        _user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
        _profileRetryCount = 0;
        _startPolling();
        return true;
      } else {
        _error = data['error'] as String? ?? 'Login failed.';
        return false;
      }
    } catch (e) {
      _error = 'Connection error. Check your internet.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data =
          await ApiService.instance.register(email, username, password);
      if (data['statusCode'] == 201) {
        _user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
        _profileRetryCount = 0;
        _startPolling();
        return true;
      } else {
        if (data['email'] != null) {
          _error = (data['email'] as List).first.toString();
        } else if (data['password'] != null) {
          _error = (data['password'] as List).first.toString();
        } else {
          _error = data['error'] as String? ?? 'Registration failed.';
        }
        return false;
      }
    } catch (e) {
      _error = 'Connection error. Check your internet.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _stopPolling();
    _retryTimer?.cancel();
    _profileRetryCount = 0;
    _isInitialising = false;
    await ApiService.instance.logout();
    _user = null;
    notifyListeners();
  }

  // ── Profile loading with retry + graceful fallback ────────────────────────
  //
  // Three distinct outcomes are handled:
  //
  //  A. SUCCESS — getMe() returns 200 with valid JSON.
  //     → Parse user, start polling, done.
  //
  //  B. AUTH FAILURE — tokens are invalid/expired AND refresh also failed.
  //     ApiService.clearTokens() was already called inside _request(), so
  //     ApiService.isLoggedIn is now false.
  //     → Log out cleanly; GoRouter sends user to /login with no blank screen.
  //
  //  C. NETWORK / SERVER ERROR — SocketException, timeout, 500, bad JSON, etc.
  //     The tokens themselves are still valid; this is a temporary failure.
  //     → Retry up to _maxProfileRetries times with exponential back-off.
  //     → After all retries exhausted, log out and send to /login so the user
  //        can try again manually rather than staring at a blank screen.

  // ── Load profile (with retry + maintenance handling) ──────────────────────
  //
  //  A. SUCCESS           → set _user, start polling, done.
  //  B. MAINTENANCE (503) → set _maintenanceException, notify router.
  //  C. AUTH FAILURE      → tokens invalid, clear and redirect to /login.
  //  D. NETWORK / SERVER  → retry with exponential back-off.

  Future<void> _loadProfile() async {
    if (!ApiService.instance.isLoggedIn) {
      await _handleUnauthenticated();
      return;
    }

    try {
      final data = await ApiService.instance.getMe();

      if (!ApiService.instance.isLoggedIn) {
        await _handleUnauthenticated();
        return;
      }

      // ── Forced update (426) or suspended account (403) ────────────────────
      // ApiService already raised the AppGate; the router shows the gate
      // screen. Keep the tokens so the session resumes once it's lifted
      // (see _onGateChanged / recheckAccountAccess).
      if (AppGate.instance.isBlocked && data['statusCode'] != 200) {
        _isInitialising = false;
        notifyListeners();
        return;
      }

      if (data['statusCode'] != null && data['statusCode'] != 200) {
        await _scheduleProfileRetry(reason: 'http ${data['statusCode']}');
        return;
      }

      // ── Happy path ────────────────────────────────────────────────────────
      _user = UserModel.fromJson(data);
      _profileRetryCount = 0;
      _isInitialising = false;
      _maintenanceException = null;
      _error = null;
      notifyListeners();
      _startPolling();
    } on MaintenanceException catch (e) {
      // ── Server is in maintenance ──────────────────────────────────────────
      // Store the exception so the router can read it and send to /maintenance.
      debugPrint('[AuthProvider] Maintenance mode: ${e.info.message}');
      _maintenanceException = e;
      _isInitialising = false;
      notifyListeners();
      // Don't retry automatically here — MaintenanceScreen handles that.
    } on SocketException {
      await _scheduleProfileRetry(reason: 'network');
    } on HandshakeException {
      await _scheduleProfileRetry(reason: 'tls');
    } on TimeoutException {
      await _scheduleProfileRetry(reason: 'timeout');
    } catch (e) {
      if (!ApiService.instance.isLoggedIn) {
        await _handleUnauthenticated();
      } else {
        await _scheduleProfileRetry(reason: 'parse/server');
      }
    }
  }

  // Called when we know the session is dead. Clears state and redirects.
  Future<void> _handleUnauthenticated() async {
    _isInitialising = false;
    await logout(); // clears tokens, sets _user = null, notifyListeners()
    // GoRouter's redirect will fire because isLoggedIn is now false and
    // ApiService tokens are also gone → sends to /login automatically.
  }

  // Schedules the next retry attempt with exponential back-off.
  // If we've exhausted all retries, falls back to logout so the user
  // always lands on /login instead of a blank screen.
  Future<void> _scheduleProfileRetry({required String reason}) async {
    if (_profileRetryCount >= _maxProfileRetries) {
      // We've tried enough. The server or network may be down.
      // Log out cleanly — user will see /login and can try again.
      debugPrint('[AuthProvider] _loadProfile failed ($reason) after '
          '$_maxProfileRetries retries — clearing session.');
      _isInitialising = false;
      await logout();
      return;
    }

    final delay =
        _retryDelays[_profileRetryCount.clamp(0, _retryDelays.length - 1)];
    _profileRetryCount++;

    debugPrint('[AuthProvider] _loadProfile failed ($reason) — '
        'retry $_profileRetryCount/$_maxProfileRetries in ${delay}s');

    // Keep _isInitialising = true so the UI stays on the loading screen
    // (not a blank screen or a premature redirect to /login).
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delay), _loadProfile);
  }

  // ── Polling (every 15s) ───────────────────────────────────────────────────
// ── Called by MaintenanceScreen after server comes back up ────────────────
  // Clears the maintenance state and re-runs _loadProfile so the router
  // redirects to /dashboard once the server is healthy again.

  Future<void> clearMaintenance() async {
    _maintenanceException = null;
    _isInitialising = true;
    notifyListeners();
    await _loadProfile();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!isLoggedIn) return;
      try {
        final data = await ApiService.instance.poll();
        final newCredits = (data['credits'] ?? 0).toDouble();
        // Picks up a freeze / unfreeze within one poll cycle.
        final status = data.containsKey('account_status')
            ? AccountStatus.fromJson(data['account_status'])
            : _user?.accountStatus;
        if (_user != null &&
            (newCredits != _user!.credits || status != _user!.accountStatus)) {
          _user = _user!.copyWith(credits: newCredits, accountStatus: status);
          notifyListeners();
        }
        // A successful poll means the account isn't suspended (any more) —
        // e.g. a temporary suspension just ended.
        AppGate.instance.clearSuspension();
      } catch (_) {
        // If ApiService cleared tokens because the refresh token expired,
        // log out cleanly so GoRouter redirects to /login.
        if (!ApiService.instance.isLoggedIn) {
          await logout();
        }
        // Otherwise it's a transient network blip — polling will retry in 15s.
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Account status / gates ────────────────────────────────────────────────

  void _applyAccountStatus(AccountStatus status) {
    if (_user == null || _user!.accountStatus == status) return;
    _user = _user!.copyWith(accountStatus: status);
    notifyListeners();
  }

  // When a gate is lifted while we still hold tokens but never loaded the
  // profile (the gate hit during start-up), resume the normal start-up.
  void _onGateChanged() {
    if (AppGate.instance.isBlocked) return;
    if (_user == null && ApiService.instance.isLoggedIn && !_isInitialising) {
      _profileRetryCount = 0;
      _isInitialising = true;
      notifyListeners();
      _loadProfile();
    }
  }

  /// "Check again" on the suspended screen. Returns true if access is back.
  Future<bool> recheckAccountAccess() async {
    if (!ApiService.instance.isLoggedIn) return false;
    try {
      final data = await ApiService.instance.getMe();
      if (data['statusCode'] == 200) {
        _user = UserModel.fromJson(data);
        _profileRetryCount = 0;
        _isInitialising = false;
        AppGate.instance.clearSuspension(); // router leaves the gate screen
        notifyListeners();
        _startPolling();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// "Sign out" on the suspended screen.
  Future<void> signOutFromGate() async {
    await logout(); // user cleared first so the router lands on /login
    AppGate.instance.clearSuspension();
  }

  void updateCredits(double newCredits) {
    if (_user != null) {
      _user = _user!.copyWith(credits: newCredits);
      notifyListeners();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppGate.instance.removeListener(_onGateChanged);
    if (AppGate.instance.onAccountStatus == _applyAccountStatus) {
      AppGate.instance.onAccountStatus = null;
    }
    _stopPolling();
    _retryTimer?.cancel();
    super.dispose();
  }
}