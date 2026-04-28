import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/constants.dart';

class SocialLoginButtons extends StatelessWidget {
  final Future<void> Function(String provider, String idToken, String? name)
      onSocialLogin;
  final bool isLoading;

  const SocialLoginButtons({
    super.key,
    required this.onSocialLogin,
    this.isLoading = false,
  });

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    try {
      // 웹은 index.html의 google-signin-client_id 메타 태그를 자동으로 사용한다.
      final googleSignIn = GoogleSignIn(scopes: const ['email']);
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return;

      await onSocialLogin('google', idToken, account.displayName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google 로그인 실패: $e')),
        );
      }
    }
  }

  Future<void> _handleAppleSignIn(BuildContext context) async {
    try {
      WebAuthenticationOptions? webOptions;
      if (kIsWeb) {
        if (AppConstants.appleWebServiceId.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Apple 웹 로그인 설정이 누락되었습니다 (Service ID)')),
            );
          }
          return;
        }
        final redirect = AppConstants.appleWebRedirectUri.isNotEmpty
            ? AppConstants.appleWebRedirectUri
            : '${Uri.base.origin}/api/auth/apple/web-callback';
        webOptions = WebAuthenticationOptions(
          clientId: AppConstants.appleWebServiceId,
          redirectUri: Uri.parse(redirect),
        );
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: webOptions,
      );

      final idToken = credential.identityToken;
      if (idToken == null) return;

      final name = [credential.givenName, credential.familyName]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');

      await onSocialLogin('apple', idToken, name.isEmpty ? null : name);
    } on SignInWithAppleAuthorizationException {
      // User cancelled — do nothing
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple 로그인 실패: $e')),
        );
      }
    }
  }

  bool get _showAppleButton {
    // Apple 로그인은 iOS와 Web에서 지원, Android는 미지원.
    if (kIsWeb) return AppConstants.appleWebServiceId.isNotEmpty;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Divider with "또는"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '또는',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Google button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : () => _handleGoogleSignIn(context),
            icon: Image.network(
              'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
              height: 20,
              width: 20,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.g_mobiledata, size: 24),
            ),
            label: const Text('Google로 계속하기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Apple button (iOS / Web)
        if (_showAppleButton)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : () => _handleAppleSignIn(context),
              icon: const Icon(Icons.apple, size: 24),
              label: const Text('Apple로 계속하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
      ],
    );
  }
}
