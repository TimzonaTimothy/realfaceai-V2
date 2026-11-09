// lib/screens/update_required_screen.dart
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_version.dart';
import '../services/app_gate.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Full-screen, non-dismissible gate shown when this build is below the
/// newest mandatory release. The router keeps the user here until the app is
/// replaced by a supported build (or the mandatory release is withdrawn).
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;
  bool _checking = false;
  String? _note;

  Future<void> _download(UpdateInfo info) async {
    setState(() {
      _opening = true;
      _note = null;
    });
    try {
      final ok = await launchUrl(Uri.parse(info.downloadUrl),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _note =
            'Couldn’t open your browser. Copy the link below and open it yourself.');
      } else if (mounted) {
        setState(() => _note =
            'Install the new version, then quit and reopen ${Brand.name}.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _note =
            'Couldn’t open your browser. Copy the link below and open it yourself.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _checkAgain() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    final info = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (info == null) {
        _note = 'Couldn’t reach ${Brand.domain}. Check your connection.';
      } else if (info.forceUpdate) {
        _note = 'You’re on $kAppVersion. Install version ${info.version} to continue.';
      }
      // If the update is no longer required the gate clears and the router
      // moves on by itself.
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = context.watch<AppGate>().requiredUpdate;
    if (info == null) return Scaffold(backgroundColor: AppColors.bg);

    final target = info.version.isNotEmpty ? info.version : 'the latest version';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLockup(height: 30),
                  const SizedBox(height: 36),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.cobalt50,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(Icons.system_update_alt_rounded,
                        color: AppColors.cobalt, size: 30),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    info.message ??
                        'This version of ${Brand.name} is no longer supported. '
                            'Install $target to keep using the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _VersionCard(info: info),
                  const SizedBox(height: 20),
                  if (_note != null) ...[
                    _Note(text: _note!),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _opening ? null : () => _download(info),
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: Text('Download $target'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _checking ? null : _checkAgain,
                          child: _checking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Check again'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => exit(0),
                          child: Text('Quit ${Brand.name}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _CopyableLink(url: info.downloadUrl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final UpdateInfo info;
  const _VersionCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Installed', kAppVersion, muted: true),
          if (info.version.isNotEmpty) ...[
            const SizedBox(height: 6),
            _row('Latest', info.version),
          ],
          if (info.minSupportedVersion != null) ...[
            const SizedBox(height: 6),
            _row('Minimum supported', info.minSupportedVersion!),
          ],
          if (info.releaseNotes != null) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Text(
              'What’s new',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              info.releaseNotes!,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool muted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            color: muted ? AppColors.textMuted : AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cobalt50,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cobalt100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.cobalt),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableLink extends StatelessWidget {
  final String url;
  const _CopyableLink({required this.url});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: SelectableText(
            url,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Copy link',
          iconSize: 15,
          visualDensity: VisualDensity.compact,
          color: AppColors.textMuted,
          icon: const Icon(Icons.copy_rounded),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Link copied')),
            );
          },
        ),
      ],
    );
  }
}
