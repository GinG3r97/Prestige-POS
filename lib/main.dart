import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'models/cart.dart';
import 'data/supabase_client.dart';
import 'design_system/colors.dart';
import 'features/auth/welcome_view.dart';
import 'features/login/login_view.dart';
import 'features/onboarding/onboarding_view.dart';
import 'features/pin/set_pin_view.dart';
import 'features/shell/nav_controller.dart';
import 'features/shell/shell_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Load Supabase before runApp so AppState can observe auth state from boot.
  await SupabaseBootstrap.ensureInitialized();
  runApp(const YosefPOSApp());
}

bool get _isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Shown for the brief moment after sign-in (or PIN sign-in) while
/// AppState fetches the tenant / re-filters permissions / settles the
/// shell. Avoids the user seeing Onboarding flash before the PIN screen,
/// or the nav items reshuffling after a cashier PIN's role kicks in.
///
/// Stateful so the spinner + caption scale-and-fade in (gentle 0.92 → 1.0
/// scale + opacity ramp) on first mount — feels intentional rather than a
/// hard-cut between routes.
class _PreparingStoreView extends StatefulWidget {
  const _PreparingStoreView({this.caption = 'Preparing your store…'});

  final String caption;

  @override
  State<_PreparingStoreView> createState() => _PreparingStoreViewState();
}

class _PreparingStoreViewState extends State<_PreparingStoreView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YColor.surface2,
      body: Center(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, child) {
            final t = Curves.easeOutCubic.transform(_anim.value);
            return Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: 16),
              Text(
                widget.caption,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Just a moment.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class YosefPOSApp extends StatelessWidget {
  const YosefPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: YColor.brand,
        primary: YColor.brand,
        surface: YColor.surface1,
      ),
      scaffoldBackgroundColor: YColor.surface2,
      useMaterial3: true,
    );

    // On iOS/macOS, leave the default text theme so Flutter resolves to SF Pro.
    // Elsewhere, swap in Inter (a free Apple-system-like UI font).
    final theme = _isApplePlatform
        ? baseTheme
        : baseTheme.copyWith(textTheme: GoogleFonts.interTextTheme());

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => NavController()),
        // Scope the cart so cart edits repaint only cart-watching widgets,
        // not every context.watch<AppState>() in the app. Same CartStore
        // instance AppState owns (provided by value, never recreated).
        ChangeNotifierProxyProvider<AppState, CartStore>(
          create: (ctx) => ctx.read<AppState>().cart,
          update: (_, app, __) => app.cart,
        ),
      ],
      child: MaterialApp(
        title: 'Prestige POS',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Consumer<AppState>(
          builder: (_, state, _) {
            // Pick the right destination for the current session state.
            // Wrapped in an AnimatedSwitcher below so swaps cross-fade
            // smoothly instead of the user seeing a jarring widget tree
            // replace (e.g. nav items rebuilding their permissions after
            // a PIN sign-in).
            Widget child;
            String key;
            if (!state.hasAccount) {
              child = const WelcomeView();
              key = 'welcome';
            } else if (state.isHydrating) {
              child = const _PreparingStoreView(
                  caption: 'Preparing your store…');
              key = 'hydrating';
            } else if (state.needsOnboarding) {
              child = const OnboardingView();
              key = 'onboarding';
            } else if (state.needsToSetPin) {
              child = const SetPinView();
              key = 'setpin';
            } else if (state.isLocking) {
              child = const _PreparingStoreView(
                  caption: 'Locking, please wait…');
              key = 'locking';
            } else if (!state.isAuthenticated) {
              child = const LoginView();
              key = 'login';
            } else if (state.isPinSettling) {
              child = const _PreparingStoreView(
                  caption: 'Welcome back…');
              key = 'settling';
            } else {
              child = const ShellView();
              key = 'shell';
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (w, anim) => FadeTransition(
                opacity: anim,
                child: w,
              ),
              child: KeyedSubtree(key: ValueKey(key), child: child),
            );
          },
        ),
      ),
    );
  }
}
