import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/account_status.dart';
import '../models/update_info.dart';

/// App-wide blocking states decided by the server.
///
///   requiredUpdate — this build is below the newest mandatory release.
///                    Comes from a 426 on any API call, or from the update
///                    check (`force_update: true`).
///   suspension     — the signed-in account is suspended
///                    (403 `account_suspended` on any call, including login).
///
/// The router listens to this and shows a full-screen gate while either is
/// set. ApiService feeds every response through [inspect], so a gate appears
/// on the very next request after an admin acts — no polling needed.
class AppGate extends ChangeNotifier {
  static final AppGate instance = AppGate._();
  AppGate._();

  UpdateInfo? _requiredUpdate;
  AccountStatus? _suspension;
  String? _suspensionMessage;

  /// Called when the server reports a (non-suspended) restriction, e.g. a
  /// 403 `account_frozen` from a write. AuthProvider uses it to update the
  /// signed-in user's status without waiting for the next poll.
  void Function(AccountStatus status)? onAccountStatus;

  UpdateInfo? get requiredUpdate => _requiredUpdate;
  AccountStatus? get suspension => _suspension;
  String? get suspensionMessage => _suspensionMessage;
  bool get isBlocked => _requiredUpdate != null || _suspension != null;

  /// Looks at an API response and raises a gate if it is a gate response.
  /// Returns true when the response was handled as one.
  bool inspect(http.Response resp) {
    if (resp.statusCode != 426 && resp.statusCode != 403) return false;

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return false;
      body = decoded;
    } catch (_) {
      return false;
    }

    if (resp.statusCode == 426 &&
        (body['update_required'] == true || body['code'] == 'update_required')) {
      requireUpdate(UpdateInfo.fromJson(body));
      return true;
    }

    if (resp.statusCode == 403) {
      switch (body['code']) {
        case 'account_suspended':
          _setSuspension(
            AccountStatus.fromJson(body['account_status']),
            body['error'] as String?,
          );
          return true;
        case 'account_frozen':
          onAccountStatus?.call(AccountStatus.fromJson(body['account_status']));
          return true;
      }
    }
    return false;
  }

  void requireUpdate(UpdateInfo info) {
    final current = _requiredUpdate;
    if (current != null &&
        current.version == info.version &&
        current.downloadUrl == info.downloadUrl) {
      return;
    }
    _requiredUpdate = info;
    notifyListeners();
  }

  /// The server no longer requires an update (e.g. the mandatory release was
  /// pulled). Only the update check calls this.
  void clearRequiredUpdate() {
    if (_requiredUpdate == null) return;
    _requiredUpdate = null;
    notifyListeners();
  }

  void _setSuspension(AccountStatus status, String? message) {
    final suspended = status.isSuspended
        ? status
        : AccountStatus(
            state: AccountState.suspended,
            reason: status.reason,
            expiresAt: status.expiresAt,
            supportEmail: status.supportEmail,
          );
    if (_suspension == suspended && _suspensionMessage == message) return;
    _suspension = suspended;
    _suspensionMessage = message;
    notifyListeners();
  }

  /// The account is usable again, or the user chose to sign out.
  void clearSuspension() {
    if (_suspension == null) return;
    _suspension = null;
    _suspensionMessage = null;
    notifyListeners();
  }
}
