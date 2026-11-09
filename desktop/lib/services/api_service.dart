// import 'dart:convert';
// import 'dart:io';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';

// // ── Change this to your real Django server URL ──
// const String kBaseUrl =
//     'https://instantfaceai-django-backend.onrender.com/api/v1';

// // const String kBaseUrl = 'http://127.0.0.1:8000/api/v1';
// // const String kBaseUrl = 'http://10.42.166.139:8000/api/v1';

// class ApiService {
//   static final ApiService instance = ApiService._();
//   ApiService._();

//   String? _accessToken;
//   String? _refreshToken;

//   // ── Token Management ──────────────────────────────────────────────────────

//   Future<void> loadTokens() async {
//     final prefs = await SharedPreferences.getInstance();
//     _accessToken = prefs.getString('access_token');
//     _refreshToken = prefs.getString('refresh_token');
//   }

//   Future<void> saveTokens(String access, String refresh) async {
//     _accessToken = access;
//     _refreshToken = refresh;
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString('access_token', access);
//     await prefs.setString('refresh_token', refresh);
//   }

//   Future<void> clearTokens() async {
//     _accessToken = null;
//     _refreshToken = null;
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove('access_token');
//     await prefs.remove('refresh_token');
//   }

//   bool get isLoggedIn => _accessToken != null;
//   String? get accessToken => _accessToken;

//   Map<String, String> get _authHeaders => {
//         'Content-Type': 'application/json',
//         if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
//       };

//   Future<bool> _tryRefresh() async {
//     if (_refreshToken == null) return false;
//     try {
//       final resp = await http.post(
//         Uri.parse('$kBaseUrl/auth/refresh/'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'refresh': _refreshToken}),
//       );
//       if (resp.statusCode == 200) {
//         final data = jsonDecode(resp.body);
//         await saveTokens(data['access'], _refreshToken!);
//         return true;
//       }
//     } catch (_) {}
//     return false;
//   }

//   Future<http.Response> _request(
//     String method,
//     String path, {
//     Map<String, dynamic>? body,
//   }) async {
//     final uri = Uri.parse('$kBaseUrl$path');
//     http.Response resp;

//     Future<http.Response> makeRequest() async {
//       switch (method) {
//         case 'GET':
//           return http.get(uri, headers: _authHeaders);
//         case 'POST':
//           return http.post(uri,
//               headers: _authHeaders,
//               body: body != null ? jsonEncode(body) : null);
//         case 'PATCH':
//           return http.patch(uri,
//               headers: _authHeaders,
//               body: body != null ? jsonEncode(body) : null);
//         case 'DELETE':
//           return http.delete(uri, headers: _authHeaders);
//         default:
//           throw Exception('Unknown method: $method');
//       }
//     }

//     resp = await makeRequest();

//     if (resp.statusCode == 401 && _refreshToken != null) {
//       final refreshed = await _tryRefresh();
//       if (refreshed) {
//         resp = await makeRequest();
//       } else {
//         // ✅ FIX: refresh token is expired/invalid — clear tokens so
//         // isLoggedIn becomes false and AuthProvider can trigger logout
//         await clearTokens();
//       }
//     }

//     return resp;
//   }

//   // ── AUTH ──────────────────────────────────────────────────────────────────

//   Future<Map<String, dynamic>> login(String email, String password) async {
//     final resp = await http.post(
//       Uri.parse('$kBaseUrl/auth/login/'),
//       headers: {'Content-Type': 'application/json'},
//       body: jsonEncode({'email': email, 'password': password}),
//     );
//     final data = jsonDecode(resp.body) as Map<String, dynamic>;
//     if (resp.statusCode == 200) {
//       await saveTokens(data['access'], data['refresh']);
//     }
//     return {'statusCode': resp.statusCode, ...data};
//   }

//   Future<Map<String, dynamic>> register(
//       String email, String username, String password) async {
//     final resp = await http.post(
//       Uri.parse('$kBaseUrl/auth/register/'),
//       headers: {'Content-Type': 'application/json'},
//       body: jsonEncode({
//         'email': email,
//         'username': username,
//         'password': password,
//         'password2': password,
//       }),
//     );
//     final data = jsonDecode(resp.body) as Map<String, dynamic>;
//     if (resp.statusCode == 201) {
//       await saveTokens(data['access'], data['refresh']);
//     }
//     return {'statusCode': resp.statusCode, ...data};
//   }

//   Future<void> logout() async => clearTokens();

//   // ── Desktop — Forgot Password ─────────────────────────────────────────────
//   // Sends a reset link via streamai51@gmail.com (no auth required).

