// // Add a Browser Source correct

// // Click + in Sources → choose Browser.

// // Paste the /popout URL

// // In the Browser Source properties, set the URL to the one shown in the app after clicking OBS (visible in the green badge on the AI Output panel):

// // http://127.0.0.1:8700/popout
// // The port number may differ — always copy it from the badge in the app.

// // Set width & height to match your stream resolution

// // Typical values: 1920 × 1080. The page has a black background so letterboxing is invisible.

// // Start the stream in the app first, then click OBS in the app

// // The Browser Source shows "Waiting for stream…" until frames start arriving. Once you click the OBS button in the app the relay starts and OBS fills with the AI output only — no UI chrome.

// // ── Phase enum ────────────────────────────────────────────────────────────────

// enum _Phase { fetchingToken, startingServer, ready, error }

// Add a Browser Source correct

// Click + in Sources → choose Browser.

// Paste the /popout URL

// In the Browser Source properties, set the URL to the one shown in the app after clicking OBS (visible in the green badge on the AI Output panel):

// http://127.0.0.1:8700/popout
// The port number may differ — always copy it from the badge in the app.

// Set width & height to match your stream resolution

// Typical values: 1920 × 1080. The page has a black background so letterboxing is invisible.

// Start the stream in the app first, then click OBS in the app

// The Browser Source shows "Waiting for stream…" until frames start arriving. Once you click the OBS button in the app the relay starts and OBS fills with the AI output only — no UI chrome.

// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'dart:math';

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:go_router/go_router.dart';
// import 'package:provider/provider.dart';

// import '../../services/api_service.dart';
// import '../../services/auth_provider.dart';
// import '../../theme/app_theme.dart';
// import '../../utils/error_handler.dart';

// // ═══════════════════════════════════════════════════════════════════════════════
// //  RealtimeStreamScreen
// //
// //  Pure WebView approach — works on Windows, macOS, Android, iOS.
// //  No camera plugin needed. getUserMedia runs inside WebView2 / WKWebView.
// //
// //  OBS FIX (v2 — low-latency):
// //  Previous approach used polling (/frame every 33 ms) + base64 encoding.
// //  Both added latency. New approach:
// //
// //    /push   → JS POSTs raw binary JPEG (toBlob, no base64) here per frame
// //    /stream → MJPEG multipart stream — OBS holds this connection open;
// //              Dart fans each /push frame out instantly (no poll delay)
// //    /popout → HTML page: <img src="/stream"> — browser handles MJPEG natively
// //
// //  JS side uses requestVideoFrameCallback (fires on decoded frames, not a
// //  fixed timer) + back-pressure flag so a slow POST never queues up frames.
// //  Net result: ~0 ms poll lag, no base64 overhead, no main-thread blocking.
// //
// //  ① Race condition  → server fully binds BEFORE setState triggers WebView load
// //  ② Missing headers → Permissions-Policy + Feature-Policy served on every req
// //  ③ No error surface→ JS handler 'onError' routes failures back to Flutter UI
// //  ④ Windows WebView2 getUserMedia blocked from non-HTTPS →
// //       Works fine from http://127.0.0.1 (loopback is allowlisted by WebView2)
// //  ⑤ faceImageBase64 passed to getRealtimeToken (backend face-swap init)
// //  ⑥ FACE_URL forwarded to rtClient.set() after stream connects
// //  ⑦ Live elapsed timer + credits pushed into WebView every second via JS
// //  ⑧ App logo embedded as base64 in the HTML topbar
// // ═══════════════════════════════════════════════════════════════════════════════

// class RealtimeStreamScreen extends StatefulWidget {
//   final String model;
//   final String? prompt;
//   final String? faceImageBase64;

//   const RealtimeStreamScreen({
//     super.key,
//     required this.model,
//     this.prompt,
//     this.faceImageBase64,
//   });

//   @override
//   State<RealtimeStreamScreen> createState() => _RealtimeStreamScreenState();
// }

// class _RealtimeStreamScreenState extends State<RealtimeStreamScreen> {
//   // ── State ──────────────────────────────────────────────────────────────────
//   _Phase _phase = _Phase.fetchingToken;
//   String? _error;

//   // ── Token data ─────────────────────────────────────────────────────────────
//   String? _streamToken;
//   double? _creditsRemaining;

//   // ── Local HTTP server ──────────────────────────────────────────────────────
//   HttpServer? _server;
//   int? _port;

//   // ── Latest frame buffer + SSE subscriber list ─────────────────────────────
//   List<int>? _latestFrameBytes;
//   final List<HttpResponse> _sseClients = [];

//   // ── WebView ────────────────────────────────────────────────────────────────
//   InAppWebViewController? _webViewController;
//   bool _streaming = false;

//   // ── Timers ───────────────────────────────────────────────────────────────
//   Timer? _elapsedTimer; // kept for future use
//   Timer? _heartbeatTimer; // fires every 10 s, deducts credits on backend
//   double _creditsPerSecond = 2.0; // default, overridden from token response

//   // ── Logo base64 ───────────────────────────────────────────────────────────
//   String _logoBase64 = '';

//   static const int _preferredPort = 8700;

//   // ──────────────────────────────────────────────────────────────────────────
//   @override
//   void initState() {
//     super.initState();
//     _loadLogo().then((_) => _boot());
//   }

//   @override
//   void dispose() {
//     _elapsedTimer?.cancel();
//     _heartbeatTimer?.cancel();
//     for (final c in _sseClients) {
//       try {
//         c.close();
//       } catch (_) {}
//     }
//     _sseClients.clear();
//     _server?.close(force: true);
//     super.dispose();
//   }

//   // ── Load logo asset as base64 so it can be embedded in the HTML ───────────
//   Future<void> _loadLogo() async {
//     try {
//       final bytes =
//           await rootBundle.load('assets/images/logo_transparent_800x340.png');
//       _logoBase64 = base64Encode(bytes.buffer.asUint8List());
//     } catch (_) {
//       _logoBase64 = ''; // graceful fallback — text logo shows instead
//     }
//   }

//   // ── BOOT SEQUENCE ─────────────────────────────────────────────────────────
//   Future<void> _boot() async {
//     setState(() {
//       _phase = _Phase.fetchingToken;
//       _error = null;
//     });

//     // Step 1: get token
//     try {
//       final result = await ApiService.instance.getRealtimeToken(
//         widget.model,
//         faceImageBase64: widget.faceImageBase64,
//         prompt: widget.prompt,
//       );
//       final code = result['statusCode'];
//       if (code != null && code != 200) {
//         throw Exception(result['error'] ?? 'Failed to get stream token.');
//       }
//       _streamToken = result['token'] as String;
//       _creditsRemaining = (result['credits_remaining'] as num?)?.toDouble();
//       _creditsPerSecond =
//           (result['credits_per_second'] as num?)?.toDouble() ?? 2.0;
//       if (_creditsRemaining != null && mounted) {
//         context.read<AuthProvider>().updateCredits(_creditsRemaining!);
//       }
//     } catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _error = ErrorHandler.sanitize(e);
//         _phase = _Phase.error;
//       });
//       return;
//     }

//     // Step 2: start server
//     try {
//       setState(() => _phase = _Phase.startingServer);
//       await _startServer();
//     } catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _error = 'Local server error: ${e.toString()}';
//         _phase = _Phase.error;
//       });
//       return;
//     }

//     // Step 3: show WebView
//     if (mounted) setState(() => _phase = _Phase.ready);
//   }

//   // ── Credits push (timer lives in JS now) ──────────────────────────────────
//   void _startElapsedTimer() {
//     // Timer is handled entirely in JS — nothing to start in Dart.
//     // We just kick off the credits refresh loop here if needed in future.
//   }

//   void _stopElapsedTimer() {
//     _elapsedTimer?.cancel();
//     _elapsedTimer = null;
//   }

//   // ── HEARTBEAT ─────────────────────────────────────────────────────────────
//   void _startHeartbeat() {
//     _heartbeatTimer?.cancel();
//     _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
//       try {
//         final result = await ApiService.instance.streamHeartbeat();
//         if (!mounted) return;

//         final stop = result['stop'] == true;
//         final newCredits = (result['credits_remaining'] as num?)?.toDouble();

//         if (newCredits != null) {
//           _creditsRemaining = newCredits;
//           context.read<AuthProvider>().updateCredits(newCredits);
//           // Push updated credits + remaining time into WebView
//           _pushCreditsUpdate();
//         }

//         if (stop) {
//           // Out of credits — stop the stream from Dart side
//           _webViewController?.evaluateJavascript(source: 'stopStream();');
//           _stopHeartbeat();
//         }
//       } catch (_) {
//         // Network hiccup — skip this tick, try again next interval
//       }
//     });
//   }

//   void _stopHeartbeat() {
//     _heartbeatTimer?.cancel();
//     _heartbeatTimer = null;
//   }

//   /// Push updated credits + remaining stream time into the WebView.
//   void _pushCreditsUpdate() {
//     if (_webViewController == null || _creditsRemaining == null) return;
//     final credits = _creditsRemaining!.toStringAsFixed(0);
//     // remaining seconds = credits / creditsPerSecond
//     final remainSecs = (_creditsPerSecond > 0)
//         ? (_creditsRemaining! / _creditsPerSecond).floor()
//         : 0;
//     final rm = (remainSecs ~/ 60).toString().padLeft(2, '0');
//     final rs = (remainSecs % 60).toString().padLeft(2, '0');
//     final timeStr = '$rm:$rs';
//     _webViewController!.evaluateJavascript(source: """
//       (function() {
//         var c = document.getElementById('hudCredits');
//         var r = document.getElementById('hudRemain');
//         if (c) { c.textContent = '$credits cr'; c.style.display = ''; }
//         if (r) { r.textContent = '⏳ $timeStr left'; r.style.display = ''; }
//       })();
//     """);
//   }

//   // ── LOCAL HTTP SERVER ──────────────────────────────────────────────────────
//   Future<void> _startServer() async {
//     await _server?.close(force: true);
//     _port = await _findFreePort();
//     _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port!);
//     _server!.listen(_handleRequest);
//   }

//   Future<void> _handleRequest(HttpRequest req) async {
//     final path = req.uri.path;

//     req.response.headers
//       ..set('Access-Control-Allow-Origin', '*')
//       ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
//       ..set('Access-Control-Allow-Headers', 'Content-Type')
//       ..set('Feature-Policy', 'camera *; microphone *')
//       ..set('Permissions-Policy', 'camera=(*), microphone=(*)')
//       ..set('Cross-Origin-Opener-Policy', 'same-origin')
//       ..set('Cross-Origin-Embedder-Policy', 'require-corp');

//     if (req.method == 'OPTIONS') {
//       req.response.statusCode = 204;
//       await req.response.close();
//       return;
//     }

//     switch (path) {
//       case '/push':
//         if (req.method == 'POST') {
//           final bodyBytes = await req
//               .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
//           if (bodyBytes.isNotEmpty) {
//             _latestFrameBytes = bodyBytes;
//             final deadClients = <HttpResponse>[];
//             for (final client in _sseClients) {
//               try {
//                 client
//                   ..write('--frame\r\n')
//                   ..write('Content-Type: image/jpeg\r\n')
//                   ..write('Content-Length: ${bodyBytes.length}\r\n\r\n')
//                   ..add(bodyBytes)
//                   ..write('\r\n');
//                 await client.flush();
//               } catch (_) {
//                 deadClients.add(client);
//               }
//             }
//             for (final d in deadClients) {
//               _sseClients.remove(d);
//               try {
//                 d.close();
//               } catch (_) {}
//             }
//           }
//           req.response
//             ..statusCode = 204
//             ..close();
//         } else {
//           req.response
//             ..statusCode = 405
//             ..close();
//         }

//       case '/stream':
//         req.response
//           ..statusCode = 200
//           ..headers
//               .set('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
//           ..headers.set('Cache-Control', 'no-cache')
//           ..headers.set('Connection', 'keep-alive')
//           ..headers.set('Access-Control-Allow-Origin', '*');
//         final snap = _latestFrameBytes;
//         if (snap != null) {
//           req.response
//             ..write('--frame\r\n')
//             ..write('Content-Type: image/jpeg\r\n')
//             ..write('Content-Length: ${snap.length}\r\n\r\n')
//             ..add(snap)
//             ..write('\r\n');
//           await req.response.flush();
//         }
//         _sseClients.add(req.response);

//       case '/frame':
//         final frameBytes = _latestFrameBytes;
//         if (frameBytes == null) {
//           req.response
//             ..statusCode = 204
//             ..close();
//         } else {
//           req.response
//             ..statusCode = 200
//             ..headers.set('Content-Type', 'image/jpeg')
//             ..headers
//                 .set('Cache-Control', 'no-cache, no-store, must-revalidate')
//             ..headers.set('Pragma', 'no-cache')
//             ..headers.contentLength = frameBytes.length
//             ..add(frameBytes)
//             ..close();
//         }

