import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads Supabase credentials from `.env` and initializes the global client.
/// Call once at app start from `main()`. The SDK persists sessions in
/// platform secure storage (iOS Keychain / Android Keystore) by default —
/// no extra configuration needed for token security.
class SupabaseBootstrap {
  static bool _initialized = false;

  /// Length of the email OTP code, sourced from .env. Must match the value
  /// configured in Supabase Dashboard → Authentication → Providers → Email.
  /// Defaults to 6 (Supabase default) if not set.
  static int otpLength = 6;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    await dotenv.load(fileName: '.env');

    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty || url.contains('your-')) {
      throw StateError(
        'SUPABASE_URL is missing or unset in .env. '
        'Copy .env.example to .env and fill in your project credentials.',
      );
    }
    if (anonKey == null || anonKey.isEmpty || anonKey.contains('paste')) {
      throw StateError(
        'SUPABASE_ANON_KEY is missing or unset in .env. '
        'Grab it from Supabase Dashboard → Settings → API → "anon public".',
      );
    }

    final otpLenStr = dotenv.env['SUPABASE_OTP_LENGTH'];
    final parsed = int.tryParse(otpLenStr ?? '');
    if (parsed != null && parsed >= 6 && parsed <= 10) {
      otpLength = parsed;
    }

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      // Persist tokens in the platform's secure storage by default.
      // OTP-based auth — no password ever touches the device.
      authOptions: const FlutterAuthClientOptions(
        // PKCE adds a per-request verifier so a stolen auth code can't be
        // redeemed by an attacker. Default for new Supabase projects, but
        // declared here so it's obvious and durable across SDK upgrades.
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
      debug: kDebugMode,
    );

    _initialized = true;
  }
}

/// Shortcut to the global Supabase client.
SupabaseClient get supabase => Supabase.instance.client;