//   Future<Map<String, dynamic>> desktopForgotPassword(String email) async {
//     try {
//       final resp = await http.post(
//         Uri.parse('$kBaseUrl/auth/desktop/forgot-password/'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'email': email}),
//       );
//       final data = jsonDecode(resp.body) as Map<String, dynamic>;
//       if (resp.statusCode == 200) {
//         return {'ok': true, 'detail': data['detail']};
//       }
//       return {'ok': false, 'error': data['error'] ?? 'Request failed.'};
//     } catch (_) {
//       return {'ok': false, 'error': 'Connection error.'};
//     }
//   }

//   // ── Desktop — Verify OTP & Reset Password ─────────────────────────────────
//   // Verifies the 6-digit OTP code and sets a new password (no auth required).

//   Future<Map<String, dynamic>> desktopVerifyOTP({
//     required String email,
//     required String code,
//     required String newPassword,
//     required String confirmPassword,
//   }) async {
//     try {
//       final resp = await http.post(
//         Uri.parse('$kBaseUrl/auth/desktop/verify-otp/'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email,
//           'code': code,
//           'new_password': newPassword,
//           'confirm_password': confirmPassword,
//         }),
//       );
//       final data = jsonDecode(resp.body) as Map<String, dynamic>;
//       if (resp.statusCode == 200) {
//         return {'ok': true, 'detail': data['detail']};
//       }
//       return {'ok': false, 'error': data['error'] ?? 'Verification failed.'};
//     } catch (_) {
//       return {'ok': false, 'error': 'Connection error.'};
//     }
//   }

//   // ── Desktop — Change Password ─────────────────────────────────────────────
//   // Requires a valid access token. Confirmation email sent via Gmail.

//   Future<Map<String, dynamic>> desktopChangePassword({
//     required String currentPassword,
//     required String newPassword,
//     required String confirmPassword,
//   }) async {
//     try {
//       final resp = await _request(
//         'POST',
//         '/auth/desktop/change-password/',
//         body: {
//           'current_password': currentPassword,
//           'new_password': newPassword,
//           'confirm_password': confirmPassword,
//         },
//       );
//       final data = jsonDecode(resp.body) as Map<String, dynamic>;
//       if (resp.statusCode == 200) {
//         return {'ok': true, 'detail': data['detail']};
//       }
//       return {
//         'ok': false,
//         'error': data['error'] ?? 'Failed to change password.'
//       };
//     } catch (_) {
//       return {'ok': false, 'error': 'Connection error.'};
//     }
//   }

//   // ── PROFILE ───────────────────────────────────────────────────────────────

//   Future<Map<String, dynamic>> getMe() async {
//     final resp = await _request('GET', '/auth/me/');
//     return jsonDecode(resp.body) as Map<String, dynamic>;
//   }

//   Future<Map<String, dynamic>> getDashboard({
//     int days = 30,
//     int activityPage = 1,
//     int activityPageSize = 8,
//   }) async {
//     final resp = await _request('GET',
//         '/auth/dashboard/?days=$days&activity_page=$activityPage&activity_page_size=$activityPageSize');
//     final data = jsonDecode(resp.body) as Map<String, dynamic>;
//     data['statusCode'] = resp.statusCode;
//     return data;
//   }

//   Future<Map<String, dynamic>> poll() async {
//     final resp = await _request('GET', '/auth/poll/');
//     // ✅ FIX: check status before parsing so a 401 doesn't crash the poller
//     if (resp.statusCode != 200) {
//       throw Exception('Poll failed: ${resp.statusCode}');
//     }
//     return jsonDecode(resp.body) as Map<String, dynamic>;
//   }

//   Future<List<dynamic>> getUsageHistory() async {
//     final resp = await _request('GET', '/auth/usage/');
//     return jsonDecode(resp.body) as List<dynamic>;
//   }

//   // ── API KEYS ──────────────────────────────────────────────────────────────

//   Future<List<dynamic>> getApiKeys() async {
//     final resp = await _request('GET', '/keys/');
//     return jsonDecode(resp.body) as List<dynamic>;
//   }

//   Future<Map<String, dynamic>> createApiKey(String name) async {
//     final resp = await _request('POST', '/keys/', body: {'name': name});
//     return jsonDecode(resp.body) as Map<String, dynamic>;
//   }

//   Future<bool> revokeApiKey(int keyId) async {
//     final resp = await _request('DELETE', '/keys/$keyId/');
//     return resp.statusCode == 200;
//   }

//   Future<bool> renameApiKey(int keyId, String name) async {
//     final resp =
//         await _request('PATCH', '/keys/$keyId/rename/', body: {'name': name});
//     return resp.statusCode == 200;
//   }

//   // ── STREAMING ─────────────────────────────────────────────────────────────

//   Future<Map<String, dynamic>> getRealtimeToken(
//     String model, {
//     String? faceImageBase64,
//     String? prompt,
//   }) async {
//     final body = <String, dynamic>{'model': model};
//     if (faceImageBase64 != null) body['face_image'] = faceImageBase64;
//     if (prompt != null && prompt.isNotEmpty) body['prompt'] = prompt;
//     final resp = await _request('POST', '/stream/token/', body: body);
//     return {
//       'statusCode': resp.statusCode,
//       ...jsonDecode(resp.body) as Map<String, dynamic>
//     };
//   }

