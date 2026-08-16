import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

/// Google sign-in, matching the web app — it is the only provider configured on
/// this Supabase project.
///
/// Two paths, in order of preference:
///
///  1. **Native** (`google_sign_in` → `signInWithIdToken`): the Android account
///     sheet, no browser bounce. Needs an Android OAuth client registered with
///     this app's package name and signing SHA-1, and that client ID added to
///     Supabase's Google "Client IDs" allow-list.
///  2. **Browser redirect** (`signInWithOAuth`): needs nothing but a redirect
///     URL, and is kept as a fallback because native depends on Play Services
///     being present and healthy. A dead sign-in button with no alternative is
///     the worst failure this screen can have — it's the first thing a new user
///     touches.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;
  // Revealed only when native sign-in fails, so the happy path stays a single
  // button rather than asking the user to pick a sign-in mechanism.
  bool _offerBrowser = false;

  static bool _googleInitialized = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on GoogleSignInException catch (e) {
      // debugPrint, not just the on-screen text: the UI truncates/wraps long
      // strings, and reading a dialog aloud to transcribe it loses exact
      // wording. This line shows up in `flutter run`'s terminal and in
      // `adb logcat` under the "flutter" tag verbatim.
      debugPrint(
        'GoogleSignInException code=${e.code.name} description=${e.description} details=${e.details}',
      );
      if (e.code != GoogleSignInExceptionCode.canceled) {
        if (mounted) {
          setState(() {
            _error = '${e.code.name}: ${e.description ?? "(no description)"}';
            _offerBrowser = true;
          });
        }
      }
    } on AuthException catch (e) {
      debugPrint('AuthException message=${e.message} statusCode=${e.statusCode} code=${e.code}');
      if (mounted) {
        setState(() {
          _error = e.message;
          _offerBrowser = true;
        });
      }
    } catch (e, st) {
      debugPrint('Sign-in failed: $e\n$st');
      if (mounted) {
        setState(() {
          _error = '$e';
          _offerBrowser = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInNative() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(serverClientId: Config.googleWebClientId);
      _googleInitialized = true;
    }
    if (!google.supportsAuthenticate()) {
      await _signInBrowser();
      return;
    }

    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token');
    }

    // Supabase accepts the ID token alone; the access token is passed when
    // available so the session can also carry Google API access later.
    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email', 'profile']);

    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization?.accessToken,
    );
  }

  Future<void> _signInBrowser() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Config.authRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hanko', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Verba non Acta',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(Config.hasNativeGoogle
                        ? _signInNative
                        : _signInBrowser),
                icon: const Icon(Icons.login),
                label: Text(_busy ? 'Нэвтэрч байна…' : 'Google-ээр нэвтрэх'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              if (_offerBrowser && Config.hasNativeGoogle) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => _run(_signInBrowser),
                  child: const Text('Хөтчөөр нэвтрэх'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
