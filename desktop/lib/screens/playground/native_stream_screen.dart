// ═══════════════════════════════════════════════════════════════════════════════
//  NativeStreamScreen — iOS / Android
//
//  Streams through the native Xmax Flutter SDK (package:xmax_sdk): camera
//  capture, Agora transport and video rendering are all native, no WebView.
//  The SDK supports iOS and Android only, so desktop keeps the WebView
//  RealtimeStreamScreen.
//
//  Flow: POST /stream/token/ → per-session Xmax temporary key + model + prompt
//  → camera preview → Start uploads the face once and starts generation →
//  heartbeat bills every 10 s while live (same as desktop).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';

class NativeStreamScreen extends StatefulWidget {
  final String? prompt;
  final String? faceImageBase64;

  const NativeStreamScreen({
    super.key,
    this.prompt,
    this.faceImageBase64,
  });

  @override
  State<NativeStreamScreen> createState() => _NativeStreamScreenState();
}

class _NativeStreamScreenState extends State<NativeStreamScreen> {
  // ── Phase ──────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.fetchingToken;
  String? _error;

  // ── Stream config — all decided by the backend ─────────────────────────────
  String? _streamToken;
  String? _modelId; // e.g. "x2.1"
  String _facePrompt = '';
  double? _creditsRemaining;
  double _creditsPerSecond = 2.0;

  // ── SDK ────────────────────────────────────────────────────────────────────
  XmaxClient? _client;
  XmaxRealtimeManaging? _realtime;
  RealtimeMediaStream? _localStream;
  RealtimeVideoTrack? _localTrack;
  RealtimeVideoTrack? _remoteTrack;
  String? _referenceUrl; // uploaded face, reused for every start / re-apply

