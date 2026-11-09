import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// A compact toast floated over the page (bottom-right) whenever an update is available.
/// Tapping "Download update" opens your website's download page in the browser.
/// Mandatory updates cannot be dismissed.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<UpdateService>();
    if (!svc.hasUpdate) return const SizedBox.shrink();

    final info = svc.available!;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.screen,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt_rounded,
                  size: 16, color: AppColors.cobaltLight),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Update available',
                  style: TextStyle(
                    color: AppColors.screenText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!info.isMandatory)
                Tooltip(
                  message: 'Dismiss',
                  child: InkWell(
                    onTap: svc.dismiss,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: AppColors.screenMuted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Version ${info.version} is ready to download.',
            style:
                const TextStyle(color: AppColors.screenMuted, fontSize: 12.5),
          ),
          if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              info.releaseNotes!,
              style: const TextStyle(
                color: AppColors.screenMuted,
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF8A84), fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openDownloadPage(info.downloadUrl),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.open_in_browser_rounded, size: 15),
              label: const Text('Download update'),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the website download page in the default browser.
  /// No file is downloaded or saved by the app itself.
  Future<void> _openDownloadPage(String url) async {
    setState(() => _error = null);
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        setState(() => _error = 'Could not open browser. Visit:\n$url');
      }
    } catch (_) {
      setState(() => _error = 'Could not open browser.');
    }
  }
}