//       case '/popout':
//         final html = _buildPopoutHtml();
//         req.response
//           ..statusCode = 200
//           ..headers.set('Content-Type', 'text/html; charset=utf-8')
//           ..write(html)
//           ..close();

//       default:
//         final html = _buildHtml();
//         req.response
//           ..statusCode = 200
//           ..headers.set('Content-Type', 'text/html; charset=utf-8')
//           ..write(html)
//           ..close();
//     }
//   }

//   Future<int> _findFreePort() async {
//     for (final port in [_preferredPort, ..._randomPorts()]) {
//       try {
//         final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
//         await s.close();
//         return port;
//       } catch (_) {}
//     }
//     final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
//     final p = s.port;
//     await s.close();
//     return p;
//   }

//   List<int> _randomPorts() {
//     final rand = Random();
//     return List.generate(10, (_) => 8700 + rand.nextInt(200));
//   }

//   // ── HTML ──────────────────────────────────────────────────────────────────

//   String _buildPopoutHtml() => '''<!DOCTYPE html>
// <html>
// <head>
// <meta charset="UTF-8">
// <title>AI Output – OBS</title>
// <style>
//   * { margin:0; padding:0; box-sizing:border-box; }
//   html, body { width:100%; height:100%; background:#000; overflow:hidden; }
//   img { width:100%; height:100%; object-fit:contain; display:block; color:transparent; }
//   #msg {
//     position:fixed; inset:0; display:flex; align-items:center;
//     justify-content:center; color:#3A4048; font-family:system-ui;
//     font-size:14px; letter-spacing:.08em; pointer-events:none;
//   }
// </style>
// </head>
// <body>
// <img id="frame" alt="">
// <div id="msg">Waiting for stream… start the stream in the app</div>
// <script>
//   const img = document.getElementById('frame');
//   const msg = document.getElementById('msg');
//   function connect() {
//     img.src = '/stream?t=' + Date.now();
//     img.onload  = () => { msg.style.display = 'none'; };
//     img.onerror = () => { setTimeout(connect, 1000); };
//   }
//   connect();
// </script>
// </body>
// </html>''';

//   String _escape(String s) =>
//       s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll("'", "\\'");

//   String _buildHtml() {
//     final safeToken = _escape(_streamToken ?? '');
//     final safeModel = _escape(widget.model);
//     final safePrompt = _escape(widget.prompt ?? 'Transform this scene');
//     final faceDataUrl = widget.faceImageBase64 != null
//         ? 'data:image/jpeg;base64,${widget.faceImageBase64}'
//         : '';
//     final port = _port.toString();
//     final initCredits =
//         _creditsRemaining != null ? _creditsRemaining!.toStringAsFixed(1) : '';
//     // Logo: use image tag if we have base64, otherwise text fallback
//     final logoHtml = _logoBase64.isNotEmpty
//         ? '<img src="data:image/png;base64,$_logoBase64" alt="InstantFaceAI" class="logo-img">'
//         : '<span class="logo-text">INSTANTFACEAI</span>';

//     return '''<!DOCTYPE html>
// <html lang="en">
// <head>
// <meta charset="UTF-8">
// <meta name="viewport" content="width=device-width,initial-scale=1.0">
// <title>InstantFaceAI</title>
// <style>
//   :root {
//     --bg:      #0B0E11;
//     --surface: #161A1E;
//     --border:  #2B3139;
//     --text:    #EAECED;
//     --green:   #03A66D;
//     --red:     #CF304A;
//   }
//   * { margin:0; padding:0; box-sizing:border-box; }
//   html, body {
//     height: 100%; width: 100%;
//     background: var(--bg); color: var(--text);
//     font-family: system-ui, -apple-system, sans-serif;
//     overflow: hidden;
//     display: flex; flex-direction: column;
//   }

//   /* ── Top bar ── */
//   .topbar {
//     height: 52px; flex-shrink: 0;
//     background: var(--surface);
//     border-bottom: 1px solid var(--border);
//     display: flex; align-items: center;
//     padding: 0 16px; gap: 10px;
//   }

//   /* Logo */
//   .logo-img  { height: 28px; width: auto; object-fit: contain; display: block; }
//   .logo-text { font-weight: 700; letter-spacing: 1.4px; font-size: 14px; }

//   /* HUD badges — elapsed time + credits shown during live stream */
//   .hud-group {
//     display: flex; align-items: center; gap: 6px;
//   }
//   .hud-badge {
//     font-size: 11px; font-weight: 600;
//     border-radius: 20px; padding: 3px 10px;
//     white-space: nowrap;
//     min-width: 48px; text-align: center;
//   }
//   .hud-time {
//     color: #EAECED;
//     background: rgba(255,255,255,.08);
//     border: 1px solid rgba(255,255,255,.15);
//     font-variant-numeric: tabular-nums;
//     letter-spacing: .04em;
//   }
//   .hud-credits {
//     color: var(--green);
//     background: rgba(3,166,109,.12);
//     border: 1px solid rgba(3,166,109,.35);
//   }
//   .hud-remain {
//     color: #F0B90B;
//     background: rgba(240,185,11,.10);
//     border: 1px solid rgba(240,185,11,.30);
//   }

//   .spacer { flex: 1; }

//   /* ── Buttons ── */
//   button {
//     padding: 7px 18px; border: none; border-radius: 5px;
//     cursor: pointer; font-weight: 700; font-size: 13px;
//     display: flex; align-items: center; gap: 6px;
//     transition: opacity .15s;
//   }
//   button:disabled { opacity: .4; cursor: not-allowed; }
//   #startBtn     { background: var(--green); color: #000; }
//   #stopBtn      { background: var(--red);   color: #fff; }
//   #applyFaceBtn {
//     background: #1E2530; color: #EAECED;
//     border: 1px solid #3A4452;
//     display: none;
//   }
//   #applyFaceBtn.visible { display: flex; }
//   #backBtn {
//     background: transparent; color: #7A8490;
//     border: 1px solid #2B3139;
//     padding: 6px 12px; font-size: 12px;
//   }
//   #backBtn:hover { color: #EAECED; border-color: #4A5462; }

//   /* ── Video grid ── */
//   .grid {
//     flex: 1;
//     display: grid; grid-template-columns: 1fr 1fr;
//     gap: 2px; background: var(--border);
//     min-height: 0;
//   }
//   .cell { position: relative; background: #000; overflow: hidden; }
//   video { width: 100%; height: 100%; object-fit: cover; display: block; }

//   /* ── Placeholder ── */
//   .ph {
//     position: absolute; inset: 0;
//     display: flex; flex-direction: column;
//     align-items: center; justify-content: center;
//     gap: 12px; color: #3A4048;
//   }
//   .ph svg { width: 40px; height: 40px; opacity: .5; }
//   .ph span { font-size: 12px; letter-spacing: .1em; text-transform: uppercase; }

//   /* ── Cell label ── */
//   .cell-label {
//     position: absolute; bottom: 10px; left: 10px;
//     font-size: 10px; letter-spacing: 1.2px; color: rgba(255,255,255,.35);
//     background: rgba(0,0,0,.45); padding: 3px 8px; border-radius: 3px;
//     pointer-events: none;
//   }

//   /* ── OBS button ── */
//   #obsBtn {
//     position: absolute; bottom: 10px; right: 10px;
//     background: rgba(0,0,0,.55); color: rgba(255,255,255,.75);
//     border: 1px solid rgba(255,255,255,.15);
//     padding: 5px 10px; font-size: 11px; font-weight: 600;
//     border-radius: 4px; display: none; gap: 5px;
//     backdrop-filter: blur(4px); cursor: pointer;
//   }
//   #obsBtn.visible { display: flex; }
//   #obsBtn.active  { background: rgba(3,166,109,.7); color: #fff; }
//   #obsBtn:hover   { background: rgba(0,0,0,.8); color: #fff; }
//   #obsBtn.active:hover { background: rgba(3,166,109,.9); }

//   #obsUrlBadge {
//     display: none;
//     position: absolute; top: 10px; left: 0; right: 0;
//     text-align: center; font-size: 10px; color: rgba(255,255,255,.8);
//     background: rgba(0,0,0,.65); padding: 5px 8px;
//     letter-spacing: .04em; pointer-events: none;
//     border-bottom: 1px solid rgba(255,255,255,.1);
//   }

//   /* ── Status bar ── */
//   .statusbar {
//     height: 28px; flex-shrink: 0;
//     background: var(--surface); border-top: 1px solid var(--border);
//     display: flex; align-items: center; padding: 0 14px; gap: 8px;
//   }
//   .dot {
//     width: 7px; height: 7px; border-radius: 50%;
//     background: #3A4048; transition: background .3s;
//   }
//   .dot.live { background: var(--green); box-shadow: 0 0 6px var(--green); }
//   .status-text { font-size: 11px; color: #5A6472; }

//   /* ── Error overlay ── */
//   #errOverlay {
//     display: none;
//     position: fixed; inset: 0; z-index: 99;
//     background: rgba(11,14,17,.92);
//     flex-direction: column; align-items: center; justify-content: center;
//     gap: 16px; padding: 32px; text-align: center;
//   }
//   #errOverlay.show { display: flex; }
//   #errOverlay .err-icon { font-size: 40px; }
//   #errOverlay .err-msg  { color: #ccc; font-size: 14px; max-width: 420px; line-height: 1.6; }
//   #retryBtn {
//     background: var(--green); color: #000;
//     padding: 10px 24px; border-radius: 6px; font-weight: 700;
//     border: none; cursor: pointer; font-size: 14px;
//   }

//   /* ── Stopped overlay ── */
//   #stoppedOverlay {
//     display: none;
//     position: fixed; inset: 0; z-index: 98;
//     background: rgba(11,14,17,.92);
//     flex-direction: column; align-items: center; justify-content: center;
//     gap: 18px; padding: 32px; text-align: center;
//   }
//   #stoppedOverlay.show { display: flex; }
//   #stoppedOverlay .stop-icon  { font-size: 44px; }
//   #stoppedOverlay .stop-title { color: #EAECED; font-size: 18px; font-weight: 700; }
//   #stoppedOverlay .stop-sub   { color: #7A8490; font-size: 13px; }
//   .overlay-actions { display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; }
//   .btn-back {
//     background: #F0B90B; color: #0B0E11; border: none;
//     padding: 10px 22px; border-radius: 6px;
//     font-weight: 700; font-size: 13px; cursor: pointer;
//     display: flex; align-items: center; gap: 7px;
//   }
// </style>
// <script type="importmap">
//   { "imports": { "@decartai/sdk": "https://esm.sh/@decartai/sdk@latest" } }
// </script>
// </head>
// <body>

// <!-- ── Top bar ─────────────────────────────────────────────────────── -->
// <div class="topbar">
//   <button id="backBtn">← Back</button>

//   $logoHtml

//   <!-- HUD: elapsed time + credits — both hidden until stream goes live -->
//   <div class="hud-group">
//     <span class="hud-badge hud-time" id="hudTime" style="display:none">00:00</span>
//     <span class="hud-badge hud-credits" id="hudCredits" style="display:none"></span>
//     <span class="hud-badge hud-remain" id="hudRemain" style="display:none"></span>
//   </div>

//   <div class="spacer"></div>
//   <button id="applyFaceBtn">😊 Apply Face</button>
//   <button id="startBtn">▶ START</button>
//   <button id="stopBtn" disabled>■ STOP</button>
// </div>

// <!-- ── Video grid ──────────────────────────────────────────────────── -->
// <div class="grid">
//   <!-- Local camera -->
//   <div class="cell">
//     <div class="ph" id="localPh">
//       <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
//         <path d="M15 10l4.553-2.276A1 1 0 0121 8.723v6.554a1 1 0 01-1.447.894L15 14M3 8a2 2 0 012-2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z"/>
//       </svg>
//       <span>Camera Input</span>
//     </div>
//     <video id="localVideo" autoplay muted playsinline></video>
//     <span class="cell-label">INPUT</span>
//   </div>

//   <!-- AI output -->
//   <div class="cell">
//     <div class="ph" id="remotePh">
//       <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
//         <circle cx="12" cy="12" r="9"/><path d="M12 8v4l2 2"/>
//       </svg>
//       <span>AI Output</span>
//     </div>
//     <video id="remoteVideo" autoplay playsinline></video>
//     <span class="cell-label">AI OUTPUT</span>

//     <button id="obsBtn" title="Toggle OBS frame relay">
//       <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
//         <path d="M15 3h6v6M9 21H3v-6M21 3l-9 9M3 21l9-9"/>
//       </svg>
//       OBS
//     </button>
//     <div id="obsUrlBadge"></div>
//   </div>
// </div>

