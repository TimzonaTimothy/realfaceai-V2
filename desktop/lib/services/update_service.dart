import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config/app_version.dart';
import '../models/update_info.dart';
import 'api_service.dart';
import 'app_gate.dart';

export '../models/update_info.dart';

/// Kept for older imports; the source of truth is lib/config/app_version.dart.
const String kCurrentVersion = kAppVersion;

/// Checks GET /app/latest-version/ on start-up, every [_interval], and when
/// the app returns to the foreground.
///
///  • force_update  → AppGate shows the blocking update screen.
///  • otherwise, a newer build → the dismissible banner (UpdateBanner).
///
/// Forced updates are ALSO enforced server-side: once a mandatory release is
/// live, every API call from an older build gets 426, which raises the same
/// gate even between checks.
class UpdateService extends ChangeNotifier with WidgetsBindingObserver {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  static const Duration _interval = Duration(minutes: 30);
  static const Duration _minGapOnResume = Duration(minutes: 5);

  UpdateInfo? _available;
  String? _dismissedVersion;
  bool _checking = false;
  bool _started = false;
  Timer? _timer;
  DateTime? _lastCheck;

  /// Optional (non-forced) update to show in the banner, unless dismissed.
  UpdateInfo? get available {
    final info = _available;
    if (info == null) return null;
    if (!info.isMandatory && info.version == _dismissedVersion) return null;
    return info;
  }

  bool get hasUpdate => available != null;
  bool get isMandatory => _available?.isMandatory ?? false;
  bool get isChecking => _checking;

  /// Idempotent. Call once at start-up.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    checkForUpdate();
    _timer = Timer.periodic(_interval, (_) => checkForUpdate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) > _minGapOnResume) {
      checkForUpdate();
    }
  }

  /// Returns the latest info, or null when the check couldn't complete.
  Future<UpdateInfo?> checkForUpdate() async {
    final platform = kAppPlatform;
    if (platform == null || _checking) return null;

    _checking = true;
    _lastCheck = DateTime.now();
    notifyListeners();
    try {
      final uri = Uri.parse('$kBaseUrl/app/latest-version/').replace(
        queryParameters: {'platform': platform, 'current_version': kAppVersion},
      );
      final resp = await http
          .get(uri, headers: kAppVersionHeaders)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 404) {
        // Nothing published for this platform — nothing to enforce.
        _available = null;
        AppGate.instance.clearRequiredUpdate();
        return null;
      }
      if (resp.statusCode != 200) return null;

      final info =
          UpdateInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);

      if (info.forceUpdate) {
        AppGate.instance.requireUpdate(info);
      } else {
        AppGate.instance.clearRequiredUpdate();
      }

      final newer = info.updateAvailable ||
          (info.version.isNotEmpty && isNewerVersion(info.version, kAppVersion));
      _available = newer && !info.forceUpdate ? info : null;
      return info;
    } catch (_) {
      // Offline / server error — try again on the next tick.
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Hides the banner for this version until a newer one is published.
  void dismiss() {
    _dismissedVersion = _available?.version;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
