// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:go_router/go_router.dart';

// import 'theme/app_theme.dart';
// import 'services/auth_provider.dart';
// import 'screens/auth/login_screen.dart';
// import 'screens/auth/forgot_password_screen.dart';
// import 'screens/auth/change_password_screen.dart';
// import 'screens/main_shell.dart';
// import 'screens/dashboard/dashboard_screen.dart';
// import 'screens/playground/playground_screen.dart';
// import 'screens/playground/realtime_stream_screen.dart';
// import 'screens/keys/api_keys_screen.dart';
// import 'screens/billing/billing_screen.dart';
// import 'screens/usage/usage_screen.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   final authProvider = AuthProvider();
//   await authProvider.init();

//   runApp(
//     ChangeNotifierProvider.value(
//       value: authProvider,
//       child: RealFaceAIApp(authProvider: authProvider),
//     ),
//   );
// }

// class RealFaceAIApp extends StatefulWidget {
//   final AuthProvider authProvider;
//   const RealFaceAIApp({super.key, required this.authProvider});

//   @override
//   State<RealFaceAIApp> createState() => _RealFaceAIAppState();
// }

// class _RealFaceAIAppState extends State<RealFaceAIApp> {
//   late final GoRouter _router;

//   @override
//   void initState() {
//     super.initState();

//     // ── Create router ONCE — never recreated on rebuild ──────────────────
//     // This prevents the polling-triggered rebuilds from resetting navigation.
//     _router = GoRouter(
//       // Always start on /splash. The redirect below immediately moves the user
//       // to the right screen once initialisation completes.
//       initialLocation: '/splash',
//       refreshListenable: widget.authProvider,
//       redirect: (context, state) {
//         final auth     = widget.authProvider;
//         final loggedIn = auth.isLoggedIn;
//         final loading  = auth.isInitialising;
//         final loc      = state.matchedLocation;

//         // ── Cold-start guard ─────────────────────────────────────────────
//         // While _loadProfile is running (including back-off retries),
//         // keep everyone on /splash so no screen ever renders with _user == null
//         // and no premature redirect to /login happens.
//         if (loading) return loc == '/splash' ? null : '/splash';

//         // ── Stream screen is self-contained — never redirect away from it ─
//         if (loc == '/stream') return null;

//         // ── Post-init routing ────────────────────────────────────────────
//         if (!loggedIn && loc != '/login' && loc != '/forgot-password') return '/login';
//         if (loggedIn  && (loc == '/login' || loc == '/forgot-password' || loc == '/splash')) return '/dashboard';

//         return null;
//       },
//       routes: [
//         // ── Splash / initialising screen ─────────────────────────────────
//         GoRoute(
//           path: '/splash',
//           builder: (_, __) => const _SplashScreen(),
//         ),

//         // ── Auth ─────────────────────────────────────────────────────────
//         GoRoute(
//           path: '/login',
//           builder: (_, __) => const LoginScreen(),
//         ),
//         GoRoute(
//           path: '/forgot-password',
//           builder: (_, __) => const ForgotPasswordScreen(),
//         ),

//         // ── Full-screen stream — outside ShellRoute so no sidebar ─────────
//         GoRoute(
//           path: '/stream',
//           builder: (context, state) {
//             final extra = state.extra as Map<String, dynamic>? ?? {};
//             return RealtimeStreamScreen(
//               model:           extra['model'] as String? ?? 'lucy-latest',
//               prompt:          extra['prompt'] as String?,
//               faceImageBase64: extra['faceImageBase64'] as String?,
//             );
//           },
//         ),

