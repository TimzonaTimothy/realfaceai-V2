// lib/models/user.dart

import 'account_status.dart';

class UserModel {
  final int id;
  final String email;
  final String username;
  final double credits;
  final String plan;
  final bool isVerified;
  final String createdAt;

  /// active / frozen / suspended — see AccountStatus.
  final AccountStatus accountStatus;

  bool get isFrozen => accountStatus.isFrozen;

  UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.credits,
    required this.plan,
    required this.isVerified,
    required this.createdAt,
    this.accountStatus = AccountStatus.active,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:         json['id'] ?? 0,
      email:      json['email'] ?? '',
      username:   json['username'] ?? '',
      credits:    (json['credits'] ?? 0).toDouble(),
      plan:       json['plan'] ?? 'free',
      isVerified: json['is_verified'] ?? false,
      createdAt:  json['created_at'] ?? '',
      accountStatus: AccountStatus.fromJson(json['account_status']),
    );
  }

  UserModel copyWith({
    int?    id,
    String? email,
    String? username,
    double? credits,
    String? plan,
    bool?   isVerified,
    String? createdAt,
    AccountStatus? accountStatus,
  }) {
    return UserModel(
      id:         id         ?? this.id,
      email:      email      ?? this.email,
      username:   username   ?? this.username,
      credits:    credits    ?? this.credits,
      plan:       plan       ?? this.plan,
      isVerified: isVerified ?? this.isVerified,
      createdAt:  createdAt  ?? this.createdAt,
      accountStatus: accountStatus ?? this.accountStatus,
    );
  }
}