// <!-- ── Status bar ──────────────────────────────────────────────────── -->
// <div class="statusbar">
//   <div class="dot" id="liveDot"></div>
//   <span class="status-text" id="statusText">Ready — press START to begin</span>
// </div>

// <!-- ── Error overlay ───────────────────────────────────────────────── -->
// <div id="errOverlay">
//   <div class="err-icon">⚠️</div>
//   <div class="err-msg" id="errMsg">An error occurred.</div>
//   <button id="retryBtn">↻ Try Again</button>
// </div>

// <!-- ── Stopped overlay ─────────────────────────────────────────────── -->
// <div id="stoppedOverlay">
//   <div class="stop-icon">⏹</div>
//   <div class="stop-title">Stream ended</div>
//   <div class="stop-sub">Your session has been stopped.</div>
//   <div class="overlay-actions">
//     <button class="btn-back" id="goBackBtn">← Back to Playground</button>
//   </div>
// </div>

// <script type="module">
// import { createDecartClient, models } from '@decartai/sdk';

// const TOKEN    = '$safeToken';
// const MODEL_ID = '$safeModel';
// const FACE_URL = '$faceDataUrl';
// const SERVER   = 'http://127.0.0.1:$port';

// const startBtn       = document.getElementById('startBtn');
// const stopBtn        = document.getElementById('stopBtn');
// const applyFaceBtn   = document.getElementById('applyFaceBtn');
// const obsBtn         = document.getElementById('obsBtn');
// const obsUrlBadge    = document.getElementById('obsUrlBadge');
// const localVideo     = document.getElementById('localVideo');
// const remoteVideo    = document.getElementById('remoteVideo');
// const localPh        = document.getElementById('localPh');
// const remotePh       = document.getElementById('remotePh');
// const liveDot        = document.getElementById('liveDot');
// const statusText     = document.getElementById('statusText');
// const errOverlay     = document.getElementById('errOverlay');
// const errMsg         = document.getElementById('errMsg');
// const stoppedOverlay = document.getElementById('stoppedOverlay');
// const hudTime        = document.getElementById('hudTime');
// const hudCredits     = document.getElementById('hudCredits');

// let localStream = null;
// let rtClient    = null;

// // ── OBS relay ────────────────────────────────────────────────────────────────
// let _obsRelayActive = false;
// let _obsOffscreen   = null;
// let _obsCtx         = null;
// let _obsPushPending = false;

// function _obsFrameCallback(now, metadata) {
//   if (!_obsRelayActive) return;
//   remoteVideo.requestVideoFrameCallback(_obsFrameCallback);
//   if (_obsPushPending) return;
//   if (!remoteVideo.srcObject || remoteVideo.readyState < 2) return;
//   const w = remoteVideo.videoWidth  || 1280;
//   const h = remoteVideo.videoHeight || 720;
//   if (_obsOffscreen.width  !== w) _obsOffscreen.width  = w;
//   if (_obsOffscreen.height !== h) _obsOffscreen.height = h;
//   _obsCtx.drawImage(remoteVideo, 0, 0, w, h);
//   _obsPushPending = true;
//   _obsOffscreen.toBlob(async (blob) => {
//     try {
//       if (blob && _obsRelayActive) {
//         await fetch(SERVER + '/push', {
//           method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob,
//         });
//       }
//     } catch (_) {}
//     finally { _obsPushPending = false; }
//   }, 'image/jpeg', 0.80);
// }

// function _startObsRelay() {
//   if (_obsRelayActive) return;
//   _obsOffscreen = document.createElement('canvas');
//   _obsCtx = _obsOffscreen.getContext('2d');
//   _obsRelayActive = true;
//   _obsPushPending = false;
//   remoteVideo.requestVideoFrameCallback(_obsFrameCallback);
// }

// function _stopObsRelay() {
//   _obsRelayActive = false;
//   _obsOffscreen = null;
//   _obsCtx = null;
//   _obsPushPending = false;
// }

// window.toggleObs = function() {
//   if (_obsRelayActive) {
//     _stopObsRelay();
//     obsBtn.classList.remove('active');
//     obsUrlBadge.style.display = 'none';
//     obsUrlBadge.textContent = '';
//   } else {
//     if (!remoteVideo.srcObject) return;
//     _startObsRelay();
//     obsBtn.classList.add('active');
//     const url = SERVER + '/popout';
//     obsUrlBadge.textContent = 'OBS Browser Source URL: ' + url;
//     obsUrlBadge.style.display = 'block';
//   }
// };

// // ── Helpers ──────────────────────────────────────────────────────────────────
// function setStatus(msg, live = false) {
//   statusText.textContent = msg;
//   liveDot.className = 'dot' + (live ? ' live' : '');
// }

// function showError(msg) {
//   errMsg.textContent = msg;
//   errOverlay.classList.add('show');
//   setStatus('Error — see details above');
//   startBtn.disabled = false;
//   stopBtn.disabled  = true;
//   // Hide HUD on error
//   if (window._hudTimerInterval) { clearInterval(window._hudTimerInterval); window._hudTimerInterval = null; }
//   hudTime.style.display = 'none';
//   if (window.flutter_inappwebview) {
//     window.flutter_inappwebview.callHandler('onError', msg);
//   }
// }

// function dataUrlToBlob(dataUrl) {
//   const [header, b64] = dataUrl.split(',');
//   const mime  = header.match(/:(.*?);/)[1];
//   const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
//   return new Blob([bytes], { type: mime });
// }

// // ── START ────────────────────────────────────────────────────────────────────
// window.startStream = async function() {
//   errOverlay.classList.remove('show');
//   startBtn.disabled = true;
//   setStatus('Requesting camera…');

//   try {
//     const model = models.realtime(MODEL_ID);
//     const fps = Number.isFinite(model.fps)    ? model.fps    : 30;
//     const mw  = Number.isFinite(model.width)  ? model.width  : 1280;
//     const mh  = Number.isFinite(model.height) ? model.height : 720;

//     localStream = await navigator.mediaDevices.getUserMedia({
//       video: { frameRate: { ideal: fps }, width: { ideal: mw }, height: { ideal: mh }, facingMode: 'user' },
//       audio: false,
//     });

//     localVideo.srcObject = localStream;
//     localPh.style.display = 'none';
//     setStatus('Connecting to AI…');

//     const client = createDecartClient({ apiKey: TOKEN });
//     rtClient = await client.realtime.connect(localStream, {
//       model,
//       mirror: 'auto',
//       onRemoteStream: async (stream) => {
//         remoteVideo.srcObject = stream;
//         remotePh.style.display = 'none';
//         stopBtn.disabled = false;
//         obsBtn.classList.add('visible');
//         setStatus('Streaming live', true);

//         // Start self-contained JS elapsed timer — no Dart involvement needed
//         hudTime.style.display = '';
//         hudTime.textContent = '00:00';
//         let _elapsed = 0;
//         if (window._hudTimerInterval) clearInterval(window._hudTimerInterval);
//         window._hudTimerInterval = setInterval(() => {
//           _elapsed++;
//           const m = String(Math.floor(_elapsed / 60)).padStart(2, '0');
//           const s = String(_elapsed % 60).padStart(2, '0');
//           hudTime.textContent = m + ':' + s;
//         }, 1000);

//         if (FACE_URL && FACE_URL.length > 0) {
//           applyFaceBtn.classList.add('visible');
//           await _applyFaceToSession();
//         }

//         if (window.flutter_inappwebview) {
//           window.flutter_inappwebview.callHandler('onStreamStarted');
//         }
//       },
//     });

//   } catch (err) {
//     console.error('[InstantFaceAI]', err);
//     let friendly = err.message || String(err);
//     if (friendly.includes('Permission denied') || friendly.includes('NotAllowedError')) {
//       friendly = 'Camera access was denied. Please allow camera access and try again.';
//     } else if (friendly.includes('NotFoundError') || friendly.includes('DevicesNotFound')) {
//       friendly = 'No camera found. Please connect a webcam and try again.';
//     }
//     showError(friendly);
//   }
// };

// // ── Face apply ───────────────────────────────────────────────────────────────
// async function _applyFaceToSession() {
//   if (!rtClient) { setStatus('Face apply failed — no stream client', true); return; }
//   if (!FACE_URL || FACE_URL.length === 0) { setStatus('Face apply failed — no face image received', true); return; }
//   try {
//     setStatus('Applying face…', true);
//     const faceBlob = dataUrlToBlob(FACE_URL);
//     await rtClient.set({
//       prompt: 'Substitute the character in the video with the person in the reference image.',
//       image: faceBlob,
//       enhance: true,
//     });
//     setStatus('Streaming live ✓', true);
//   } catch (e) {
//     console.error('[InstantFaceAI] set() failed', e);
//     setStatus('Face apply failed — ' + (e?.message || String(e)), true);
//   }
// }

// // ── STOP ─────────────────────────────────────────────────────────────────────
// window.stopStream = function() {
//   _stopObsRelay();
//   obsBtn.classList.remove('visible', 'active');
//   obsUrlBadge.style.display = 'none';
//   obsUrlBadge.textContent = '';

//   rtClient?.disconnect?.();
//   localStream?.getTracks().forEach(t => t.stop());
//   localStream = null;
//   rtClient    = null;

//   localVideo.srcObject  = null;
//   remoteVideo.srcObject = null;
//   localPh.style.display  = '';
//   remotePh.style.display = '';

//   applyFaceBtn.classList.remove('visible');
//   startBtn.disabled = false;
//   stopBtn.disabled  = true;
//   setStatus('Stopped');

//   // Stop JS timer and hide HUD badges
//   if (window._hudTimerInterval) { clearInterval(window._hudTimerInterval); window._hudTimerInterval = null; }
//   hudTime.style.display = 'none';
//   hudTime.textContent   = '00:00';
//   var _hudR = document.getElementById('hudRemain');
//   if (_hudR) _hudR.style.display = 'none';

//   stoppedOverlay.classList.add('show');

//   // Notify Dart to fetch a fresh token so the next START works cleanly
//   if (window.flutter_inappwebview) {
//     window.flutter_inappwebview.callHandler('onStreamStopped');
//   }
// };

// window.retryStream = function() {
//   errOverlay.classList.remove('show');
//   // Notify Dart to get a fresh token and reload the WebView
//   if (window.flutter_inappwebview) {
//     window.flutter_inappwebview.callHandler('onStreamStopped');
//   } else {
//     startStream(); // fallback
//   }
// };

// window.applyFace = async function() {
//   if (!rtClient || !FACE_URL) return;
//   applyFaceBtn.disabled = true;
//   await _applyFaceToSession();
//   applyFaceBtn.disabled = false;
// };

// window.goBack = function() {
//   if (window.flutter_inappwebview) {
//     window.flutter_inappwebview.callHandler('onGoBack');
//   }
// };

// document.getElementById('startBtn').addEventListener('click', startStream);
// document.getElementById('stopBtn').addEventListener('click', stopStream);
// document.getElementById('retryBtn').addEventListener('click', retryStream);
// document.getElementById('applyFaceBtn').addEventListener('click', applyFace);
// document.getElementById('obsBtn').addEventListener('click', toggleObs);
// document.getElementById('backBtn').addEventListener('click', goBack);
// document.getElementById('goBackBtn').addEventListener('click', goBack);

// // Show initial credits if available at page load
// const _initCr = '$initCredits';
// if (_initCr && _initCr !== 'null' && _initCr !== '') {
//   hudCredits.textContent = _initCr + ' credits';
//   hudCredits.style.display = '';
// }
// </script>
// </body>
// </html>''';
//   }

//   // ── WEBVIEW SETTINGS ──────────────────────────────────────────────────────
//   InAppWebViewSettings _webSettings() => InAppWebViewSettings(
//         javaScriptEnabled: true,
//         mediaPlaybackRequiresUserGesture: false,
//         allowsInlineMediaPlayback: true,
//         iframeAllow: 'camera *; microphone *',
//         supportZoom: false,
//         useShouldOverrideUrlLoading: false,
//         allowUniversalAccessFromFileURLs: true,
//         allowFileAccessFromFileURLs: true,
//         javaScriptCanOpenWindowsAutomatically: true,
//         isInspectable: true,
//         transparentBackground: false,
//         useHybridComposition: true,
//       );

//   // ── BUILD ─────────────────────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.bg,
//       body: Stack(
//         children: [
//           if (_phase == _Phase.ready && _port != null)
//             InAppWebView(
//               initialUrlRequest: URLRequest(
//                 url: WebUri('http://127.0.0.1:$_port'),
//               ),
//               initialSettings: _webSettings(),
//               onWebViewCreated: (controller) {
//                 _webViewController = controller;

