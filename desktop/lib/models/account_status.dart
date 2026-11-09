import '../widgets/brand.dart';

enum AccountState { active, frozen, suspended }

/// Mirrors the backend's `account_status` object:
///   { status, reason, expires_at, changed_at, support_email }
///
/// active    — normal use.
/// frozen    — read-only: can view the account, but streaming, generation and
///             payments are refused by the server.
/// suspended — locked out entirely.
class AccountStatus {
  final AccountState state;
  final String reason;
  final DateTime? expiresAt;
  final String supportEmail;

  const AccountStatus({
    required this.state,
    this.reason = '',
    this.expiresAt,
    this.supportEmail = Brand.supportEmail,
  });

  static const active = AccountStatus(state: AccountState.active);

  bool get isActive => state == AccountState.active;
  bool get isFrozen => state == AccountState.frozen;
  bool get isSuspended => state == AccountState.suspended;

  factory AccountStatus.fromJson(dynamic json) {
    if (json is! Map) return AccountStatus.active;
    final raw = (json['status'] as String?)?.toLowerCase();
    final state = switch (raw) {
      'frozen' => AccountState.frozen,
      'suspended' => AccountState.suspended,
      _ => AccountState.active,
    };
    DateTime? expires;
    final e = json['expires_at'];
    if (e is String && e.isNotEmpty) expires = DateTime.tryParse(e)?.toLocal();
    final support = json['support_email'] as String?;
    return AccountStatus(
      state: state,
      reason: (json['reason'] as String?) ?? '',
      expiresAt: expires,
      supportEmail:
          (support != null && support.isNotEmpty) ? support : Brand.supportEmail,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccountStatus &&
      other.state == state &&
      other.reason == reason &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(state, reason, expiresAt);
}
