import '../widgets/brand.dart';

/// Response of GET /app/latest-version/ — and of any 426 "update required"
/// response, which carries the same fields.
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? releaseNotes;

  /// Legacy flag. For builds that send their version it equals [forceUpdate].
  final bool isMandatory;

  /// True when this build is below the newest mandatory release and must be
  /// updated before the app can be used.
  final bool forceUpdate;

  /// True when a newer build than this one is published.
  final bool updateAvailable;

  final String? minSupportedVersion;
  final String? message;
  final String platform;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.releaseNotes,
    this.isMandatory = false,
    this.forceUpdate = false,
    this.updateAvailable = false,
    this.minSupportedVersion,
    this.message,
    required this.platform,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final mandatory = (json['mandatory'] as bool?) ?? false;
    final notes = json['release_notes'] as String?;
    final msg = (json['message'] as String?) ?? (json['error'] as String?);
    final url = json['download_url'] as String?;
    return UpdateInfo(
      version: (json['version'] as String?) ?? '',
      downloadUrl:
          (url != null && url.isNotEmpty) ? url : '${Brand.url}/download',
      releaseNotes: (notes != null && notes.isNotEmpty) ? notes : null,
      isMandatory: mandatory,
      forceUpdate: (json['force_update'] as bool?) ??
          (json['update_required'] as bool?) ??
          false,
      updateAvailable: (json['update_available'] as bool?) ?? false,
      minSupportedVersion: json['min_supported_version'] as String?,
      message: (msg != null && msg.isNotEmpty) ? msg : null,
      platform: (json['platform'] as String?) ?? 'unknown',
    );
  }
}
