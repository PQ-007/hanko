/// Build-time configuration, passed with `--dart-define-from-file=env.json`.
///
/// These are the same public values the web app and the extension ship: the
/// publishable/anon key is safe on a client because Row Level Security is what
/// actually protects the data. They still live outside the repo so a key
/// rotation doesn't mean a code change.
///
///   flutter run --dart-define-from-file=env.json
class Config {
  const Config._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// The **Web** OAuth client ID — the same one in Supabase's Google provider
  /// "Client IDs" field, paired with the client secret.
  ///
  /// Native sign-in mints an ID token whose audience is this web client, which
  /// is what Supabase validates. The *Android* client ID is deliberately absent
  /// from this file: it belongs only in Supabase's allow-list. Putting it here
  /// produces tokens Supabase rejects with an opaque audience error.
  ///
  /// Left empty, the app falls back to the browser-redirect flow.
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get hasNativeGoogle => googleWebClientId.isNotEmpty;

  /// Where Supabase sends the browser back after Google sign-in. Must match
  /// both the intent-filter in AndroidManifest.xml and the redirect allow-list
  /// in the Supabase dashboard (Authentication → URL Configuration).
  static const authRedirect = 'com.hanko.mobile://login-callback';

  /// Public privacy-policy page, linked from Settings. Both app stores require
  /// one for an app with sign-in. Optional here: left empty, the link is
  /// hidden. Nothing else depends on any web server — the app talks only to
  /// Supabase plus public dictionary/translate endpoints (core/dictionary.dart).
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');

  /// The web app's address — only for building public deck links
  /// (`/share/<token>`, 0028), which open in any browser without an account.
  /// The phone itself never calls this server.
  static const webUrl = String.fromEnvironment('WEB_URL', defaultValue: 'https://hanko-amber.vercel.app');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
