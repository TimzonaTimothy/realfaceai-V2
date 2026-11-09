class ApiKeyModel {
  final int id;
  final String name;
  final String prefix;
  final String? key; // Only present on creation
  final String createdAt;
  final String? lastUsedAt;

  ApiKeyModel({
    required this.id,
    required this.name,
    required this.prefix,
    this.key,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory ApiKeyModel.fromJson(Map<String, dynamic> json) {
    return ApiKeyModel(
      id:          json['id'] ?? 0,
      name:        json['name'] ?? 'My Key',
      prefix:      json['prefix'] ?? '',
      key:         json['key'],
      createdAt:   json['created_at'] ?? '',
      lastUsedAt:  json['last_used_at'],
    );
  }
}