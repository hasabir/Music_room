import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/google_auth_service.dart';
import '../core/api/api_client.dart';

class _ConnectedColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const verified = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
}

/// Shows how the signed-in account authenticates, from the real
/// `AuthUser` fields (`email`, `is_email_verified`, `registration_method`,
/// `has_google_linked`).
///
/// A Google-registered account's sign-in method can't be changed here —
/// there's no "disconnect" endpoint, since that would leave the user
/// locked out (Google-only signups get an unusable password; see
/// `User.objects.create_user` in the backend). But an email/password
/// account that hasn't linked Google yet can do so via
/// `POST /api/v1/auth/google/link/` (`GoogleLinkView`), which requires
/// the Google account's email to match this account's email.
class ConnectedAccountsScreen extends StatefulWidget {
  const ConnectedAccountsScreen({super.key, required this.authUser});

  final AuthUser authUser;

  @override
  State<ConnectedAccountsScreen> createState() => _ConnectedAccountsScreenState();
}

class _ConnectedAccountsScreenState extends State<ConnectedAccountsScreen> {
  final _authApi = AuthApi();

  late AuthUser _authUser;
  bool _isLinking = false;

  @override
  void initState() {
    super.initState();
    _authUser = widget.authUser;
  }

  Future<void> _onLinkGoogle() async {
    setState(() => _isLinking = true);
    try {
      final idToken = await GoogleAuthService.signInAndGetIdToken();
      final updated = await _authApi.linkGoogleAccount(idToken: idToken);
      if (!mounted) return;
      setState(() => _authUser = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google account linked.')));
    } on GoogleAuthCancelled {
      // User backed out of the picker — nothing to report.
    } on GoogleAuthFailed catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGoogle = _authUser.registrationMethod == 'google';

    return Scaffold(
      backgroundColor: _ConnectedColors.background,
      appBar: AppBar(
        backgroundColor: _ConnectedColors.background,
        elevation: 0,
        title: const Text(
          'Connected Accounts',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w800,
            color: _ConnectedColors.headline,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Manage how you log in to your Music Room account.',
            style: TextStyle(color: _ConnectedColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (isGoogle)
            _AccountCard(
              icon: Icons.g_mobiledata_rounded,
              title: 'Google Account',
              subtitle: 'OAUTH PROVIDER',
              email: _authUser.email,
              note: 'This is your sign-in method for Music Room.',
            )
          else ...[
            _AccountCard(
              icon: Icons.mail_outline_rounded,
              title: 'Email Authentication',
              subtitle: 'PRIMARY LOGIN',
              email: _authUser.email,
              isVerified: _authUser.isEmailVerified,
            ),
            const SizedBox(height: 14),
            if (_authUser.hasGoogleLinked)
              const _AccountCard(
                icon: Icons.g_mobiledata_rounded,
                title: 'Google Account',
                subtitle: 'LINKED',
                email: '',
                note: 'You can also sign in with Google.',
              )
            else
              _LinkGoogleCard(isLinking: _isLinking, onLink: _onLinkGoogle),
          ],
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.email,
    this.isVerified,
    this.note,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String email;
  final bool? isVerified;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ConnectedColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ConnectedColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _ConnectedColors.background,
                child: Icon(icon, color: _ConnectedColors.headline, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: _ConnectedColors.body,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: _ConnectedColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(email, style: const TextStyle(color: _ConnectedColors.body, fontSize: 14)),
          ],
          if (isVerified != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  isVerified! ? Icons.check_circle : Icons.error_outline,
                  size: 16,
                  color: isVerified! ? _ConnectedColors.verified : _ConnectedColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  isVerified! ? 'VERIFIED' : 'NOT VERIFIED',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isVerified! ? _ConnectedColors.verified : _ConnectedColors.muted,
                  ),
                ),
              ],
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(note!, style: const TextStyle(color: _ConnectedColors.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _LinkGoogleCard extends StatelessWidget {
  const _LinkGoogleCard({required this.isLinking, required this.onLink});

  final bool isLinking;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ConnectedColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ConnectedColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _ConnectedColors.background,
                child: const Icon(
                  Icons.g_mobiledata_rounded,
                  color: _ConnectedColors.headline,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Account',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _ConnectedColors.body,
                      ),
                    ),
                    Text(
                      'NOT LINKED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: _ConnectedColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Link a Google account with the same email so you can sign in either way.',
            style: TextStyle(color: _ConnectedColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: isLinking ? null : onLink,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ConnectedColors.headline,
                side: const BorderSide(color: _ConnectedColors.gradientStart),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
              ),
              icon: isLinking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _ConnectedColors.headline,
                      ),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(
                isLinking ? 'Linking...' : 'Link Google Account',
                style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
