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

  /// Where Supabase sends the browser back after Google sign-in. Must match
  /// both the intent-filter in AndroidManifest.xml and the redirect allow-list
  /// in the Supabase dashboard (Authentication → URL Configuration).
  static const authRedirect = 'com.hanko.mobile://login-callback';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
