import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// The version of THIS build.
///
/// Bump it for every release, and publish a matching "App release" in Django
/// admin (same platform + version). The backend compares this value — sent on
/// every request as `X-App-Version` — against the newest mandatory release
/// and refuses outdated builds with HTTP 426.
const String kAppVersion = '1.1.0';

/// Backend platform slug for this build, or null where updates don't apply.
String? get kAppPlatform {
  if (kIsWeb) return null;
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  return null;
}

/// Headers attached to every request so the server can enforce updates.
Map<String, String> get kAppVersionHeaders => {
      'X-App-Version': kAppVersion,
      if (kAppPlatform != null) 'X-App-Platform': kAppPlatform!,
    };

/// Compares dotted versions numerically ("1.0.10" > "1.0.9"). Pre-release and
/// build suffixes ("-beta", "+45") are ignored, matching the backend.
/// Returns <0, 0 or >0.
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  for (var i = 0; i < 4; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

bool isNewerVersion(String remote, String local) =>
    compareVersions(remote, local) > 0;

List<int> _parts(String v) {
  var core = v.trim();
  if (core.startsWith('v') || core.startsWith('V')) core = core.substring(1);
  core = core.split(RegExp(r'[-+]')).first;
  final parts = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  while (parts.length < 4) {
    parts.add(0);
  }
  return parts.take(4).toList();
}