//                 controller.addJavaScriptHandler(
//                   handlerName: 'onStreamStarted',
//                   callback: (_) {
//                     if (mounted) {
//                       setState(() => _streaming = true);
//                       _startElapsedTimer();
//                       _startHeartbeat();
//                       _pushCreditsUpdate(); // show initial remaining time immediately
//                     }
//                   },
//                 );
//                 controller.addJavaScriptHandler(
//                   handlerName: 'onError',
//                   callback: (args) {
//                     final msg =
//                         args.isNotEmpty ? args[0].toString() : 'Stream error';
//                     debugPrint('[RealtimeScreen] JS error: $msg');
//                     if (mounted) {
//                       setState(() => _streaming = false);
//                       _stopElapsedTimer();
//                       _stopHeartbeat();
//                     }
//                   },
//                 );
//                 controller.addJavaScriptHandler(
//                   handlerName: 'onGoBack',
//                   callback: (_) {
//                     _stopElapsedTimer();
//                     _stopHeartbeat();
//                     _server?.close(force: true);
//                     if (mounted) context.go('/playground');
//                   },
//                 );
//                 controller.addJavaScriptHandler(
//                   handlerName: 'onStreamStopped',
//                   callback: (_) async {
//                     if (!mounted) return;
//                     _stopElapsedTimer();
//                     _stopHeartbeat();
//                     setState(() => _streaming = false);
//                     // Fetch a fresh token and reload the WebView
//                     // so the next START uses a new valid session token
//                     try {
//                       final result = await ApiService.instance.getRealtimeToken(
//                         widget.model,
//                         faceImageBase64: widget.faceImageBase64,
//                       );
//                       if (result['statusCode'] == 200) {
//                         _streamToken = result['token'] as String;
//                         await _webViewController?.reload();
//                       }
//                     } catch (_) {
//                       // If token refresh fails, reload anyway — user will see error on next start
//                       await _webViewController?.reload();
//                     }
//                   },
//                 );
//               },
//               onPermissionRequest: (controller, request) async {
//                 debugPrint(
//                     '[RealtimeScreen] Permission request: ${request.resources}');
//                 return PermissionResponse(
//                   resources: request.resources,
//                   action: PermissionResponseAction.GRANT,
//                 );
//               },
//               onConsoleMessage: (_, msg) =>
//                   debugPrint('[WebView] ${msg.message}'),
//               onLoadError: (_, url, code, message) {
//                 debugPrint('[WebView] Load error $code: $message');
//               },
//             ),
//           if (_phase != _Phase.ready && _phase != _Phase.error)
//             _buildLoadingOverlay(),
//           if (_phase == _Phase.error) _buildErrorOverlay(),
//         ],
//       ),
//     );
//   }

//   Widget _buildLoadingOverlay() {
//     final label = switch (_phase) {
//       _Phase.fetchingToken => 'Getting stream token…',
//       _Phase.startingServer => 'Starting local server…',
//       _Phase.ready => '',
//       _Phase.error => '',
//     };
//     return Container(
//       color: AppColors.bg,
//       child: Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const SizedBox(
//               width: 36,
//               height: 36,
//               child: CircularProgressIndicator(strokeWidth: 2.5),
//             ),
//             const SizedBox(height: 18),
//             Text(label,
//                 style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildErrorOverlay() {
//     return Container(
//       color: AppColors.bg,
//       padding: const EdgeInsets.all(40),
//       child: Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Icon(Icons.error_outline, color: Color(0xFFCF304A), size: 52),
//             const SizedBox(height: 20),
//             Text(
//               _error ?? 'An error occurred.',
//               textAlign: TextAlign.center,
//               style: const TextStyle(
//                   color: AppColors.textSecondary, fontSize: 15, height: 1.5),
//             ),
//             const SizedBox(height: 28),
//             ElevatedButton.icon(
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF03A66D),
//                 foregroundColor: Colors.white,
//                 padding:
//                     const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//               ),
//               icon: const Icon(Icons.refresh),
//               label: const Text('Try Again',
//                   style: TextStyle(fontWeight: FontWeight.bold)),
//               onPressed: _boot,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ── Phase enum ────────────────────────────────────────────────────────────────
// enum _Phase { fetchingToken, startingServer, ready, error }

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  RealtimeStreamScreen
//
//  Pure WebView approach — works on Windows, macOS, Android, iOS.
//  No camera plugin needed. getUserMedia runs inside WebView2 / WKWebView.
//
//  SDK is served from the local Dart HTTP server as /static/rt.js —
//  bundled into the app as a Flutter asset. Zero external network calls,
//  no provider branding visible in traffic.
//
//  Local server routes:
//    /            → main WebView HTML (camera + AI output UI)
//    /static/rt.js→ self-contained SDK bundle (served from assets/js/rt.js)
//    /push        → JS POSTs raw binary JPEG here per frame (no base64)
//    /stream      → MJPEG multipart stream — OBS holds this open
//    /frame       → single-frame fallback JPEG snapshot
//    /popout      → OBS Browser Source HTML (<img src="/stream">)
//
//  JS side uses requestVideoFrameCallback + back-pressure so a slow POST
//  never queues up frames. Net result: ~0 ms poll lag, no base64 overhead.
//
//  Windows: the page opens in the user's default browser instead of WebView2
//  (WebView2 failed to open the camera on some machines, e.g. HP Omen). The
//  page talks to Dart over the local server instead of JS handlers:
//    /api/started → start billing heartbeat
//    /api/stopped → stop heartbeat + fetch a fresh token (page then reloads)
//    /api/status  → page polls every 2 s: credits, forced stop, liveness
//    /api/closed  → tab closed/reloaded mid-stream (sendBeacon)
//    /api/back    → back to studio
//  All /api/* calls carry a per-session key so other local pages can't use them.
// ═══════════════════════════════════════════════════════════════════════════════

/// The streaming model is NOT chosen by the app: the backend returns it (with
/// the face-swap prompt) from POST /stream/token/, so the model can be
/// switched server-side without shipping a new build.
class RealtimeStreamScreen extends StatefulWidget {
  final String? prompt;
  final String? faceImageBase64;

  const RealtimeStreamScreen({
    super.key,
    this.prompt,
    this.faceImageBase64,
  });

  @override
  State<RealtimeStreamScreen> createState() => _RealtimeStreamScreenState();
}

class _RealtimeStreamScreenState extends State<RealtimeStreamScreen> {
  // ── Phase ──────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.fetchingToken;
  String? _error;

  // ── Token data ─────────────────────────────────────────────────────────────
  String? _streamToken;
  double? _creditsRemaining;
  double _creditsPerSecond = 2.0;

  // ── Stream config — all decided by the backend ─────────────────────────────
  String? _modelId; // e.g. "lucy-2.5"
  String _facePrompt = '';
  String? _referenceUrl; // face already uploaded by the backend
  bool _promptEnhance = true;

  // ── Local HTTP server ──────────────────────────────────────────────────────
  HttpServer? _server;
  int? _port;

  // ── MJPEG frame buffer + subscriber list ──────────────────────────────────
  List<int>? _latestFrameBytes;
  final List<HttpResponse> _sseClients = [];

  // ── WebView ────────────────────────────────────────────────────────────────
  InAppWebViewController? _webViewController;
  bool _streaming = false;

  // ── External browser mode (Windows) ────────────────────────────────────────
  // macOS stays in WKWebView: Chrome blocks the OBS pop-out there.
  final bool _external = Platform.isWindows;
  final String _pageKey = List.generate(
      16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
  DateTime _lastPagePing = DateTime.now();
  String? _pendingStop; // reason handed to the page on its next /api/status

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _elapsedTimer;
  Timer? _heartbeatTimer;

  // ── Assets (loaded once at boot) ──────────────────────────────────────────
  String _logoBase64 = '';
  Uint8List? _sdkBytes; // rt.js bundle from assets/js/rt.js
  // Worker rt.js starts next to itself (./frame-metadata-worker.js) in Chrome.
  // Without it the encoded-frame pipeline stalls and no AI video arrives.
  Uint8List? _workerBytes;

  // Content fingerprint of rt.js, added to its URL (?v=…). The WebView caches
  // rt.js on disk across launches, so without this a replaced SDK file keeps
  // being served from cache (that's how an old SDK rejected "lucy-2.5").
  String _sdkVersion = '0';

  static const int _preferredPort = 8700;

  // ──────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAssets().then((_) => _boot());
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _heartbeatTimer?.cancel();
    for (final c in _sseClients) {
      try {
        c.close();
      } catch (_) {}
    }
    _sseClients.clear();
    _server?.close(force: true);
    super.dispose();
  }

  // ── Load assets ───────────────────────────────────────────────────────────
  Future<void> _loadAssets() async {
    // Logo (optional — text fallback if missing)
    try {
      final bytes =
          await rootBundle.load('assets/images/logo_transparent_800x340.png');
      _logoBase64 = base64Encode(bytes.buffer.asUint8List());
    } catch (_) {
      _logoBase64 = '';
    }

    // SDK bundle — required. App won't stream without it.
    try {
      final bytes = await rootBundle.load('assets/js/rt.js');
      _sdkBytes = bytes.buffer.asUint8List();
      _sdkVersion = _fingerprint(_sdkBytes!);
    } catch (e) {
      debugPrint('[RealtimeScreen] WARNING: assets/js/rt.js not found: $e');
      // _sdkBytes stays null; _handleRequest returns 404 for /static/rt.js
      // and the WebView will show a JS import error — better than a silent hang.
    }

    try {
      final bytes =
          await rootBundle.load('assets/js/frame-metadata-worker.js');
      _workerBytes = bytes.buffer.asUint8List();
    } catch (e) {
      debugPrint('[RealtimeScreen] WARNING: frame-metadata-worker.js '
          'not found: $e');
    }
  }

  /// FNV-1a (32-bit) over the bytes + their length. Cheap, deterministic,
  /// changes whenever the file changes.
  static String _fingerprint(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${bytes.length.toRadixString(36)}${hash.toRadixString(36)}';
  }