//   Future<Map<String, dynamic>> generateVideo({
//     required String prompt,
//     String model = 'lucy-pro-t2v',
//     String resolution = '720p',
//   }) async {
//     final resp = await _request('POST', '/stream/generate/video/', body: {
//       'prompt': prompt,
//       'model': model,
//       'resolution': resolution,
//     });
//     return {
//       'statusCode': resp.statusCode,
//       ...jsonDecode(resp.body) as Map<String, dynamic>
//     };
//   }

//   Future<Map<String, dynamic>> generateImage({
//     required String prompt,
//     String model = 'lucy-image',
//   }) async {
//     final resp = await _request('POST', '/stream/generate/image/', body: {
//       'prompt': prompt,
//       'model': model,
//     });
//     return {
//       'statusCode': resp.statusCode,
//       ...jsonDecode(resp.body) as Map<String, dynamic>
//     };
//   }

//   // ── PAYMENTS — SHARED ─────────────────────────────────────────────────────

//   Future<List<dynamic>> getCreditPacks() async {
//     final resp = await http.get(Uri.parse('$kBaseUrl/auth/packs/'));
//     return jsonDecode(resp.body) as List<dynamic>;
//   }

//   Future<Map<String, dynamic>> getPaymentHistory(
//       {int page = 1, int pageSize = 10}) async {
//     final resp =
//         await _request('GET', '/payments/?page=$page&page_size=$pageSize');
//     final data = jsonDecode(resp.body);
//     if (data is Map<String, dynamic>) return data;
//     return {
//       'results': data,
//       'count': (data as List).length,
//       'total_pages': 1,
//       'page': 1,
//       'page_size': pageSize
//     };
//   }

//   Future<Map<String, dynamic>> getPaymentStatus(int paymentId) async {
//     final resp = await _request('GET', '/auth/$paymentId/status/');
//     return jsonDecode(resp.body) as Map<String, dynamic>;
//   }

//   // ── PAYMENTS — CRYPTO (NOWPayments) ──────────────────────────────────────

//   /// Creates a NOWPayments crypto invoice.
//   /// [currency]: btc | eth | usdttrc20 | usdterc20 | usdc | bnb | ltc | sol
//   Future<Map<String, dynamic>> createCryptoPayment({
//     required String packId,
//     required String currency,
//   }) async {
//     final resp = await _request('POST', '/auth/payments/create/', body: {
//       'pack_id': packId,
//       'currency': currency,
//     });
//     return {
//       'statusCode': resp.statusCode,
//       ...jsonDecode(resp.body) as Map<String, dynamic>
//     };
//   }

//   // ── PAYMENTS — FLUTTERWAVE (Card / Bank / Mobile Money) ───────────────────

//   /// Creates a Flutterwave payment link.
//   /// [currency]: NGN | GHS | KES | ZAR | UGX | TZS | USD | EUR | GBP
//   Future<Map<String, dynamic>> createFlutterwavePayment({
//     required String packId,
//     required String currency,
//   }) async {
//     final resp =
//         await _request('POST', '/auth/payments/flutterwave/initiate/', body: {
//       'pack_id': packId,
//       'currency': currency,
//     });
//     return {
//       'statusCode': resp.statusCode,
//       ...jsonDecode(resp.body) as Map<String, dynamic>
//     };
//   }

//   /// Verifies a Flutterwave payment after user returns from payment page.
//   /// [txRef]: the tx_ref returned by createFlutterwavePayment
//   /// [transactionId]: optional — Flutterwave appends this to redirect URL as ?transaction_id=
//   Future<Map<String, dynamic>> verifyFlutterwavePayment({
//     required String txRef,
//     String? transactionId,
//   }) async {
//     final query = transactionId != null ? '?transaction_id=$transactionId' : '';
//     final resp = await _request(
//         'GET', '/auth/payments/flutterwave/verify/$txRef/$query');
//     return {
//       'statusCode': resp.statusCode,
//       ...jsonDecode(resp.body) as Map<String, dynamic>
//     };
//   }

//   // ── LEGACY ALIAS (keeps old billing screen code working) ─────────────────
//   Future<Map<String, dynamic>> createPayment({
//     required String packId,
//     required String currency,
//   }) =>
//       createCryptoPayment(packId: packId, currency: currency);

//   // ── WALLET ADDRESSES ──────────────────────────────────────────────────────
//   /// Returns the crypto wallet addresses from the server.
//   /// Map key = currency id (e.g. "usdttrc20"), value = { address, label, network }
//   Future<Map<String, dynamic>> getWalletAddresses() async {
//     final resp = await _request('GET', '/auth/payments/wallets/');
//     if (resp.statusCode == 200) {
//       return jsonDecode(resp.body) as Map<String, dynamic>;
//     }
//     return {};
//   }