//         // ── Main app with sidebar ─────────────────────────────────────────
//         ShellRoute(
//           builder: (context, state, child) => MainShell(child: child),
//           routes: [
//             GoRoute(
//               path: '/dashboard',
//               builder: (_, __) => const DashboardScreen(),
//             ),
//             GoRoute(
//               path: '/playground',
//               builder: (_, __) => const PlaygroundScreen(),
//             ),
//             GoRoute(
//               path: '/keys',
//               builder: (_, __) => const ApiKeysScreen(),
//             ),
//             GoRoute(
//               path: '/billing',
//               builder: (_, __) => const BillingScreen(),
//             ),
//             GoRoute(
//               path: '/usage',
//               builder: (_, __) => const UsageScreen(),
//             ),
//             GoRoute(
//               path: '/change-password',
//               builder: (_, __) => const ChangePasswordScreen(),
//             ),
//           ],
//         ),
//       ],
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp.router(
//       title: 'RealFaceAI',
//       debugShowCheckedModeBanner: false,
//       theme: AppTheme.light,
//       routerConfig: _router,
//     );
//   }
// }

// // ── Splash screen shown during cold-start profile fetch ──────────────────────
// // Displayed whenever isInitialising == true.
// // Shows a retry counter so the user knows the app is working, not frozen.
// class _SplashScreen extends StatelessWidget {
//   const _SplashScreen();

//   @override
//   Widget build(BuildContext context) {
//     final auth = context.watch<AuthProvider>();
//     // Show retry hint only after the first attempt has failed.
//     final retrying = auth.isInitialising;

//     return Scaffold(
//       backgroundColor: AppColors.bg,
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             // Logo mark
//             Container(
//               width: 56,
//               height: 56,
//               decoration: BoxDecoration(
//                 color: AppColors.accent,
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
//             ),
//             const SizedBox(height: 24),
//             const Text(
//               'StreamAI',
//               style: TextStyle(
//                 color: AppColors.textPrimary,
//                 fontSize: 24,
//                 fontWeight: FontWeight.w800,
//                 letterSpacing: -0.5,
//               ),
//             ),
//             const SizedBox(height: 32),
//             const SizedBox(
//               width: 24,
//               height: 24,
//               child: CircularProgressIndicator(
//                 color: AppColors.accent,
//                 strokeWidth: 2.5,
//               ),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               retrying ? 'Connecting to server…' : 'Starting up…',
//               style: const TextStyle(
//                 color: AppColors.textSecondary,
//                 fontSize: 13,
//               ),
//             ),
//             const SizedBox(height: 6),
//             const Text(
//               'Please wait',
//               style: TextStyle(
//                 color: AppColors.textMuted,
//                 fontSize: 11,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
// lib/main.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'screens/account_suspended_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/billing/billing_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/keys/api_keys_screen.dart';
import 'screens/main_shell.dart';
import 'screens/maintenance_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/playground/native_stream_screen.dart';
import 'screens/playground/playground_screen.dart';
import 'screens/playground/realtime_stream_screen.dart';
import 'screens/update_required_screen.dart';
import 'screens/usage/usage_screen.dart';
import 'services/app_gate.dart';
import 'services/auth_provider.dart';
import 'services/theme_controller.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'widgets/brand.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Apply the saved appearance before the first frame.
  await ThemeController.instance.load();

  final authProvider = AuthProvider();

  // Start init() AFTER runApp so the splash screen renders immediately.
  // The router stays on /splash while isInitialising == true,
  // then redirects automatically once init() completes and notifyListeners() fires.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: AppGate.instance),
        ChangeNotifierProvider.value(value: UpdateService.instance),
        ChangeNotifierProvider.value(value: ThemeController.instance),
      ],
      child: RealFaceAIApp(authProvider: authProvider),
    ),
  );

  // Fire init in the background — splash is already visible at this point.
  authProvider.init();

  // Check for updates now, every 30 min, and on resume. A forced update
  // raises AppGate before the user can sign in.
  UpdateService.instance.start();
}

class RealFaceAIApp extends StatefulWidget {
  final AuthProvider authProvider;
  const RealFaceAIApp({super.key, required this.authProvider});

  @override
  State<RealFaceAIApp> createState() => _RealFaceAIAppState();
}

class _RealFaceAIAppState extends State<RealFaceAIApp> {
  late final GoRouter _router;

  static const _publicRoutes = {'/welcome', '/login', '/forgot-password'};
  static const _gateRoutes = {'/update-required', '/account-suspended'};

