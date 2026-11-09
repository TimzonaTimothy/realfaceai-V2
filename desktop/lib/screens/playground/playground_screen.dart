import 'dart:convert';
import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../widgets/pro_layout.dart';
import '../../widgets/viewfinder_frame.dart';

/// Playground — studio layout.
///
///   Toolbar: title · balance · [Launch live stream]
///   ┌ Setup rail ─┬ Preview (monitor) ──────────────┬ Pre-flight ┐
///   │ mode        │ face image on the dark screen   │ checklist  │
///   │ source face │                                 │ cost       │
///   └─────────────┴─────────────────────────────────┴────────────┘
///
/// Launch lives in the toolbar so it never scrolls out of reach. Under
/// 1100 px the inspector stacks below; under 800 px the rail stacks too.
class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  static const int _minCredits = 20;

  String? _error;

  File? _faceImage;
  String? _faceImageBase64;
  String? _faceImageName;


  // ── Actions ─────────────────────────────────────────────────────────────
  Future<void> _pickFaceImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;
    final file = File(picked.path!);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _faceImage = file;
      _faceImageBase64 = base64Encode(bytes);
      _faceImageName = picked.name;
      _error = null;
    });
  }

  void _removeFaceImage() => setState(() {
        _faceImage = null;
        _faceImageBase64 = null;
        _faceImageName = null;
      });

  void _launch() {
    if (_faceImageBase64 == null) {
      setState(() => _error = 'Upload a face image before launching.');
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.credits < _minCredits) {
      setState(() => _error =
          'Not enough credits. You need at least $_minCredits credits to start streaming.');
      return;
    }
    // No model here — the backend chooses it when the session starts.
    context.go('/stream', extra: {
      'prompt': null,
      'faceImageBase64': _faceImageBase64,
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final enough = auth.credits >= _minCredits;
    final ready = _faceImage != null && enough;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          ProToolbar(
            icon: Icons.center_focus_strong_rounded,
            title: 'Studio',
            subtitle: 'Set up a face, check the essentials, then go live.',
            actions: [
              _BalancePill(
                text: '${CreditDisplay.toTime(auth.credits)} left',
                low: !enough,
              ),
              _LaunchButton(ready: ready, onPressed: _launch),
            ],
          ),
          Expanded(
            child: ProWorkspace(
              railWidth: 300,
              inspectorWidth: 280,
              collapsedMainHeight: 380,
              collapsedRailHeight: 560,
              collapsedInspectorHeight: 220,
              rail: _setupPanel(),
              main: _previewPanel(),
              inspector: _preflightPanel(auth, enough),
            ),
          ),
        ],
      ),
    );
  }

  // ── Setup rail ──────────────────────────────────────────────────────────
  Widget _setupPanel() {
    return ProPanel(
      title: 'Setup',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          ProLabel('Source face', trailing: ProTag('Required', color: AppColors.danger)),
          const SizedBox(height: 4),
          Text(
            'A clear, front-facing photo works best.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          FaceImageUploader(
            imageFile: _faceImage,
            onPickImage: _pickFaceImage,
            onRemoveImage: _removeFaceImage,
          ),
          if (_faceImageName != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 11, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _faceImageName!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontFamily: AppFonts.mono),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Preview monitor ─────────────────────────────────────────────────────
  Widget _previewPanel() {
    return ProPanel(
      title: 'Preview',
      icon: Icons.monitor_rounded,
      scroll: false,
      padding: EdgeInsets.zero,
      color: AppColors.screen,
      trailing: _faceImage == null
          ? ProTag('No face', color: AppColors.warning)
          : ProTag('Face ready', color: AppColors.success),
      child: Container(
        color: AppColors.screen,
        padding: const EdgeInsets.all(18),
        child: ViewfinderFrame(
          arm: 26,
          padding: const EdgeInsets.all(10),
          bracketColor:
              _faceImage == null ? AppColors.screenMuted : AppColors.cobaltLight,
          child: Center(
            child: _faceImage == null
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.face_retouching_natural_rounded,
                              size: 48, color: AppColors.screenMuted),
                          SizedBox(height: 14),
                          Text(
                            'Your source face will appear here',
                            style: TextStyle(
                                color: AppColors.screenText,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Upload a photo on the left, then press Go live.',
                            style: TextStyle(
                                color: AppColors.screenMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.file(_faceImage!, fit: BoxFit.contain),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Pre-flight inspector ────────────────────────────────────────────────
  Widget _preflightPanel(AuthProvider auth, bool enough) {
    return ProPanel(
      title: 'Pre-flight',
      icon: Icons.fact_check_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _check('Source face uploaded', _faceImage != null),
          _check('At least $_minCredits credits', enough),
          _check('Mode selected', true),
          const SizedBox(height: 20),
          const ProLabel('Session'),
          const SizedBox(height: 6),
          const ProKv('Typical length', '~37 sec', mono: true),
          ProKv('Balance', CreditDisplay.toTime(auth.credits),
              mono: true,
              valueColor: enough ? AppColors.success : AppColors.danger),
          const ProKv('Output', 'Browser Source (OBS)', last: true),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: AppColors.dangerText,
                            fontSize: 13,
                            height: 1.45)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _check(String text, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 18,
              color: ok ? AppColors.success : AppColors.borderLight,
            ),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
                color: ok ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: ok ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );
}

// ── Toolbar widgets ──────────────────────────────────────────────────────────

class _BalancePill extends StatelessWidget {
  final String text;
  final bool low;
  const _BalancePill({required this.text, required this.low});

  @override
  Widget build(BuildContext context) {
    final c = low ? AppColors.danger : AppColors.success;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 16, color: c),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: c,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final bool ready;
  final VoidCallback onPressed;
  const _LaunchButton({required this.ready, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Stays tappable when not ready so the error explains what's missing,
    // but reads as secondary until pre-flight passes.
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(ready ? Icons.play_arrow_rounded : Icons.lock_outline_rounded,
            size: 18),
        label: const Text('Go live'),
        style: ready
            ? null
            : ButtonStyle(
                backgroundColor:
                    WidgetStateProperty.all(AppColors.bgHover),
                foregroundColor:
                    WidgetStateProperty.all(AppColors.textSecondary),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FACE IMAGE UPLOADER (public — kept for compatibility)
// ─────────────────────────────────────────────────────────────────────────────

class FaceImageUploader extends StatelessWidget {
  final File? imageFile;
  final VoidCallback onPickImage;
  final VoidCallback? onRemoveImage;

  const FaceImageUploader({
    super.key,
    required this.imageFile,
    required this.onPickImage,
    this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    if (imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          height: 200,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(imageFile!, fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _overlayAction(
                          Icons.swap_horiz_rounded, 'Change', Colors.white,
                          onPickImage),
                      _overlayAction(Icons.delete_outline_rounded, 'Remove',
                          const Color(0xFFFF8A87), onRemoveImage ?? () {}),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onPickImage,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: DottedBorder(
        color: AppColors.borderLight,
        strokeWidth: 1,
        dashPattern: const [6, 4],
        borderType: BorderType.RRect,
        radius: const Radius.circular(AppRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          color: AppColors.bgSubtle,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppShadows.xs,
                ),
                child: Icon(Icons.upload_rounded,
                    color: AppColors.cobalt, size: 22),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'Click to upload',
                      style: TextStyle(color: AppColors.cobalt)),
                  TextSpan(text: ' a face photo'),
                ]),
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('JPG, PNG or WEBP',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlayAction(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 13, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}