  // ── Session ────────────────────────────────────────────────────────────────
  bool _busy = false; // starting, stopping, switching camera
  bool _live = false; // first AI frame is on screen
  String _status = 'Ready. Press Start to go live';
  int _elapsed = 0;
  Timer? _elapsedTimer;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _heartbeatTimer?.cancel();
    _releaseSdk();
    super.dispose();
  }

  // ── BOOT: token → SDK → camera preview ────────────────────────────────────
  Future<void> _boot() async {
    await _releaseSdk();
    setState(() {
      _phase = _Phase.fetchingToken;
      _error = null;
    });

    try {
      final result = await ApiService.instance.getRealtimeToken(
        faceImageBase64: widget.faceImageBase64,
        prompt: widget.prompt,
      );
      final code = result['statusCode'];
      if (code != null && code != 200) {
        throw Exception(result['error'] ?? 'Failed to get stream token.');
      }
      _streamToken = result['token'] as String;
      final model = result['model'];
      if (model is String && model.isNotEmpty) _modelId = model;
      final prompt = result['prompt'];
      if (prompt is String && prompt.isNotEmpty) _facePrompt = prompt;
      // The backend uploads the face when it can; otherwise Start does.
      final reference = result['reference_url'];
      _referenceUrl = reference is String && reference.isNotEmpty ? reference : null;
      _creditsRemaining = (result['credits_remaining'] as num?)?.toDouble();
      _creditsPerSecond =
          (result['credits_per_second'] as num?)?.toDouble() ?? 2.0;
      if (_creditsRemaining != null && mounted) {
        context.read<AuthProvider>().updateCredits(_creditsRemaining!);
      }
      // Xmax temporary keys start with "tk-"; anything else means the backend
      // is not issuing Xmax keys (old code, or XMAX_API_KEY not set).
      debugPrint('[NativeStream] model=$_modelId key='
          '${_streamToken!.startsWith('tk-') ? 'xmax temporary' : 'NOT an Xmax temporary key'}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.sanitize(e);
        _phase = _Phase.error;
      });
      return;
    }

    try {
      final model = RealtimeModel.values
          .where((m) => m.value == _modelId)
          .firstOrNull;
      if (model == null) {
        throw Exception('This version of the app cannot stream with the '
            'current AI model. Please update the app.');
      }
      if (!mounted) return;
      setState(() => _phase = _Phase.openingCamera);

      final client = XmaxClient(
        configuration: XmaxConfiguration(
          apiKey: _streamToken!,
          environment: XmaxEnvironment.global, // the SDK defaults to china
        ),
      );
      final realtime = client.createRealtimeManager(
        options: RealtimeConfiguration(model: model),
      );
      _client = client;
      _realtime = realtime;
      await realtime.setStateListener(_onState);

      // Model defaults: portrait on phones. The SDK asks for camera permission.
      final stream = await realtime.createLocalCameraStream(
        position: CameraPosition.front,
      );
      if (!mounted) return;
      setState(() {
        _localStream = stream;
        _localTrack = stream.videoTrack;
        _phase = _Phase.ready;
      });
    } catch (e) {
      debugPrint('[NativeStream] camera/SDK setup failed: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _releaseSdk() async {
    final realtime = _realtime;
    _realtime = null;
    _client = null;
    _localStream = null;
    _localTrack = null;
    _remoteTrack = null;
    _referenceUrl = null;
    if (realtime == null) return;
    try {
      await realtime.setStateListener(null);
      await realtime.close();
    } catch (e) {
      debugPrint('[NativeStream] close failed: $e');
    }
  }

  // ── SDK state ─────────────────────────────────────────────────────────────
  void _onState(RealtimeState state) {
    debugPrint('[NativeStream] state: ${state.connectionState.value}');
    final error = state.reason?.error;
    if (error != null) {
      debugPrint('[NativeStream] session failure: $error');
      _endSession(_friendly(error));
      return;
    }
    if (!mounted || _live) return;
    switch (state.connectionState) {
      case RealtimeConnectionState.connecting:
        setState(() => _status = 'Connecting to AI…');
      case RealtimeConnectionState.connected:
      case RealtimeConnectionState.generating:
        if (_busy) setState(() => _status = 'Starting AI…');
      default:
        break;
    }
  }

  /// First AI frame is on screen: start the clock and billing.
  void _onFirstOutput() {
    if (_live || _remoteTrack == null || !mounted) return;
    setState(() {
      _live = true;
      _busy = false;
      _status = 'Streaming live';
      _elapsed = 0;
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    _startHeartbeat();
  }

  // ── START / STOP ──────────────────────────────────────────────────────────
  Future<void> _start() async {
    final realtime = _realtime;
    final local = _localStream;
    if (realtime == null || local == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Connecting to AI…';
    });
    try {
      await _ensureReference();
      // Prompt + face go with the start, so the first frame out is already
      // transformed (no flash of the raw camera).
      final remote = await realtime.startGeneration(
        localStream: local,
        context: _context(),
      );
      if (!mounted) return;
      setState(() => _remoteTrack = remote?.videoTrack);
    } catch (e) {
      final sdkError = XmaxError.from(e);
      if (sdkError.code == XmaxErrorCode.cancelled) return;
      debugPrint('[NativeStream] start failed: $sdkError');
      await _endSession(_friendly(sdkError));
    }
  }

  /// The model takes the face as a URL: upload it once per session.
  Future<void> _ensureReference() async {
    final face = widget.faceImageBase64;
    if (face == null || face.isEmpty || _referenceUrl != null) return;
    if (mounted) setState(() => _status = 'Preparing your face…');
    final uploaded = await _client!.createStorageManager().uploadImage(
          data: base64Decode(face),
          fileName: 'face.jpg',
          contentType: 'image/jpeg',
        );
    _referenceUrl = uploaded.url.toString();
  }

  RealtimeContext _context() =>
      RealtimeContext(prompt: _facePrompt, referencePath: _referenceUrl);

  /// Stops generation and billing but keeps the camera preview, so Start
  /// works again with the same session key. [message] explains a failure.
  Future<void> _endSession([String? message]) async {
    _stopHeartbeat();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (mounted) {
      setState(() {
        _live = false;
        _busy = true;
        _remoteTrack = null;
        _status = message == null ? 'Stopped' : 'Error';
      });
    }
    try {
      await _realtime?.disconnect();
    } catch (e) {
      debugPrint('[NativeStream] disconnect failed: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reapplyFace() async {
    final realtime = _realtime;
    if (realtime == null || !_live || _referenceUrl == null) return;
    setState(() => _status = 'Applying face…');
    try {
      // On a running task this only updates its conditions.
      await realtime.startGeneration(context: _context());
      if (mounted) setState(() => _status = 'Streaming live ✓');
    } catch (e) {
      debugPrint('[NativeStream] re-apply failed: $e');
      if (mounted) setState(() => _status = 'Face apply failed');
    }
  }

  Future<void> _switchCamera() async {
    final realtime = _realtime;
    if (realtime == null || _busy) return;
    setState(() => _busy = true);
    try {
      final stream = await realtime.switchCamera();
      if (!mounted) return;
      setState(() {
        _localStream = stream;
        _localTrack = stream.videoTrack;
      });
    } catch (e) {
      debugPrint('[NativeStream] switch camera failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goBack() async {
    _stopHeartbeat();
    _elapsedTimer?.cancel();
    await _releaseSdk();
    if (mounted) context.go('/playground');
  }

  // ── Heartbeat (deducts credits on backend every 10 s) ─────────────────────
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final result = await ApiService.instance.streamHeartbeat();
        if (!mounted) return;
        // Stop on: out of credits (402), account frozen/suspended (403) or
        // build no longer supported (426).
        final code = result['statusCode'];
        final stop = result['stop'] == true || code == 403 || code == 426;
        final newCredits = (result['credits_remaining'] as num?)?.toDouble();
        if (newCredits != null) {
          setState(() => _creditsRemaining = newCredits);
          context.read<AuthProvider>().updateCredits(newCredits);
        }
        if (stop) {
          final reason = code == 402
              ? 'You ran out of credits. Top up to keep streaming.'
              : (result['error'] as String?) ?? 'The server ended the session.';
          debugPrint('[NativeStream] heartbeat stopped the stream (HTTP $code)');
          await _endSession(reason);
        }
      } catch (e) {
        debugPrint('[NativeStream] heartbeat failed: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ── Errors ────────────────────────────────────────────────────────────────
  String _friendly(Object e) {
    if (e is! XmaxError) return ErrorHandler.sanitize(e);
    switch (e.apiCode) {
      case 46002:
        return 'Your streaming session expired. Go back and start again.';
      case 46018:
      case 46019:
        return 'This session reached its time or credit limit. Go back and start again.';
      case 46032:
        return 'Another stream is already running on your account. Stop it, then try again.';
    }
    return switch (e.code) {
      XmaxErrorCode.invalidAPIKey =>
        'Your streaming session expired. Go back and start again.',
      XmaxErrorCode.cameraPermissionDenied =>
        'Camera access was denied. Allow camera access in Settings and try again.',
      XmaxErrorCode.unsafeImage =>
        'The face photo was rejected by the content safety check. Try a different photo.',
      XmaxErrorCode.uploadError =>
        'Could not upload your face photo. Check your connection and try again.',
      XmaxErrorCode.networkError ||
      XmaxErrorCode.rtcError =>
        'Network problem while streaming. Check your connection and try again.',
      XmaxErrorCode.timeout =>
        'The AI service took too long to respond. Please try again.',
      // Server messages can arrive in Chinese; don't show those as-is.
      _ => RegExp(r'[一-鿿]').hasMatch(e.message)
          ? 'The AI service could not start the stream'
              '${e.apiCode != null ? ' (code ${e.apiCode})' : ''}. Please try again.'
          : 'AI stream error: ${e.message}',
    };
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  String get _elapsedText =>
      '${(_elapsed ~/ 60).toString().padLeft(2, '0')}:'
      '${(_elapsed % 60).toString().padLeft(2, '0')}';

  String? get _remainText {
    final credits = _creditsRemaining;
    if (credits == null || _creditsPerSecond <= 0) return null;
    final secs = (credits / _creditsPerSecond).floor();
    return '${(secs ~/ 60).toString().padLeft(2, '0')}:'
        '${(secs % 60).toString().padLeft(2, '0')} left';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screen,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_phase == _Phase.ready)
            XmaxRealtimeDualVideo(
              localTrack: _localTrack,
              remoteTrack: _remoteTrack,
              isInteractionEnabled: false,
              onRemoteVideoReady: _onFirstOutput,
            ),
          if (_phase == _Phase.ready) _buildHud(),
          if (_phase == _Phase.fetchingToken || _phase == _Phase.openingCamera)
            _buildLoadingOverlay(),
          if (_phase == _Phase.error) _buildErrorOverlay(),
        ],
      ),
    );
  }

  Widget _buildHud() {
    final hasFace = (widget.faceImageBase64 ?? '').isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _RoundButton(icon: Icons.arrow_back_rounded, onTap: _goBack),
                const SizedBox(width: 10),
                Expanded(child: _StatusChip(text: _status, live: _live)),
                const SizedBox(width: 10),
                _RoundButton(
                  icon: Icons.cameraswitch_rounded,
                  onTap: _busy ? null : _switchCamera,
                ),
              ],
            ),
            const Spacer(),
            if (_live || _creditsRemaining != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  [
                    if (_live) _elapsedText,
                    if (_creditsRemaining != null)
                      '${_creditsRemaining!.toStringAsFixed(0)} cr',
                    if (_remainText != null) _remainText!,
                  ].join('  ·  '),
                  style: const TextStyle(
                      color: AppColors.screenText,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            Row(
              children: [
                if (_live && hasFace) ...[
                  _RoundButton(icon: Icons.face_retouching_natural, onTap: _reapplyFace),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _live || _remoteTrack != null
                            ? AppColors.tally
                            : AppColors.cobalt,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                      ),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(_live || _remoteTrack != null
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded),
                      label: Text(_live || _remoteTrack != null ? 'Stop' : 'Start'),
                      onPressed: _live || _remoteTrack != null
                          ? () => _endSession()
                          : (_busy ? null : _start),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    final label = _phase == _Phase.fetchingToken
        ? 'Getting stream token…'
        : 'Opening camera…';
    return Container(
      color: AppColors.screen,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 18),
            Text(label,
                style: const TextStyle(color: AppColors.screenMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: AppColors.screen,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.tally.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.error_outline_rounded,
                    color: AppColors.tally, size: 28),
              ),
              const SizedBox(height: 20),
              const Text(
                'The stream couldn’t start',
                style: TextStyle(
                    color: AppColors.screenText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.screenMuted, fontSize: 14.5, height: 1.5),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.screenText,
                      side: const BorderSide(color: AppColors.screenBorder),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _goBack,
                    child: const Text('Back to studio'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                    onPressed: _boot,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: onTap == null ? AppColors.screenMuted : Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final bool live;

  const _StatusChip({required this.text, required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: live ? AppColors.tally : AppColors.screenMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.screenText, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

enum _Phase { fetchingToken, openingCamera, ready, error }