  @override
  void initState() {
    super.initState();

    // Router is created once — never recreated on rebuild.
    // This prevents polling-triggered rebuilds from resetting navigation.
    _router = GoRouter(
      initialLocation: '/splash',
      refreshListenable:
          Listenable.merge([widget.authProvider, AppGate.instance]),
      redirect: (context, state) {
        final auth = widget.authProvider;
        final loggedIn = auth.isLoggedIn;
        final loading = auth.isInitialising;
        final inMaint = auth.isInMaintenance;
        final loc = state.matchedLocation;

        // ── Maintenance — highest priority ────────────────────────────────
        // If the server is in maintenance, send everyone to /maintenance
        // regardless of auth state. Exempt /maintenance itself to avoid
        // redirect loops.
        if (inMaint) {
          return loc == '/maintenance' ? null : '/maintenance';
        }

        // ── Server-decided gates — block everything, including /stream ────
        // (the server also refuses the stream heartbeat, so a live session
        // is ending anyway).
        final gate = AppGate.instance;
        if (gate.requiredUpdate != null) {
          return loc == '/update-required' ? null : '/update-required';
        }
        if (gate.suspension != null) {
          return loc == '/account-suspended' ? null : '/account-suspended';
        }
        if (_gateRoutes.contains(loc)) {
          // Gate lifted — continue to wherever the user belongs.
          if (loading) return '/splash';
          if (loggedIn) return '/dashboard';
          return auth.onboardingDone ? '/login' : '/welcome';
        }

        // ── Cold-start guard ──────────────────────────────────────────────
        if (loading) return loc == '/splash' ? null : '/splash';

        // ── Stream screen is self-contained ───────────────────────────────
        if (loc == '/stream') return null;

        // ── First run: show the welcome tour once ─────────────────────────
        if (!loggedIn && !auth.onboardingDone && loc != '/welcome') {
          return '/welcome';
        }

        // ── Auth routing ──────────────────────────────────────────────────
        if (!loggedIn && !_publicRoutes.contains(loc)) {
          return '/login';
        }
        if (loggedIn && (_publicRoutes.contains(loc) || loc == '/splash')) {
          return '/dashboard';
        }

        return null;
      },
      routes: [
        // ── Splash ───────────────────────────────────────────────────────
        GoRoute(
          path: '/splash',
          builder: (_, __) => const _SplashScreen(),
        ),

        // ── Maintenance ───────────────────────────────────────────────────
        // MaintenanceScreen reads info from AuthProvider directly so we
        // don't need to pass it via state.extra (avoids stale data if the
        // server updates the message mid-session).
        GoRoute(
          path: '/maintenance',
          builder: (context, _) {
            final auth = context.read<AuthProvider>();
            return MaintenanceScreen(
              info: auth.maintenanceException!.info,
            );
          },
        ),

        // ── Blocking gates (see AppGate) ──────────────────────────────────
        GoRoute(
          path: '/update-required',
          pageBuilder: (_, __) => _fade(const UpdateRequiredScreen()),
        ),
        GoRoute(
          path: '/account-suspended',
          pageBuilder: (_, __) => _fade(const AccountSuspendedScreen()),
        ),

        // ── Onboarding + auth ─────────────────────────────────────────────
        GoRoute(
          path: '/welcome',
          pageBuilder: (_, __) => _fade(const OnboardingScreen()),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (_, state) => _fade(LoginScreen(
            startInRegister: state.uri.queryParameters['mode'] == 'register',
          )),
        ),
        GoRoute(
          path: '/forgot-password',
          pageBuilder: (_, __) => _fade(const ForgotPasswordScreen()),
        ),

        // ── Stream — full screen, no sidebar ─────────────────────────────
        GoRoute(
          path: '/stream',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            // The model comes from the backend, not from here.
            // Phones: native Xmax SDK. Desktop: WebView + Xmax web SDK (the
            // native Flutter SDK is iOS/Android only).
            if (Platform.isIOS || Platform.isAndroid) {
              return NativeStreamScreen(
                prompt: extra['prompt'] as String?,
                faceImageBase64: extra['faceImageBase64'] as String?,
              );
            }
            return RealtimeStreamScreen(
              prompt: extra['prompt'] as String?,
              faceImageBase64: extra['faceImageBase64'] as String?,
            );
          },
        ),

        // ── Main app with sidebar ─────────────────────────────────────────
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              pageBuilder: (_, __) => _fade(const DashboardScreen()),
            ),
            GoRoute(
              path: '/playground',
              pageBuilder: (_, __) => _fade(const PlaygroundScreen()),
            ),
            GoRoute(
              path: '/keys',
              pageBuilder: (_, __) => _fade(const ApiKeysScreen()),
            ),
            GoRoute(
              path: '/billing',
              pageBuilder: (_, __) => _fade(const BillingScreen()),
            ),
            GoRoute(
              path: '/usage',
              pageBuilder: (_, __) => _fade(const UsageScreen()),
            ),
            GoRoute(
              path: '/change-password',
              pageBuilder: (_, __) => _fade(const ChangePasswordScreen()),
            ),
          ],
        ),
      ],
    );
  }

  /// Quick cross-fade between pages: desktop apps don't slide.
  static CustomTransitionPage<void> _fade(Widget child) => CustomTransitionPage(
        child: child,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Rebuild the theme whenever the palette changes.
    context.watch<ThemeController>();
    return MaterialApp.router(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      routerConfig: _router,
    );
  }
}

// ── Splash screen ─────────────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final retrying = auth.isInitialising;

    return Scaffold(
      backgroundColor: AppColors.screen,
      body: Stack(
        children: [
          // Soft cobalt glow behind the mark.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 0.8,
                  colors: [Color(0x403A3DFF), Color(0x003A3DFF)],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandMark(size: 72)
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .scale(
                        begin: const Offset(0.92, 0.92),
                        duration: 500.ms,
                        curve: Curves.easeOutBack),
                const SizedBox(height: 24),
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'RealFace'),
                    TextSpan(
                        text: 'AI',
                        style: TextStyle(color: AppColors.cobaltLight)),
                  ]),
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: AppColors.screenText,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                  ),
                ).animate().fadeIn(delay: 120.ms, duration: 400.ms),
                const SizedBox(height: 6),
                const Text(
                  Brand.tagline,
                  style: TextStyle(color: AppColors.screenMuted, fontSize: 13.5),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                const SizedBox(height: 44),
                const SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.cobaltLight,
                      backgroundColor: AppColors.screenRaised,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  retrying ? 'Connecting to ${Brand.domain}…' : 'Starting up…',
                  style: const TextStyle(
                      color: AppColors.screenMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}