//   /// Returns {"crypto": [...], "fiat": [...]} — both lists come from the DB.
//   Future<Map<String, dynamic>> getCurrencies() async {
//     final resp = await _request('GET', '/auth/payments/currencies/');
//     if (resp.statusCode == 200) {
//       return jsonDecode(resp.body) as Map<String, dynamic>;
//     }
//     return {'crypto': [], 'fiat': []};
//   }

//   // ── PAYMENT PROOF ─────────────────────────────────────────────────────────
//   /// Uploads payment proof (screenshot/receipt) for a pending crypto payment.
//   Future<Map<String, dynamic>> submitPaymentProof({
//     required int paymentId,
//     required File imageFile,
//     String? txHash,
//     String? notes,
//   }) async {
//     final uri = Uri.parse('$kBaseUrl/auth/payments/$paymentId/proof/');

//     Future<http.Response> doSend() async {
//       final req = http.MultipartRequest('POST', uri);
//       if (_accessToken != null) {
//         req.headers['Authorization'] = 'Bearer $_accessToken';
//       }
//       req.files.add(
//           await http.MultipartFile.fromPath('proof_image', imageFile.path));
//       if (txHash != null && txHash.isNotEmpty) req.fields['tx_hash'] = txHash;
//       if (notes != null && notes.isNotEmpty) req.fields['notes'] = notes;
//       final streamed = await req.send();
//       return http.Response.fromStream(streamed);
//     }

//     Map<String, dynamic> safeParseBody(http.Response resp) {
//       final body = resp.body.trim();
//       try {
//         final decoded = jsonDecode(body);
//         if (decoded is Map<String, dynamic>) return decoded;
//         return {'detail': decoded.toString()};
//       } catch (_) {
//         final hint = body.isNotEmpty
//             ? 'Server error (${resp.statusCode}): ${body.substring(0, body.length.clamp(0, 120))}'
//             : 'Server returned status ${resp.statusCode} with no body.';
//         return {'error': hint};
//       }
//     }

//     try {
//       var resp = await doSend();

//       // Token expired — refresh and retry once
//       if (resp.statusCode == 401 && _refreshToken != null) {
//         final refreshed = await _tryRefresh();
//         if (refreshed) {
//           resp = await doSend();
//         } else {
//           // ✅ FIX: consistent with _request — clear tokens on failed refresh
//           await clearTokens();
//         }
//       }

//       return {'statusCode': resp.statusCode, ...safeParseBody(resp)};
//     } catch (e) {
//       return {'statusCode': 0, 'error': e.toString()};
//     }
//   }

//   // ── DEPOSIT ADDRESSES (user-unique, auto-credit) ─────────────────────────
//   // Add this method to ApiService in api_service.dart.
//   // GET /api/v1/payments/deposit/address/?network=<network>&token=<token>
//   // Returns the user's unique deposit address for the given network+token,
//   // creating it on first call. Response includes: address, network,
//   // network_label, token, token_label, note, pending_deposits.

//   Future<Map<String, dynamic>> getDepositAddress({
//     required String network, // 'bep20' | 'solana'
//     required String token, // 'USDT'  | 'USDC'
//   }) async {
//     final resp = await _request(
//       'GET',
//       '/payments/deposit/address/?network=$network&token=$token',
//     );
//     if (resp.statusCode == 200) {
//       return jsonDecode(resp.body) as Map<String, dynamic>;
//     }
//     return {'address': ''};
//   }

//   // GET /api/v1/payments/deposit/my-addresses/
//   // Returns (and lazily creates) ALL four deposit addresses in one request.
//   // Response: { "deposit_addresses": [ { network, token, address, ... }, ... ] }
//   Future<Map<String, String>> getAllDepositAddresses() async {
//     final resp = await _request('GET', '/payments/deposit/my-addresses/');
//     if (resp.statusCode == 200) {
//       final body = jsonDecode(resp.body) as Map<String, dynamic>;
//       final list = (body['deposit_addresses'] as List? ?? []);
//       final result = <String, String>{};
//       for (final item in list) {
//         final network = (item['network'] as String? ?? '').toLowerCase();
//         final token = (item['token'] as String? ?? '').toUpperCase();
//         final address = item['address'] as String? ?? '';
//         if (network.isNotEmpty && token.isNotEmpty) {
//           result['$network:$token'] = address;
//         }
//       }
//       return result;
//     }
//     return {};
//   }
// }

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../config/app_version.dart';
import '../models/maintenance_info.dart';
import '../utils/maintenance_exception.dart';
import 'app_gate.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Change this to your real Django server URL ──
// const String kBaseUrl = 'https://realfaceai.app/api/v1';