  // ── BOOT ──────────────────────────────────────────────────────────────────
  Future<void> _boot() async {
    setState(() {
      _phase = _Phase.fetchingToken;
      _error = null;
    });

    // Step 1 — fetch streaming token from your backend
    try {
      final result = await ApiService.instance.getRealtimeToken(
        faceImageBase64: widget.faceImageBase64,
        prompt: widget.prompt,
      );
      final code = result['statusCode'];
      if (code != null && code != 200) {
        throw Exception(result['error'] ?? 'Failed to get stream token.');
      }
      _applyStreamConfig(result);
      if (_modelId == null) {
        throw Exception(
            'Streaming isn’t available right now. Please try again shortly.');
      }
      _streamToken = result['token'] as String;
      // Xmax temporary keys start with "tk-"; anything else means the backend
      // is not issuing Xmax keys (old code, or XMAX_API_KEY not set).
      debugPrint('[RealtimeScreen] model=$_modelId key='
          '${_streamToken!.startsWith('tk-') ? 'xmax temporary' : 'NOT an Xmax temporary key'}');
      _creditsRemaining = (result['credits_remaining'] as num?)?.toDouble();
      _creditsPerSecond =
          (result['credits_per_second'] as num?)?.toDouble() ?? 2.0;
      if (_creditsRemaining != null && mounted) {
        context.read<AuthProvider>().updateCredits(_creditsRemaining!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.sanitize(e);
        _phase = _Phase.error;
      });
      return;
    }

    // Step 2 — start local HTTP server
    try {
      setState(() => _phase = _Phase.startingServer);
      await _startServer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Local server error: ${e.toString()}';
        _phase = _Phase.error;
      });
      return;
    }

    // Step 3 — show WebView (or open the browser on Windows)
    if (mounted) setState(() => _phase = _Phase.ready);
    if (_external) await _openInBrowser();
  }

  Future<void> _openInBrowser() async {
    final url = Uri.parse('http://127.0.0.1:$_port');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open your browser. Open $url manually.'),
      ));
    }
  }

  /// Reads the model + prompt the backend chose for this session.
  void _applyStreamConfig(Map<String, dynamic> result) {
    final reference = result['reference_url'];
    if (reference is String && reference.isNotEmpty) _referenceUrl = reference;
    final model = result['model'];
    if (model is String && model.isNotEmpty) _modelId = model;
    final prompt = result['prompt'];
    if (prompt is String && prompt.isNotEmpty) _facePrompt = prompt;
    final enhance = result['enhance'];
    if (enhance is bool) _promptEnhance = enhance;
  }

  // ── Heartbeat (deducts credits on backend every 10 s) ─────────────────────
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      // Browser tab closed or crashed without telling us — stop billing.
      if (_external &&
          DateTime.now().difference(_lastPagePing) > const Duration(seconds: 20)) {
        debugPrint('[RealtimeScreen] browser page stopped polling — '
            'ending session');
        _stopHeartbeat();
        if (mounted) setState(() => _streaming = false);
        return;
      }
      try {
        final result = await ApiService.instance.streamHeartbeat();
        if (!mounted) return;
        // Stop on: out of credits (402), account frozen/suspended (403) or
        // build no longer supported (426). The server sends stop:true in all
        // of these; the status check is a belt-and-braces fallback.
        final code = result['statusCode'];
        final stop = result['stop'] == true || code == 403 || code == 426;
        final newCredits = (result['credits_remaining'] as num?)?.toDouble();
        if (newCredits != null) {
          _creditsRemaining = newCredits;
          context.read<AuthProvider>().updateCredits(newCredits);
          _pushCreditsUpdate();
        }
        if (stop) {
          final reason = code == 402
              ? 'You ran out of credits. Top up to keep streaming.'
              : (result['error'] as String?) ?? 'The server ended the session.';
          debugPrint('[RealtimeScreen] heartbeat stopped the stream '
              '(HTTP $code): $reason');
          _stopPage(reason);
          _stopHeartbeat();
        }
      } catch (e) {
        debugPrint('[RealtimeScreen] heartbeat failed: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  /// Ends the stream in the page: directly in the WebView, or on the browser
  /// page's next /api/status poll.
  void _stopPage(String reason) {
    if (_external) {
      _pendingStop = reason;
    } else {
      _webViewController?.evaluateJavascript(
          source: 'stopStream(${jsonEncode(reason)});');
    }
  }

  String? get _creditsText => _creditsRemaining == null
      ? null
      : '${_creditsRemaining!.toStringAsFixed(0)} cr';

  String? get _remainText {
    if (_creditsRemaining == null) return null;
    final remainSecs = (_creditsPerSecond > 0)
        ? (_creditsRemaining! / _creditsPerSecond).floor()
        : 0;
    final rm = (remainSecs ~/ 60).toString().padLeft(2, '0');
    final rs = (remainSecs % 60).toString().padLeft(2, '0');
    return '$rm:$rs';
  }

  /// Push updated credits + estimated remaining time into the live WebView.
  /// (The browser page picks these up from /api/status instead.)
  void _pushCreditsUpdate() {
    if (_webViewController == null || _creditsRemaining == null) return;
    _webViewController!.evaluateJavascript(source: """
      (function() {
        var c = document.getElementById('hudCredits');
        var r = document.getElementById('hudRemain');
        if (c) { c.textContent = '$_creditsText'; c.style.display = ''; }
        if (r) { r.textContent = '$_remainText'; r.style.display = ''; }
      })();
    """);
  }

  void _onPageStarted() {
    if (!mounted) return;
    _lastPagePing = DateTime.now();
    _pendingStop = null;
    setState(() => _streaming = true);
    _startHeartbeat();
    _pushCreditsUpdate();
  }

  /// Stream stopped in the page: stop billing and fetch a fresh token so the
  /// next START gets a new session (the reloaded page bakes it in).
  Future<void> _onPageStopped() async {
    _stopElapsedTimer();
    _stopHeartbeat();
    if (!mounted) return;
    setState(() => _streaming = false);
    try {
      final result = await ApiService.instance.getRealtimeToken(
        faceImageBase64: widget.faceImageBase64,
      );
      if (result['statusCode'] == 200) {
        _applyStreamConfig(result);
        _streamToken = result['token'] as String;
      }
    } catch (_) {}
  }

  void _onPageBack() {
    _stopElapsedTimer();
    _stopHeartbeat();
    _server?.close(force: true);
    if (mounted) context.go('/playground');
  }

  // ── Local HTTP server ──────────────────────────────────────────────────────
  Future<void> _startServer() async {
    await _server?.close(force: true);
    _port = await _findFreePort();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port!);
    _server!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final path = req.uri.path;

    // CORS + camera permission headers on every response
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Feature-Policy', 'camera *; microphone *')
      ..set('Permissions-Policy', 'camera=(*), microphone=(*)')
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }

    // ── Browser-mode bridge (replaces the WebView JS handlers) ──────────────
    if (path.startsWith('/api/')) {
      if (req.uri.queryParameters['k'] != _pageKey) {
        req.response
          ..statusCode = 403
          ..close();
        return;
      }
      _lastPagePing = DateTime.now();
      switch (path) {
        case '/api/started':
          _onPageStarted();
        case '/api/stopped':
          await _onPageStopped(); // page reloads once this returns
        case '/api/closed':
          _stopElapsedTimer();
          _stopHeartbeat();
          if (mounted) setState(() => _streaming = false);
        case '/api/back':
          req.response
            ..statusCode = 204
            ..close();
          _onPageBack();
          return;
        case '/api/status':
          final stop = _pendingStop;
          _pendingStop = null;
          req.response
            ..statusCode = 200
            ..headers.set('Content-Type', 'application/json')
            ..headers.set('Cache-Control', 'no-store')
            ..write(jsonEncode({
              'credits': _creditsText,
              'remain': _remainText,
              'stop': stop,
            }))
            ..close();
          return;
      }
      req.response
        ..statusCode = 204
        ..close();
      return;
    }

    switch (path) {
      // ── SDK bundle — served from Flutter asset, zero external calls ────────
      case '/static/rt.js':
        final sdk = _sdkBytes;
        if (sdk == null) {
          req.response
            ..statusCode = 404
            ..write(
                'rt.js not found — add assets/js/rt.js to your Flutter assets')
            ..close();
        } else {
          req.response
            ..statusCode = 200
            ..headers
                .set('Content-Type', 'application/javascript; charset=utf-8')
            // Safe to cache long: the URL carries a content fingerprint
            // (?v=…), so a new rt.js always gets a new URL.
            ..headers.set('Cache-Control', 'max-age=31536000, immutable')
            ..headers.contentLength = sdk.length
            ..add(sdk)
            ..close();
        }

      case '/static/frame-metadata-worker.js':
        final worker = _workerBytes;
        if (worker == null) {
          req.response
            ..statusCode = 404
            ..close();
        } else {
          req.response
            ..statusCode = 200
            ..headers
                .set('Content-Type', 'application/javascript; charset=utf-8')
            // No fingerprint in this URL (rt.js builds it), so don't cache.
            ..headers.set('Cache-Control', 'no-cache')
            ..headers.contentLength = worker.length
            ..add(worker)
            ..close();
        }

      // ── JS POSTs raw binary JPEG frames here — fanned to MJPEG clients ────
      case '/push':
        if (req.method != 'POST') {
          req.response
            ..statusCode = 405
            ..close();
          break;
        }
        final bodyBytes =
            await req.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        if (bodyBytes.isNotEmpty) {
          _latestFrameBytes = bodyBytes;
          final dead = <HttpResponse>[];
          for (final client in _sseClients) {
            try {
              client
                ..write('--frame\r\n')
                ..write('Content-Type: image/jpeg\r\n')
                ..write('Content-Length: ${bodyBytes.length}\r\n\r\n')
                ..add(bodyBytes)
                ..write('\r\n');
              await client.flush();
            } catch (_) {
              dead.add(client);
            }
          }
          for (final d in dead) {
            _sseClients.remove(d);
            try {
              d.close();
            } catch (_) {}
          }
        }
        req.response
          ..statusCode = 204
          ..close();

      // ── MJPEG stream — OBS Browser Source holds this connection open ───────
      case '/stream':
        req.response
          ..statusCode = 200
          ..headers
              .set('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
          ..headers.set('Cache-Control', 'no-cache')
          ..headers.set('Connection', 'keep-alive')
          ..headers.set('Access-Control-Allow-Origin', '*');
        final snap = _latestFrameBytes;
        if (snap != null) {
          req.response
            ..write('--frame\r\n')
            ..write('Content-Type: image/jpeg\r\n')
            ..write('Content-Length: ${snap.length}\r\n\r\n')
            ..add(snap)
            ..write('\r\n');
          await req.response.flush();
        }
        _sseClients.add(req.response);
      // Connection stays open — do NOT close.

      // ── Single-frame JPEG snapshot (fallback / /popout polling) ───────────
      case '/frame':
        final fb = _latestFrameBytes;
        if (fb == null) {
          req.response
            ..statusCode = 204
            ..close();
        } else {
          req.response
            ..statusCode = 200
            ..headers.set('Content-Type', 'image/jpeg')
            ..headers
                .set('Cache-Control', 'no-cache, no-store, must-revalidate')
            ..headers.set('Pragma', 'no-cache')
            ..headers.contentLength = fb.length
            ..add(fb)
            ..close();
        }

      // ── OBS Browser Source page ────────────────────────────────────────────
      case '/popout':
        req.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/html; charset=utf-8')
          ..write(_buildPopoutHtml())
          ..close();

      // ── Main app page (default) ────────────────────────────────────────────
      default:
        // Unknown static file: a real 404, not the HTML page (a script
        // served as text/html fails with a confusing MIME error).
        if (path.startsWith('/static/')) {
          req.response
            ..statusCode = 404
            ..close();
          break;
        }
        req.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/html; charset=utf-8')
          ..write(_buildHtml())
          ..close();
    }
  }

  Future<int> _findFreePort() async {
    for (final port in [_preferredPort, ..._randomPorts()]) {
      try {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await s.close();
        return port;
      } catch (_) {}
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  List<int> _randomPorts() {
    final rand = Random();
    return List.generate(10, (_) => 8700 + rand.nextInt(200));
  }

  // ── HTML builders ─────────────────────────────────────────────────────────

  String _buildPopoutHtml() => '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Live Output</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { width:100%; height:100%; background:#000; overflow:hidden; }
  img { width:100%; height:100%; object-fit:contain; display:block; color:transparent; }
  #msg {
    position:fixed; inset:0; display:flex; align-items:center;
    justify-content:center; color:#3A4048; font-family:system-ui;
    font-size:14px; letter-spacing:.08em; pointer-events:none;
  }
</style>
</head>
<body>
<img id="frame" alt="">
<div id="msg">Waiting for stream… start the stream in the app</div>
<script>
  const img = document.getElementById('frame');
  const msg = document.getElementById('msg');
  function connect() {
    img.src = '/stream?t=' + Date.now();
    img.onload  = () => { msg.style.display = 'none'; };
    img.onerror = () => { setTimeout(connect, 1000); };
  }
  connect();
</script>
</body>
</html>''';

  // Escapes a value for a single-quoted JS string inside an HTML <script>.
  String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '')
      .replaceAll('<', '\\x3C');

  String _buildHtml() {
    final safeToken = _escape(_streamToken ?? '');
    final safeModel = _escape(_modelId ?? '');
    final safePrompt = _escape(_facePrompt);
    final enhanceJs = _promptEnhance ? 'true' : 'false';
    final safeReference = _escape(_referenceUrl ?? '');
    final faceDataUrl = widget.faceImageBase64 != null
        ? 'data:image/jpeg;base64,${widget.faceImageBase64}'
        : '';
    final port = _port.toString();
    final externalJs = _external ? 'true' : 'false';
    final pageKey = _pageKey;
    final sdkVersion = _sdkVersion;
    final initCredits =
        _creditsRemaining != null ? _creditsRemaining!.toStringAsFixed(1) : '';
    final logoHtml = _logoBase64.isNotEmpty
        ? '<img src="data:image/png;base64,$_logoBase64" alt="RealFaceAI" class="logo-img">'
        : '<span class="logo-text">RealFace<em>AI</em></span>';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>RealFaceAI · Live</title>
<style>
  :root {
    /* RealFaceAI monitor palette (mirrors AppColors) */
    --bg:      #0F1117;
    --surface: #161922;
    --raised:  #1B1E28;
    --border:  #272B37;
    --text:    #F2F4F8;
    --muted:   #8A91A3;
    --green:   #3FCB94;
    --red:     #E5322D;
    --amber:   #7B7EFF;
    --cobalt:  #3A3DFF;
    --mono:    ui-monospace, 'JetBrains Mono', Consolas, monospace;
  }
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body {
    height:100%; width:100%;
    background:var(--bg); color:var(--text);
    font-family:'Inter',system-ui,-apple-system,'Segoe UI',sans-serif;
    overflow:hidden; -webkit-font-smoothing:antialiased;
  }
  .app { height:100%; display:flex; flex-direction:column; }

  /* ── Top bar ── */
  .topbar {
    height:56px; flex-shrink:0;
    background:var(--surface); border-bottom:1px solid var(--border);
    display:flex; align-items:center; padding:0 16px; gap:14px;
  }
  .logo-img  { height:24px; width:auto; object-fit:contain; display:block; }
  .logo-text { font-weight:700; letter-spacing:-.2px; font-size:16px; }
  .logo-text em { font-style:normal; color:var(--amber); }
  .spacer { flex:1; }
  .statuschip {
    display:flex; align-items:center; gap:8px;
    font-size:12.5px; color:var(--muted);
    background:var(--bg); border:1px solid var(--border);
    border-radius:999px; padding:7px 14px; max-width:55%;
  }
  .statuschip span { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .dot { width:7px; height:7px; border-radius:50%; background:#3A4048; flex-shrink:0; transition:background .3s; }
  .dot.live { background:var(--green); box-shadow:0 0 6px var(--green); }

  /* ── Buttons ── */
  button {
    font:inherit; border:none; border-radius:8px; cursor:pointer;
    font-weight:600; font-size:13px; padding:10px 16px;
    display:flex; align-items:center; justify-content:center; gap:6px;
    transition:opacity .15s, background .15s;
  }
  button:disabled { opacity:.4; cursor:not-allowed; }
  #backBtn {
    background:transparent; color:var(--muted);
    border:1px solid var(--border); padding:7px 12px; font-size:12.5px;
  }
  #backBtn:hover { color:var(--text); border-color:#4A5462; }
  #startBtn { background:var(--cobalt); color:#fff; }
  #startBtn:hover:not(:disabled) { background:#5457FF; }
  #stopBtn  { background:var(--red);   color:#fff; }
  #applyFaceBtn {
    background:var(--raised); color:var(--text);
    border:1px solid #3A4452; display:none;
  }
  #applyFaceBtn.visible { display:flex; }

  /* ── Workspace: stage | sidebar ── */
  .workspace { flex:1; min-height:0; display:flex; }
  .stage { flex:1; min-width:0; padding:16px; display:flex; }
  .screen {
    position:relative; flex:1; min-width:0;
    background:#000; border:1px solid var(--border);
    border-radius:12px; overflow:hidden;
  }
  video { width:100%; height:100%; object-fit:contain; display:block; background:#000; }
  .local-cell { display:none; }   /* camera is captured for the model, never shown */
  #remoteView { position:absolute; inset:0; }
  /* The SDK view's root sets no size and all its layers are absolute, so it
     collapses to 0 px tall unless told to fill the container. */
  #remoteView > div { width:100%; height:100%; }

  .ph {
    position:absolute; inset:0;
    display:flex; flex-direction:column; align-items:center; justify-content:center;
    gap:12px; color:#3A4048; pointer-events:none;
  }
  .ph svg  { width:40px; height:40px; opacity:.5; }
  .ph span { font-size:13px; }

  .live-tag {
    display:none; position:absolute; top:10px; left:10px;
    font-size:11px; font-weight:600; letter-spacing:.2px;
    background:rgba(229,50,45,.92); color:#fff;
    padding:4px 10px; border-radius:999px; pointer-events:none;
  }
  body.live .live-tag { display:block; }

  .side {
    width:320px; flex-shrink:0; overflow-y:auto;
    padding:16px 16px 16px 0; display:flex; flex-direction:column; gap:14px;
  }
  .panel { background:var(--surface); border:1px solid var(--border); border-radius:12px; }
  .panel-h {
    height:44px; padding:0 14px; display:flex; align-items:center;
    font-size:13px; font-weight:600;
    color:var(--muted); border-bottom:1px solid var(--border);
  }
  .panel-b { padding:14px; display:flex; flex-direction:column; gap:8px; }

  /* Session stats */
  .stat { display:flex; align-items:baseline; justify-content:space-between; gap:10px;
          padding:6px 0; border-bottom:1px solid var(--border); }
  .stat:last-child { border-bottom:none; }
  .stat label { font-size:11.5px; color:var(--muted); }
  .stat b { font-family:var(--mono); font-size:15px; font-weight:700; }
  #hudCredits { color:var(--green); }
  #hudRemain  { color:var(--amber); }

  /* Controls */
  .row2 { display:grid; grid-template-columns:1fr 1fr; gap:8px; }

  /* OBS */
  #obsBtn {
    background:var(--raised); color:var(--text); border:1px solid #3A4452;
    opacity:.45; pointer-events:none;
  }
  #obsBtn.visible { opacity:1; pointer-events:auto; }
  #obsBtn.visible:hover { background:#252B33; }
  #obsBtn.active { background:rgba(3,166,109,.22); border-color:var(--green); color:#fff; }
  #obsUrlBadge { display:none; gap:6px; }
  #obsUrlBadge input {
    flex:1; min-width:0; background:var(--bg); color:var(--text);
    border:1px solid var(--border); border-radius:4px;
    font-family:var(--mono); font-size:11px; padding:7px 8px;
  }
  #obsCopyBtn { background:var(--raised); border:1px solid #3A4452; color:var(--text); padding:6px 10px; font-size:11.5px; }
  .hint { font-size:11px; line-height:1.5; color:var(--muted); }

  /* ── Overlays ── */
  #errOverlay, #stoppedOverlay {
    display:none; position:fixed; inset:0;
    background:rgba(15,17,23,.94);
    flex-direction:column; align-items:center; justify-content:center;
    gap:16px; padding:32px; text-align:center;
  }
  #errOverlay { z-index:99; }
  #stoppedOverlay { z-index:98; gap:18px; }
  #errOverlay.show, #stoppedOverlay.show { display:flex; }
  .err-icon  { font-size:40px; }
  .err-msg   { color:#ccc; font-size:14px; max-width:420px; line-height:1.6; }
  #retryBtn  { background:var(--cobalt); color:#fff; padding:10px 24px; font-size:14px; }
  .stop-icon  { font-size:44px; }
  .stop-title { color:var(--text); font-size:18px; font-weight:700; }
  .stop-sub   { color:var(--muted); font-size:13px; }
  .overlay-actions { display:flex; gap:10px; flex-wrap:wrap; justify-content:center; }
  .btn-back { background:var(--cobalt); color:#fff; padding:10px 22px; font-size:13px; }

  /* ── Narrow: sidebar drops below the stage ── */
  @media (max-width: 860px) {
    .workspace { flex-direction:column; overflow-y:auto; }
    .stage { flex:none; height:52vh; min-height:240px; }
    .side  { width:auto; overflow:visible; padding:0 12px 12px; }
  }
</style>

<!-- SDK served locally — no external URLs, no provider branding in traffic -->
<script type="importmap">
  { "imports": { "rt-sdk": "http://127.0.0.1:$port/static/rt.js?v=$sdkVersion" } }
</script>
</head>
<body>
<div class="app">

  <!-- ── Top bar ── -->
  <header class="topbar">
    <button id="backBtn">← Back</button>
    $logoHtml
    <div class="spacer"></div>
    <div class="statuschip">
      <div class="dot" id="liveDot"></div>
      <span id="statusText">Ready. Press Start to go live</span>
    </div>
  </header>

  <main class="workspace">

    <!-- ── Stage: the AI output, as large as the window allows ── -->
    <section class="stage">
      <div class="screen">
        <!-- Camera is still captured and fed to the model; it is just not
             rendered. Kept in the DOM so localVideo / localPh keep working. -->
        <div class="local-cell">
          <div id="localPh"></div>
          <video id="localVideo" autoplay muted playsinline></video>
        </div>

        <!-- The SDK's output view mounts here; it holds the first frames back
             until the model output has warmed up, then fades it in. -->
        <div id="remoteView"></div>
        <div class="ph" id="remotePh">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <circle cx="12" cy="12" r="9"/><path d="M12 8v4l2 2"/>
          </svg>
          <span>AI output appears here</span>
        </div>
        <span class="live-tag">● Live</span>
      </div>
    </section>

    <!-- ── Sidebar: session · controls · OBS ── -->
    <aside class="side">

      <div class="panel">
        <div class="panel-h">Session</div>
        <div class="panel-b">
          <div class="stat"><label>Elapsed</label><b id="hudTime">--:--</b></div>
          <div class="stat"><label>Credits</label><b id="hudCredits">—</b></div>
          <div class="stat"><label>Time left</label><b id="hudRemain">—</b></div>
        </div>
      </div>

      <div class="panel">
        <div class="panel-h">Controls</div>
        <div class="panel-b">
          <div class="row2">
            <button id="startBtn">▶ Start</button>
            <button id="stopBtn" disabled>■ Stop</button>
          </div>
          <button id="applyFaceBtn">😊 Re-apply face</button>
        </div>
      </div>

      <div class="panel">
        <div class="panel-h">OBS output</div>
        <div class="panel-b">
          <button id="obsBtn" title="Toggle OBS frame relay">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
              <path d="M15 3h6v6M9 21H3v-6M21 3l-9 9M3 21l9-9"/>
            </svg>
            <span id="obsLabel">Send to OBS</span>
          </button>
          <div id="obsUrlBadge">
            <input id="obsUrlInput" readonly value="">
            <button id="obsCopyBtn">Copy</button>
          </div>
          <div class="hint">Start the stream, press <b>Send to OBS</b>, then paste the URL into an OBS Browser Source (1920 × 1080).</div>
        </div>
      </div>

    </aside>
  </main>
</div>

<!-- ── Error overlay ── -->
<div id="errOverlay">
  <div class="err-icon">⚠️</div>
  <div class="err-msg" id="errMsg">An error occurred.</div>
  <button id="retryBtn">↻ Try again</button>
</div>

<!-- ── Stopped overlay ── -->
<div id="stoppedOverlay">
  <div class="stop-icon">⏹</div>
  <div class="stop-title">Stream ended</div>
  <div class="stop-sub" id="stopSub">Your session has been stopped.</div>
  <div class="overlay-actions">
    <button class="btn-back" id="goBackBtn">← Back to studio</button>
  </div>
</div>

<script type="module">
// SDK imported from local server — no external network call
import {
  XmaxClient, XmaxConfiguration, XmaxEnvironment, RealtimeConfiguration,
  RealtimeContext, RealtimeVideoFormat, RealtimeConnectionState,
  XmaxRealtimeVideoView, VideoContentMode, XmaxErrorCode, supportedVideoFormats,
} from 'rt-sdk';

// ── Config injected by Flutter ────────────────────────────────────────────────
const TOKEN    = '$safeToken';
const MODEL_ID = '$safeModel';          // chosen by the backend
const FACE_PROMPT = '$safePrompt';      // chosen by the backend
const PROMPT_ENHANCE = $enhanceJs;
const FACE_URL = '$faceDataUrl';
const REFERENCE_URL = '$safeReference'; // face uploaded by the backend, if it could
const SERVER   = 'http://127.0.0.1:$port';
const EXTERNAL = $externalJs;           // true = running in the user's browser (Windows)
const APP_KEY  = '$pageKey';

// ── App bridge ────────────────────────────────────────────────────────────────
// WebView: JS handlers. Browser: POST to the app's local server.
function notifyApp(name, arg) {
  if (!EXTERNAL) {
    if (window.flutter_inappwebview) return window.flutter_inappwebview.callHandler(name, arg);
    return Promise.resolve();
  }
  const route = { onStreamStarted: 'started', onStreamStopped: 'stopped', onError: 'closed', onGoBack: 'back' }[name];
  if (!route) return Promise.resolve();
  return fetch(SERVER + '/api/' + route + '?k=' + APP_KEY, { method: 'POST' }).catch(() => {});
}

// Browser mode: poll the app for credits / forced stop. If the app is gone
// (closed, navigated away) the poll fails — stop rather than stream unbilled.
let _statusPoll = null;
function _startStatusPoll() {
  if (!EXTERNAL || _statusPoll) return;
  let failures = 0;
  _statusPoll = setInterval(async () => {
    try {
      const res = await fetch(SERVER + '/api/status?k=' + APP_KEY, { cache: 'no-store' });
      const s = await res.json();
      failures = 0;
      if (s.credits) hudCredits.textContent = s.credits;
      const hudR = document.getElementById('hudRemain');
      if (s.remain && hudR) hudR.textContent = s.remain;
      if (s.stop) stopStream(s.stop);
    } catch (_) {
      if (++failures >= 3) stopStream('The RealFaceAI app was closed. Reopen it to keep streaming.');
    }
  }, 2000);
}
function _stopStatusPoll() {
  if (_statusPoll) { clearInterval(_statusPoll); _statusPoll = null; }
}
window.addEventListener('pagehide', () => {
  if (EXTERNAL && realtime) navigator.sendBeacon(SERVER + '/api/closed?k=' + APP_KEY);
});

// ── Camera ────────────────────────────────────────────────────────────────────
// Windows laptops (HP Omen, HP Wide Vision…) expose several cameras, including
// an IR (Windows Hello) one that can be picked by default and gives no usable
// picture. Try relaxed constraints, then each real camera by id. Permission
// errors are thrown straight away; busy/overconstrained ones move on.
const _isIrCamera = (label) => /(\\bir\\b|infrared|depth|hello)/i.test(label || '');

async function openCamera(fps, mw, mh) {
  const ideal = { frameRate: { ideal: fps }, width: { ideal: mw }, height: { ideal: mh } };
  let lastErr = null;
  const tryOpen = async (video) => {
    try { return await navigator.mediaDevices.getUserMedia({ video, audio: false }); }
    catch (e) {
      if (e && (e.name === 'NotAllowedError' || e.name === 'SecurityError')) throw e;
      console.warn('[Stream] camera attempt failed: ' + (e && e.name) + ' — ' + (e && e.message));
      lastErr = e;
      return null;
    }
  };

  let stream = await tryOpen(ideal) || await tryOpen(true);

  // Device labels are only readable after permission was granted.
  let cams = [];
  try { cams = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === 'videoinput'); } catch (_) {}
  console.log('[Stream] cameras: ' + (cams.map(d => d.label || '(unnamed)').join(' | ') || 'none'));

  const track = stream && stream.getVideoTracks()[0];
  if (track && !_isIrCamera(track.label)) {
    console.log('[Stream] using camera: ' + track.label);
    return stream;
  }

  // Nothing opened, or Windows picked the IR camera: try real cameras first.
  const currentId = track && track.getSettings ? track.getSettings().deviceId : null;
  const ordered = cams.filter(d => !_isIrCamera(d.label)).concat(cams.filter(d => _isIrCamera(d.label)));
  for (const d of ordered) {
    if (d.deviceId && d.deviceId === currentId) continue;
    const s = await tryOpen({ ...ideal, deviceId: { exact: d.deviceId } })
           || await tryOpen({ deviceId: { exact: d.deviceId } });
    if (s) {
      if (stream) stream.getTracks().forEach(t => t.stop());
      console.log('[Stream] using camera: ' + d.label);
      return s;
    }
  }
  if (stream) return stream;
  throw lastErr || Object.assign(new Error('No camera found'), { name: 'NotFoundError' });
}

// ── DOM refs ─────────────────────────────────────────────────────────────────
const startBtn       = document.getElementById('startBtn');
const stopBtn        = document.getElementById('stopBtn');
const applyFaceBtn   = document.getElementById('applyFaceBtn');
const obsBtn         = document.getElementById('obsBtn');
const obsUrlBadge    = document.getElementById('obsUrlBadge');
const localVideo     = document.getElementById('localVideo');

// AI output: the SDK view (warmup + fade-in). Its <video> also feeds the OBS
// relay below.
const remoteView = new XmaxRealtimeVideoView({
  videoContentMode: VideoContentMode.fit,
  isInteractionEnabled: false,
});
remoteView.attach(document.getElementById('remoteView'));
const remoteVideo    = remoteView.videoElement;
const localPh        = document.getElementById('localPh');
const remotePh       = document.getElementById('remotePh');
const liveDot        = document.getElementById('liveDot');
const statusText     = document.getElementById('statusText');
const errOverlay     = document.getElementById('errOverlay');
const errMsg         = document.getElementById('errMsg');
const stoppedOverlay = document.getElementById('stoppedOverlay');
const hudTime        = document.getElementById('hudTime');
const hudCredits     = document.getElementById('hudCredits');

// ── State ─────────────────────────────────────────────────────────────────────
let localStream  = null;   // our camera MediaStream (we own its tracks)
let realtime     = null;   // SDK realtime manager for this session
let rtLocal      = null;   // the camera as an SDK stream
let referenceUrl = REFERENCE_URL || null;   // uploaded face image, reused for re-apply

// ── OBS MJPEG relay ───────────────────────────────────────────────────────────
// requestVideoFrameCallback fires on each decoded frame (not a fixed timer).
// canvas.toBlob sends raw binary — no base64 overhead.
// Back-pressure flag (_obsPushPending) drops frames if the previous POST
// is still in flight, so a slow network never builds a queue.
let _obsRelayActive = false;
let _obsOffscreen   = null;
let _obsCtx         = null;
let _obsPushPending = false;

function _obsFrameCallback(now, metadata) {
  if (!_obsRelayActive) return;
  remoteVideo.requestVideoFrameCallback(_obsFrameCallback);
  if (_obsPushPending) return;
  if (!remoteVideo.srcObject || remoteVideo.readyState < 2) return;
  const w = remoteVideo.videoWidth  || 1280;
  const h = remoteVideo.videoHeight || 720;
  if (_obsOffscreen.width  !== w) _obsOffscreen.width  = w;
  if (_obsOffscreen.height !== h) _obsOffscreen.height = h;
  _obsCtx.drawImage(remoteVideo, 0, 0, w, h);
  _obsPushPending = true;
  _obsOffscreen.toBlob(async (blob) => {
    try {
      if (blob && _obsRelayActive) {
        await fetch(SERVER + '/push', {
          method: 'POST',
          headers: { 'Content-Type': 'image/jpeg' },
          body: blob,
        });
      }
    } catch (_) {}
    finally { _obsPushPending = false; }
  }, 'image/jpeg', 0.80);
}

function _startObsRelay() {
  if (_obsRelayActive) return;
  _obsOffscreen   = document.createElement('canvas');
  _obsCtx         = _obsOffscreen.getContext('2d');
  _obsRelayActive = true;
  _obsPushPending = false;
  remoteVideo.requestVideoFrameCallback(_obsFrameCallback);
}

function _stopObsRelay() {
  _obsRelayActive = false;
  _obsOffscreen   = null;
  _obsCtx         = null;
  _obsPushPending = false;
}

const obsLabel      = document.getElementById('obsLabel');
const obsUrlInput   = document.getElementById('obsUrlInput');

function _obsUiOff() {
  obsBtn.classList.remove('active');
  obsLabel.textContent      = 'Send to OBS';
  obsUrlBadge.style.display = 'none';
  obsUrlInput.value         = '';
}

window.toggleObs = function() {
  if (_obsRelayActive) {
    _stopObsRelay();
    _obsUiOff();
  } else {
    if (!remoteVideo.srcObject) return;
    _startObsRelay();
    obsBtn.classList.add('active');
    obsLabel.textContent      = 'Sending to OBS';
    obsUrlInput.value         = SERVER + '/popout';
    obsUrlBadge.style.display = 'flex';
  }
};

window.copyObsUrl = function() {
  obsUrlInput.select();
  try { navigator.clipboard.writeText(obsUrlInput.value); }
  catch (_) { document.execCommand('copy'); }
};

// ── Helpers ───────────────────────────────────────────────────────────────────
// Model / provider names are never shown to the user — scrub them from any
// text that reaches the screen (SDK errors can include them).
function scrub(msg) {
  let out = String(msg == null ? '' : msg);
  if (MODEL_ID) out = out.split(MODEL_ID).join('the AI model');
  return out
    .replace(/\\bx2\\.[0-9]\\b/gi, 'the AI model')
    .replace(/xmax(\\s?ai)?/gi, 'the AI service')
    .replace(/agora|trtc|vertc|volcengine/gi, 'the media server');
}

function setStatus(msg, live = false) {
  statusText.textContent = scrub(msg);
  liveDot.className = 'dot' + (live ? ' live' : '');
  document.body.classList.toggle('live', !!live);
}

function showError(msg) {
  msg = scrub(msg);
  errMsg.textContent = msg;
  errOverlay.classList.add('show');
  setStatus('Error — see details above');
  startBtn.disabled = false;
  stopBtn.disabled  = true;
  if (window._hudTimerInterval) { clearInterval(window._hudTimerInterval); window._hudTimerInterval = null; }
  hudTime.textContent = '--:--';
  _stopStatusPoll();
  notifyApp('onError', msg);
}

function dataUrlToBlob(dataUrl) {
  const [header, b64] = dataUrl.split(',');
  const mime  = header.match(/:(.*?);/)[1];
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  return new Blob([bytes], { type: mime });
}

// ── Session helpers ───────────────────────────────────────────────────────────
// The model takes the face as a URL: upload it to the provider's storage once
// per page and reuse it for every start / re-apply.
async function getReferenceUrl(client) {
  if (!FACE_URL) return null;
  if (referenceUrl) return referenceUrl;
  const blob = dataUrlToBlob(FACE_URL);
  const stored = await client.createStorageService().uploadImage({
    data: blob,
    fileName: 'face.jpg',
    contentType: blob.type || 'image/jpeg',
  });
  referenceUrl = stored.url;
  return referenceUrl;
}

function makeContext() {
  return new RealtimeContext(referenceUrl
    ? { prompt: FACE_PROMPT, referencePath: referenceUrl }
    : { prompt: FACE_PROMPT });
}

// The model's landscape camera format closest to 1080p (webcams are landscape).
function pickFormat() {
  let formats = [];
  try { formats = supportedVideoFormats(MODEL_ID) || []; } catch (_) {}
  const landscape = formats.filter(f => f.width >= f.height);
  return landscape.find(f => f.width === 1920) || landscape[0] || formats[0]
      || { width: 1920, height: 1080, fps: 30 };
}

// SDK / API failures → something the user can act on.
function friendlySdkError(e) {
  const code = e && e.code;
  const api  = e && e.apiCode;
  if (api === 46002) return 'Your streaming session expired. Press Start to try again.';
  if (api === 46018 || api === 46019) return 'This session reached its time or credit limit. Press Start to continue.';
  if (api === 46032) return 'Another stream is already running on your account. Stop it, then try again.';
  switch (code) {
    case XmaxErrorCode.invalidAPIKey:          return 'Your streaming session expired. Press Start to try again.';
    case XmaxErrorCode.unsafeImage:            return 'The face photo was rejected by the content safety check. Try a different photo.';
    case XmaxErrorCode.uploadError:            return 'Could not upload your face photo. Check your connection and try again.';
    case XmaxErrorCode.cameraPermissionDenied: return 'Camera access was denied. Please allow camera access and try again.';
    case XmaxErrorCode.networkError:
    case XmaxErrorCode.rtcError:               return 'Network problem while streaming. Check your connection and try again.';
    case XmaxErrorCode.timeout:                return 'The AI service took too long to respond. Please try again.';
  }
  const msg = (e && e.message) ? e.message : String(e);
  // Server messages can arrive in Chinese; don't show those as-is.
  if (/[\\u4e00-\\u9fff]/.test(msg)) return 'The AI service could not start the stream' + (api ? ' (code ' + api + ')' : '') + '. Please try again.';
  return 'AI stream error: ' + msg;
}

// Ends the SDK session; our camera tracks are stopped by the caller.
function teardownSession() {
  const rt = realtime;
  realtime = null;
  rtLocal  = null;
  remoteView.track = undefined;
  if (rt) rt.close().catch((e) => console.warn('[Stream] close failed: ' + (e && e.message)));
}

let _sessionStarted = false;

function onState(state) {
  if (!realtime) return;   // late events from a closed session
  const s = state.connectionState;
  console.log('[Stream] state: ' + s + (state.reason ? ' (' + state.reason.kind + ')' : ''));
  if (state.reason && state.reason.kind === 'failure') {
    const e = state.reason.error;
    console.error('[Stream] SDK failure: ' + (e && e.code ? e.code + ' — ' : '') + (e && e.message));
    teardownSession();
    localStream?.getTracks().forEach(t => t.stop());
    localStream = null;
    showError(friendlySdkError(e));
    return;
  }
  if (s === RealtimeConnectionState.connecting) setStatus('Connecting to AI…');
  else if (s === RealtimeConnectionState.connected && !_sessionStarted) setStatus('Connected — starting AI…');
  else if (s === RealtimeConnectionState.starting && !_sessionStarted) setStatus('Starting AI…');
  else if (s === RealtimeConnectionState.generating) {
    setStatus('Streaming live', true);
    if (!_sessionStarted) onFirstOutput();
  }
}

// First AI frame is on screen: start the clock, billing and OBS.
function onFirstOutput() {
  _sessionStarted = true;
  if (window._remoteWatchdog) { clearTimeout(window._remoteWatchdog); window._remoteWatchdog = null; }
  console.log('[Stream] AI video playing at ' + remoteVideo.videoWidth + 'x' + remoteVideo.videoHeight);
  remotePh.style.display = 'none';
  stopBtn.disabled = false;
  obsBtn.classList.add('visible');

  // Elapsed timer — runs entirely in JS, no Dart round-trip needed
  hudTime.style.display = '';
  hudTime.textContent = '00:00';
  let _elapsed = 0;
  if (window._hudTimerInterval) clearInterval(window._hudTimerInterval);
  window._hudTimerInterval = setInterval(() => {
    _elapsed++;
    const m = String(Math.floor(_elapsed / 60)).padStart(2, '0');
    const s = String(_elapsed % 60).padStart(2, '0');
    hudTime.textContent = m + ':' + s;
  }, 1000);

  if (FACE_URL && FACE_URL.length > 0) applyFaceBtn.classList.add('visible');

  notifyApp('onStreamStarted');
  _startStatusPoll();
}

// ── START ─────────────────────────────────────────────────────────────────────
window.startStream = async function() {
  errOverlay.classList.remove('show');
  startBtn.disabled = true;
  _sessionStarted = false;
  setStatus('Requesting camera…');

  try {
    const fmt = pickFormat();
    localStream = await openCamera(fmt.fps || 30, fmt.width, fmt.height);
    localVideo.srcObject = localStream;
    localPh.style.display = 'none';

    // The SDK takes our camera track as-is (openCamera keeps its IR-camera
    // handling); tell it the size the camera actually delivers.
    const track = localStream.getVideoTracks()[0];
    const cam = (track.getSettings && track.getSettings()) || {};
    const videoFormat = new RealtimeVideoFormat({
      width:  cam.width  || fmt.width,
      height: cam.height || fmt.height,
      fps:    Math.round(cam.frameRate || fmt.fps || 30),
    });
    console.log('[Stream] camera ' + videoFormat.width + 'x' + videoFormat.height + '@' + videoFormat.fps);

    const client = new XmaxClient(new XmaxConfiguration({
      apiKey: TOKEN,
      environment: XmaxEnvironment.global,
    }));
    realtime = client.createRealtimeManager(new RealtimeConfiguration({ model: MODEL_ID }));
    await realtime.setStateListener(onState);
    // Startup breakdown (camera, session, RTC join, first frame, warmup) —
    // shows where the wait before the AI video goes.
    await realtime.setTimingListener((t) => console.log('[Stream] timing ' + JSON.stringify(t)));

    if (FACE_URL) {
      setStatus('Preparing your face…');
      await getReferenceUrl(client);
    }

    // Diagnostics: if the AI video never arrives, say what the session was
    // doing instead of sitting on "Connecting…" with the camera on.
    if (window._remoteWatchdog) clearTimeout(window._remoteWatchdog);
    window._remoteWatchdog = setTimeout(() => {
      if (_sessionStarted || !realtime) return;
      const st = realtime.currentState.connectionState;
      console.warn('[Stream] no AI video after 45s; model=' + MODEL_ID + ' state=' + st);
      setStatus('Still waiting for the AI video (' + st + ')…');
    }, 45000);

    rtLocal = await realtime.createExternalVideoStream({ videoTrack: track, videoFormat });
    setStatus('Connecting to AI…');
    // Prompt + face go with the start, so the first frame out is already
    // transformed (no flash of the raw camera).
    const remote = await realtime.startGeneration({ localStream: rtLocal, context: makeContext() });
    if (realtime) remoteView.track = remote.videoTrack;

  } catch (err) {
    console.error('[Stream] start failed: ' + (err && err.code ? err.code + ' — ' : '') + ((err && err.message) ? err.message : String(err)));
    if (window._remoteWatchdog) { clearTimeout(window._remoteWatchdog); window._remoteWatchdog = null; }
    const handled = !realtime && errOverlay.classList.contains('show');
    teardownSession();
    localStream?.getTracks().forEach(t => t.stop());
    localStream = null;
    if (handled) return;   // onState already reported this failure
    let friendly = (err && err.message) ? err.message : String(err);
    const name = (err && err.name) || '';
    if (name === 'NotAllowedError' || friendly.includes('Permission denied') || friendly.includes('NotAllowedError')) {
      friendly = EXTERNAL
        ? 'Camera access was denied. Click the camera icon in the address bar, allow the camera, then try again. Also check Windows Settings → Privacy & security → Camera.'
        : 'Camera access was denied. Please allow camera access and try again.';
    } else if (name === 'NotFoundError' || friendly.includes('NotFoundError') || friendly.includes('DevicesNotFound')) {
      friendly = 'No camera found. Please connect a webcam and try again.';
    } else if (name === 'NotReadableError' || name === 'TrackStartError' || name === 'AbortError') {
      friendly = 'Your camera is busy. Another app is using it (e.g. Zoom, Teams, OBS virtual camera, HP camera software). Close it and try again.';
    } else if (err && err.code) {
      friendly = friendlySdkError(err);
    }
    showError(friendly);
  }
};

// ── Face apply ────────────────────────────────────────────────────────────────
// startGeneration on a running task only updates its conditions.
async function _applyFaceToSession() {
  if (!realtime || !rtLocal) { setStatus('Face apply failed — no stream', true); return; }
  if (!referenceUrl) { setStatus('Face apply failed — no face image', true); return; }
  try {
    setStatus('Applying face…', true);
    await realtime.startGeneration({ localStream: rtLocal, context: makeContext() });
    setStatus('Streaming live ✓', true);
  } catch (e) {
    console.error('[Stream] re-apply failed', e);
    setStatus('Face apply failed — ' + (e?.message || String(e)), true);
  }
}

// ── STOP ──────────────────────────────────────────────────────────────────────
// Note on freezing for OBS: _stopObsRelay() just stops POSTing new frames to
// /push. The Dart server's _latestFrameBytes is never cleared, so /stream,
// /frame, and /popout keep serving that last frame indefinitely — OBS just
// naturally holds on the last AI frame, paused, with no extra code needed.
// reason: string when the app stops the stream (e.g. out of credits);
// a click Event (ignored) when the user presses Stop.
window.stopStream = function(reason) {
  const why = (typeof reason === 'string' && reason) ? reason : '';
  console.log('[Stream] stopped: ' + (why || 'by user'));
  const stopSub = document.getElementById('stopSub');
  if (stopSub) stopSub.textContent = scrub(why) || 'Your session has been stopped.';
  if (window._remoteWatchdog) { clearTimeout(window._remoteWatchdog); window._remoteWatchdog = null; }
  _sessionStarted = false;
  _stopObsRelay();
  obsBtn.classList.remove('visible');
  _obsUiOff();

  teardownSession();
  localStream?.getTracks().forEach(t => t.stop());
  localStream = null;

  localVideo.srcObject  = null;
  localPh.style.display  = '';
  remotePh.style.display = '';

  applyFaceBtn.classList.remove('visible');
  startBtn.disabled = false;
  stopBtn.disabled  = true;
  setStatus('Stopped');

  if (window._hudTimerInterval) { clearInterval(window._hudTimerInterval); window._hudTimerInterval = null; }
  hudTime.textContent = '--:--';
  const hudR = document.getElementById('hudRemain');
  if (hudR) hudR.textContent = '—';

  stoppedOverlay.classList.add('show');
  _stopStatusPoll();

  // Browser: the app fetches a fresh token, then we reload to pick it up
  // (the WebView is reloaded by the app itself).
  notifyApp('onStreamStopped').then((r) => { if (EXTERNAL && r && r.ok) location.reload(); });
};

window.retryStream = function() {
  errOverlay.classList.remove('show');
  notifyApp('onStreamStopped').then((r) => { if (EXTERNAL && r && r.ok) location.reload(); });
};

window.applyFace = async function() {
  if (!realtime || !FACE_URL) return;
  applyFaceBtn.disabled = true;
  await _applyFaceToSession();
  applyFaceBtn.disabled = false;
};

window.goBack = function() {
  if (EXTERNAL) {
    // End the session here; stopStream() would reload the page.
    _stopStatusPoll();
    teardownSession();
    localStream?.getTracks().forEach(t => t.stop());
    localStream = null;
  }
  notifyApp('onGoBack').then(() => {
    if (EXTERNAL) document.body.innerHTML = '<div style="height:100%;display:flex;align-items:center;justify-content:center;color:#8A91A3;font-family:system-ui">Session closed. You can close this tab.</div>';
  });
};

// ── Wire buttons ──────────────────────────────────────────────────────────────
document.getElementById('startBtn').addEventListener('click', startStream);
document.getElementById('stopBtn').addEventListener('click', stopStream);
document.getElementById('retryBtn').addEventListener('click', retryStream);
document.getElementById('applyFaceBtn').addEventListener('click', applyFace);
document.getElementById('obsBtn').addEventListener('click', toggleObs);
document.getElementById('obsCopyBtn').addEventListener('click', copyObsUrl);
document.getElementById('backBtn').addEventListener('click', goBack);
document.getElementById('goBackBtn').addEventListener('click', goBack);

// Show initial credits if available at page load
const _initCr = '$initCredits';
if (_initCr && _initCr !== 'null' && _initCr !== '') {
  hudCredits.textContent   = _initCr + ' credits';
  hudCredits.style.display = '';
}
</script>

<!-- If the SDK module fails to load (missing/broken rt.js, import error), none
     of the module above runs and Start would silently do nothing. Classic
     script: runs regardless, and 'load' fires after module scripts settle. -->
<script>
window.addEventListener('load', function() {
  if (typeof window.startStream === 'function') return;
  var msg = 'The streaming engine failed to load. Please restart the app — if this keeps happening, reinstall or update it.';
  console.error('[Stream] SDK module failed to load; startStream is undefined');
  function fail() {
    document.getElementById('errMsg').textContent = msg;
    document.getElementById('errOverlay').classList.add('show');
    document.getElementById('statusText').textContent = 'Error — streaming engine unavailable';
    if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onError', msg);
  }
  document.getElementById('startBtn').addEventListener('click', fail);
  document.getElementById('retryBtn').addEventListener('click', function() { location.reload(); });
  ['backBtn', 'goBackBtn'].forEach(function(id) {
    document.getElementById(id).addEventListener('click', function() {
      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onGoBack');
    });
  });
  fail();
});
</script>
</body>
</html>''';
  }

  // ── WebView settings ──────────────────────────────────────────────────────
  InAppWebViewSettings _webSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        iframeAllow: 'camera *; microphone *',
        supportZoom: false,
        useShouldOverrideUrlLoading: false,
        allowUniversalAccessFromFileURLs: true,
        allowFileAccessFromFileURLs: true,
        javaScriptCanOpenWindowsAutomatically: true,
        isInspectable: true,
        transparentBackground: false,
        useHybridComposition: true,
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          if (_phase == _Phase.ready && _port != null && _external)
            _buildBrowserPanel(),
          if (_phase == _Phase.ready && _port != null && !_external)
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('http://127.0.0.1:$_port'),
              ),
              initialSettings: _webSettings(),
              onWebViewCreated: (controller) {
                _webViewController = controller;

                controller.addJavaScriptHandler(
                  handlerName: 'onStreamStarted',
                  callback: (_) => _onPageStarted(),
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onError',
                  callback: (args) {
                    final msg =
                        args.isNotEmpty ? args[0].toString() : 'Stream error';
                    debugPrint('[RealtimeScreen] JS error: $msg');
                    if (!mounted) return;
                    setState(() => _streaming = false);
                    _stopElapsedTimer();
                    _stopHeartbeat();
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onGoBack',
                  callback: (_) => _onPageBack(),
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onStreamStopped',
                  callback: (_) async {
                    await _onPageStopped();
                    // Reload the WebView — new token will be baked into fresh HTML
                    await _webViewController?.reload();
                  },
                );
              },
              onPermissionRequest: (controller, request) async {
                debugPrint('[RealtimeScreen] Permission: ${request.resources}');
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              onConsoleMessage: (_, msg) =>
                  debugPrint('[WebView] ${msg.message}'),
              onLoadError: (_, url, code, message) =>
                  debugPrint('[WebView] Load error $code: $message'),
            ),
          if (_phase != _Phase.ready && _phase != _Phase.error)
            _buildLoadingOverlay(),
          if (_phase == _Phase.error) _buildErrorOverlay(),
        ],
      ),
    );
  }

  // ── Windows: stream runs in the browser; the app keeps the server alive ────
  Widget _buildBrowserPanel() {
    final url = 'http://127.0.0.1:$_port';
    // The app theme gives outlined buttons a light card fill; this panel is
    // on the dark stream surface.
    final outlined = OutlinedButton.styleFrom(
      foregroundColor: AppColors.screenText,
      backgroundColor: AppColors.screenRaised,
      side: const BorderSide(color: AppColors.screenBorder),
      minimumSize: const Size(0, 44),
    );
    return Container(
      color: AppColors.screen,
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                    _streaming
                        ? Icons.sensors_rounded
                        : Icons.open_in_browser_rounded,
                    color: AppColors.accent,
                    size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                _streaming
                    ? 'You’re live in your browser'
                    : 'Stream opened in your browser',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.screenText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Press Start in the browser tab and allow camera access. '
                'Keep this app open while you stream — closing it ends the session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.screenMuted, fontSize: 14.5, height: 1.5),
              ),
              const SizedBox(height: 20),
              SelectableText(
                url,
                style: TextStyle(
                    color: AppColors.accent,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 13),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    style: outlined,
                    onPressed: _onPageBack,
                    child: const Text('Back to studio'),
                  ),
                  OutlinedButton.icon(
                    style: outlined,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy link'),
                    onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                  ),
                  ElevatedButton.icon(
                    style:
                        ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: const Text('Reopen browser'),
                    onPressed: _openInBrowser,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    final label = switch (_phase) {
      _Phase.fetchingToken => 'Getting stream token…',
      _Phase.startingServer => 'Starting local server…',
      _Phase.ready => '',
      _Phase.error => '',
    };
    return Container(
      color: AppColors.bg,
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
                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: AppColors.screen,
      padding: const EdgeInsets.all(40),
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
                    onPressed: () => context.go('/playground'),
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

// ── Phase enum ────────────────────────────────────────────────────────────────
enum _Phase { fetchingToken, startingServer, ready, error }