// Dev: this Mac's LAN IP (phones can't reach 127.0.0.1). Changes with the
// network — check with `ipconfig getifaddr en0`.
const String kBaseUrl = 'http://10.112.60.138:8000/api/v1';

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  String? _accessToken;
  String? _refreshToken;

  // ── Token Management ──────────────────────────────────────────────────────

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    if (await _isNewMacInstall(prefs)) {
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
    }
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  /// macOS keeps preferences (and so the saved login) when the app is
  /// deleted, so a reinstall would sign straight back in. Every install or
  /// update copies a new bundle, which gives the executable a new inode; a
  /// changed inode means "new install" and the saved session is dropped.
  /// Skipped in debug, where every build replaces the executable.
  Future<bool> _isNewMacInstall(SharedPreferences prefs) async {
    if (!Platform.isMacOS || kDebugMode) return false;
    const key = 'install_id';
    try {
      final result = await Process.run(
          '/usr/bin/stat', ['-f', '%d:%i', Platform.resolvedExecutable]);
      final installId = (result.stdout as String).trim();
      if (result.exitCode != 0 || installId.isEmpty) return false;
      if (prefs.getString(key) == installId) return false;
      await prefs.setString(key, installId);
      return true;
    } catch (_) {
      return false; // can't tell — keep the session rather than guess
    }
  }

  Future<void> saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  bool get isLoggedIn => _accessToken != null;
  String? get accessToken => _accessToken;

  // Every request carries the build's version so the server can refuse
  // outdated builds (426) once a mandatory update is published.
  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ...kAppVersionHeaders,
      };

  Map<String, String> get _authHeaders => {
        ..._jsonHeaders,
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/refresh/'),
        headers: _jsonHeaders,
        body: jsonEncode({'refresh': _refreshToken}),
      );
      // A suspended account's refresh is refused with 403 account_suspended.
      AppGate.instance.inspect(resp);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await saveTokens(data['access'], _refreshToken!);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    final resp = await http.post(
      Uri.parse('$kBaseUrl/auth/login/'),
      headers: _jsonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    AppGate.instance.inspect(resp); // 426 update required / 403 suspended
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      await saveTokens(data['access'], data['refresh']);
    }
    return {'statusCode': resp.statusCode, ...data};
  }

  Future<Map<String, dynamic>> register(
      String email, String username, String password) async {
    final resp = await http.post(
      Uri.parse('$kBaseUrl/auth/register/'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'email': email,
        'username': username,
        'password': password,
        'password2': password,
      }),
    );

    AppGate.instance.inspect(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    if (resp.statusCode == 201) {
      await saveTokens(data['access'], data['refresh']);
    }
    return {'statusCode': resp.statusCode, ...data};
  }

  Future<void> logout() async => clearTokens();

  // ── Desktop — Forgot Password ─────────────────────────────────────────────
  // Sends a reset link via streamai51@gmail.com (no auth required).

  Future<Map<String, dynamic>> desktopForgotPassword(String email) async {
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/desktop/forgot-password/'),
        headers: _jsonHeaders,
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'ok': true, 'detail': data['detail']};
      }
      return {'ok': false, 'error': data['error'] ?? 'Request failed.'};
    } catch (_) {
      return {'ok': false, 'error': 'Connection error.'};
    }
  }

  // ── Desktop — Verify OTP & Reset Password ─────────────────────────────────
  // Verifies the 6-digit OTP code and sets a new password (no auth required).

  Future<Map<String, dynamic>> desktopVerifyOTP({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/desktop/verify-otp/'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'email': email,
          'code': code,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'ok': true, 'detail': data['detail']};
      }
      return {'ok': false, 'error': data['error'] ?? 'Verification failed.'};
    } catch (_) {
      return {'ok': false, 'error': 'Connection error.'};
    }
  }

  // ── Desktop — Change Password ─────────────────────────────────────────────
  // Requires a valid access token. Confirmation email sent via Gmail.

  Future<Map<String, dynamic>> desktopChangePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final resp = await _request(
        'POST',
        '/auth/desktop/change-password/',
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        },
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'ok': true, 'detail': data['detail']};
      }
      return {
        'ok': false,
        'error': data['error'] ?? 'Failed to change password.'
      };
    } catch (_) {
      return {'ok': false, 'error': 'Connection error.'};
    }
  }

  // ── PROFILE ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMe() async {
    final resp = await _request('GET', '/auth/me/');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    data['statusCode'] = resp.statusCode;
    return data;
  }

  Future<Map<String, dynamic>> getDashboard({
    int days = 30,
    int activityPage = 1,
    int activityPageSize = 8,
  }) async {
    final resp = await _request('GET',
        '/auth/dashboard/?days=$days&activity_page=$activityPage&activity_page_size=$activityPageSize');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    data['statusCode'] = resp.statusCode;
    return data;
  }

  Future<Map<String, dynamic>> poll() async {
    final resp = await _request('GET', '/auth/poll/');
    // ✅ FIX: check status before parsing so a 401 doesn't crash the poller
    if (resp.statusCode != 200) {
      throw Exception('Poll failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getUsageHistory() async {
    final resp = await _request('GET', '/auth/usage/');
    return jsonDecode(resp.body) as List<dynamic>;
  }

  // ── API KEYS ──────────────────────────────────────────────────────────────

  Future<List<dynamic>> getApiKeys() async {
    final resp = await _request('GET', '/keys/');
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createApiKey(String name) async {
    final resp = await _request('POST', '/keys/', body: {'name': name});
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<bool> revokeApiKey(int keyId) async {
    final resp = await _request('DELETE', '/keys/$keyId/');
    return resp.statusCode == 200;
  }

  Future<bool> renameApiKey(int keyId, String name) async {
    final resp =
        await _request('PATCH', '/keys/$keyId/rename/', body: {'name': name});
    return resp.statusCode == 200;
  }

  // ── STREAMING ─────────────────────────────────────────────────────────────

  /// Called every 10 s while streaming. Returns {stop, credits_remaining}.
  Future<Map<String, dynamic>> streamHeartbeat() async {
    final resp = await _request('POST', '/stream/heartbeat/');
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>,
    };
  }

  /// Starts a stream session. The backend picks the model and returns it as
  /// `model` (plus `model_name`, `prompt`, `enhance`) — the app never sends
  /// or hard-codes one.
  Future<Map<String, dynamic>> getRealtimeToken({
    String? faceImageBase64,
    String? prompt,
  }) async {
    final body = <String, dynamic>{};
    if (faceImageBase64 != null) body['face_image'] = faceImageBase64;
    if (prompt != null && prompt.isNotEmpty) body['prompt'] = prompt;
    final resp = await _request('POST', '/stream/token/', body: body);
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  // ── PAYMENTS — SHARED ─────────────────────────────────────────────────────

  /// Decodes a JSON object body without ever throwing. A proxy/hosting error
  /// page (HTML) becomes {'error': ...} instead of a FormatException that
  /// silently kills the calling flow.
  Map<String, dynamic> _safeJson(http.Response resp) {
    final body = resp.body.trim();
    if (body.isEmpty) {
      return {'error': 'Server returned status ${resp.statusCode} with no body.'};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'detail': decoded.toString()};
    } catch (_) {
      return {
        'error': resp.statusCode >= 500
            ? 'The server had a problem (${resp.statusCode}). Please try again.'
            : 'Unexpected server response (${resp.statusCode}).',
      };
    }
  }

  Future<List<dynamic>> getCreditPacks() async {
    final resp =
        await http.get(Uri.parse('$kBaseUrl/auth/packs/'), headers: _jsonHeaders);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getPaymentHistory(
      {int page = 1, int pageSize = 10}) async {
    final resp =
        await _request('GET', '/payments/?page=$page&page_size=$pageSize');
    final data = jsonDecode(resp.body);
    if (data is Map<String, dynamic>) return data;
    return {
      'results': data,
      'count': (data as List).length,
      'total_pages': 1,
      'page': 1,
      'page_size': pageSize
    };
  }

  /// Status + full payment instructions (wallet, amount, network, proof_count).
  /// Used both for polling and for reopening the "Payment Pending" dialog.
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async {
    final resp = await _request('GET', '/auth/$paymentId/status/')
        .timeout(const Duration(seconds: 30));
    return {'statusCode': resp.statusCode, ..._safeJson(resp)};
  }

  // ── PAYMENTS — CRYPTO (manual, admin-confirmed) ──────────────────────────

  /// Creates (or reuses a fresh) pending crypto payment.
  /// Throws [TimeoutException] if the server doesn't answer in 45 s — the
  /// billing screen catches that and checks history for the payment.
  Future<Map<String, dynamic>> createCryptoPayment({
    required String packId,
    required String currency,
  }) async {
    final resp = await _request('POST', '/auth/payments/create/', body: {
      'pack_id': packId,
      'currency': currency,
    }).timeout(const Duration(seconds: 45));
    return {'statusCode': resp.statusCode, ..._safeJson(resp)};
  }

  // ── PAYMENTS — FLUTTERWAVE (Card / Bank / Mobile Money) ───────────────────

  /// Creates a Flutterwave payment link.
  /// [currency]: NGN | GHS | KES | ZAR | UGX | TZS | USD | EUR | GBP
  Future<Map<String, dynamic>> createFlutterwavePayment({
    required String packId,
    required String currency,
  }) async {
    final resp =
        await _request('POST', '/auth/payments/flutterwave/initiate/', body: {
      'pack_id': packId,
      'currency': currency,
    });
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  /// Verifies a Flutterwave payment after user returns from payment page.
  /// [txRef]: the tx_ref returned by createFlutterwavePayment
  /// [transactionId]: optional — Flutterwave appends this to redirect URL as ?transaction_id=
  Future<Map<String, dynamic>> verifyFlutterwavePayment({
    required String txRef,
    String? transactionId,
  }) async {
    final query = transactionId != null ? '?transaction_id=$transactionId' : '';
    final resp = await _request(
        'GET', '/auth/payments/flutterwave/verify/$txRef/$query');
    return {
      'statusCode': resp.statusCode,
      ...jsonDecode(resp.body) as Map<String, dynamic>
    };
  }

  // ── LEGACY ALIAS (keeps old billing screen code working) ─────────────────
  Future<Map<String, dynamic>> createPayment({
    required String packId,
    required String currency,
  }) =>
      createCryptoPayment(packId: packId, currency: currency);

  // ── WALLET ADDRESSES ──────────────────────────────────────────────────────
  /// Returns the crypto wallet addresses from the server.
  /// Map key = currency id (e.g. "usdttrc20"), value = { address, label, network }
  Future<Map<String, dynamic>> getWalletAddresses() async {
    final resp = await _request('GET', '/auth/payments/wallets/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {};
  }

  /// Returns {"crypto": [...], "fiat": [...]} — both lists come from the DB.
  Future<Map<String, dynamic>> getCurrencies() async {
    final resp = await _request('GET', '/auth/payments/currencies/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {'crypto': [], 'fiat': []};
  }

  // ── PAYMENT PROOF ─────────────────────────────────────────────────────────

  /// Every proof the user has sent for [paymentId], newest first:
  /// { payment_id, status, can_upload, count, results: [ {id, submitted_at,
  ///   tx_hash, notes, has_image, image_path, original_filename}, … ] }
  Future<Map<String, dynamic>> getPaymentProofs(String paymentId) async {
    final resp = await _request('GET', '/auth/payments/$paymentId/proofs/')
        .timeout(const Duration(seconds: 30));
    return {'statusCode': resp.statusCode, ..._safeJson(resp)};
  }

  /// Full URL for a proof's `image_path` (as returned by the API).
  String proofImageUrl(String imagePath) => '$kBaseUrl$imagePath';

  /// Headers needed to load a proof image with Image.network.
  Map<String, String> get imageHeaders => {
        ...kAppVersionHeaders,
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  /// Generates a random per-attempt key used for idempotency. Kept as its
  /// own function (rather than a package) so we don't need to add a new
  /// dependency just for this.
  String _generateIdempotencyKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Uploads payment proof (screenshot/receipt) for a pending crypto payment.
  ///
  /// The server stores the image on its own disk BEFORE replying, so a
  /// 200/201 means the image really is on the server. The response carries
  /// the stored proof: { detail, proof: {...}, proof_count }.
  ///
  /// Idempotent: one `Idempotency-Key` is generated per submission and reused
  /// across retries of it, so a retry after a dropped connection returns the
  /// already-stored proof instead of creating a duplicate.
  Future<Map<String, dynamic>> submitPaymentProof({
    required String paymentId,
    required File imageFile,
    String? txHash,
    String? notes,
  }) async {
    final uri = Uri.parse('$kBaseUrl/auth/payments/$paymentId/proof/');
    final idempotencyKey = _generateIdempotencyKey();

    Future<http.Response> doSend() async {
      final req = http.MultipartRequest('POST', uri);
      if (_accessToken != null) {
        req.headers['Authorization'] = 'Bearer $_accessToken';
      }
      req.headers['Idempotency-Key'] = idempotencyKey;
      req.headers.addAll(kAppVersionHeaders);
      req.files.add(
          await http.MultipartFile.fromPath('proof_image', imageFile.path));
      if (txHash != null && txHash.isNotEmpty) req.fields['tx_hash'] = txHash;
      if (notes != null && notes.isNotEmpty) req.fields['notes'] = notes;
      final streamed = await req.send().timeout(const Duration(seconds: 120));
      return http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 60));
    }

    // Up to 3 attempts total (1 original + 2 retries). Retries only kick in
    // for connection-level failures — never for an actual server reply —
    // and always reuse the same Idempotency-Key.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final isLastAttempt = attempt == maxAttempts;
      try {
        var resp = await doSend();

        // Token expired — refresh and retry once.
        if (resp.statusCode == 401 && _refreshToken != null) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            resp = await doSend();
          } else {
            await clearTokens();
          }
        }

        _checkForMaintenance(resp);
        AppGate.instance.inspect(resp);
        return {'statusCode': resp.statusCode, ..._safeJson(resp)};
      } on TimeoutException {
        if (isLastAttempt) {
          return {
            'statusCode': 0,
            'error':
                'Upload timed out. Your connection may be slow — please try again.',
          };
        }
      } on SocketException {
        if (isLastAttempt) {
          return {
            'statusCode': 0,
            'error': 'Connection error. Check your internet and try again.',
          };
        }
      } on http.ClientException {
        if (isLastAttempt) {
          return {
            'statusCode': 0,
            'error': 'Connection was interrupted. Please try again.',
          };
        }
      } on MaintenanceException {
        rethrow;
      } catch (e) {
        // Not a connection issue (e.g. failed to read the file) — no point
        // retrying with the same broken input.
        return {'statusCode': 0, 'error': 'Could not read the image: $e'};
      }
      await Future.delayed(Duration(milliseconds: 800 * attempt));
    }
    return {
      'statusCode': 0,
      'error': 'Upload failed after multiple attempts. Please try again.',
    };
  }

  // ── DEPOSIT ADDRESSES (user-unique, auto-credit) ─────────────────────────
  // Add this method to ApiService in api_service.dart.
  // GET /api/v1/payments/deposit/address/?network=<network>&token=<token>
  // Returns the user's unique deposit address for the given network+token,
  // creating it on first call. Response includes: address, network,
  // network_label, token, token_label, note, pending_deposits.

  Future<Map<String, dynamic>> getDepositAddress({
    required String network, // 'bep20' | 'solana'
    required String token, // 'USDT'  | 'USDC'
  }) async {
    final resp = await _request(
      'GET',
      '/payments/deposit/address/?network=$network&token=$token',
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return {'address': ''};
  }

  // GET /api/v1/payments/deposit/my-addresses/
  // Returns (and lazily creates) ALL four deposit addresses in one request.
  // Response: { "deposit_addresses": [ { network, token, address, ... }, ... ] }
  Future<Map<String, String>> getAllDepositAddresses() async {
    final resp = await _request('GET', '/payments/deposit/my-addresses/');
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (body['deposit_addresses'] as List? ?? []);
      final result = <String, String>{};
      for (final item in list) {
        final network = (item['network'] as String? ?? '').toLowerCase();
        final token = (item['token'] as String? ?? '').toUpperCase();
        final address = item['address'] as String? ?? '';
        if (network.isNotEmpty && token.isNotEmpty) {
          result['$network:$token'] = address;
        }
      }
      return result;
    }
    return {};
  }

  // ── Core request method ───────────────────────────────────────────────────
  //
  // All responses are passed through _checkForMaintenance() before being
  // returned to callers. A 503 with maintenance=true throws
  // MaintenanceException — callers and AuthProvider catch this and navigate
  // to MaintenanceScreen automatically.

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$kBaseUrl$path');

    Future<http.Response> makeRequest() async {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: _authHeaders);
        case 'POST':
          return http.post(uri,
              headers: _authHeaders,
              body: body != null ? jsonEncode(body) : null);
        case 'PATCH':
          return http.patch(uri,
              headers: _authHeaders,
              body: body != null ? jsonEncode(body) : null);
        case 'DELETE':
          return http.delete(uri, headers: _authHeaders);
        default:
          throw Exception('Unknown method: $method');
      }
    }

    var resp = await makeRequest();

    // ── Maintenance check — runs before any other status handling ─────────
    _checkForMaintenance(resp);

    // ── Forced update (426) / suspended account (403) ─────────────────────
    // Raises the app-wide gate; the router swaps to the blocking screen.
    // The response is still returned so callers can show its 'error'.
    AppGate.instance.inspect(resp);

    // ── 401 → try refresh, then retry ────────────────────────────────────
    if (resp.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        resp = await makeRequest();
        _checkForMaintenance(resp); // check again after retry
        AppGate.instance.inspect(resp);
      } else {
        await clearTokens();
      }
    }

    return resp;
  }

  /// Throws [MaintenanceException] if the response is a 503 maintenance response.
  /// Does nothing for any other status code.
  void _checkForMaintenance(http.Response resp) {
    if (resp.statusCode == 503) {
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['maintenance'] == true) {
          throw MaintenanceException(MaintenanceInfo.fromJson(body));
        }
      } on MaintenanceException {
        rethrow; // let it propagate
      } catch (_) {
        // 503 but not a maintenance response — treat as a normal server error
      }
    }
  }

  // ── Health check ──────────────────────────────────────────────────────────
  //
  // Lightweight endpoint used by MaintenanceScreen to check if the server
  // is back up. Throws MaintenanceException if still in maintenance,
  // SocketException / TimeoutException for network failures.

  Future<void> healthCheck() async {
    final resp = await http.get(
      Uri.parse('$kBaseUrl/health/'),
      headers: _jsonHeaders,
    ).timeout(const Duration(seconds: 10));
    _checkForMaintenance(resp);
    // Any non-503 response means the server is reachable — we're back up.
  }
}