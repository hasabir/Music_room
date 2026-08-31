import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/email_verification_pending_screen.dart';
import '../auth/welcome_screen.dart';
import '../core/auth/token_storage.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/profile_avatar.dart';
import '../profile/profile_models.dart';
import 'connected_accounts_screen.dart';
import 'update_password_screen.dart';

class _SettingsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const verified = Color(0xFF2FD9F4);
  static const logout = Color(0xFFFF8A8A);
}

/// The signed-in user's Settings screen, reached from the Profile
/// screen's gear icon. Takes the already-loaded [profile] and [authUser]
/// from the caller rather than re-fetching, since Profile just loaded
/// both.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.profile, required this.authUser});

  final UserProfile profile;
  final AuthUser authUser;

  String get _displayName {
    if (profile.displayName.isNotEmpty) return profile.displayName;
    final name = '${authUser.firstName} ${authUser.lastName}'.trim();
    return name.isEmpty ? authUser.email : name;
  }

  Future<void> _onEditProfile(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: profile, email: authUser.email),
      ),
    );
  }

  void _onConnectedAccounts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConnectedAccountsScreen(authUser: authUser)),
    );
  }

  void _onChangePassword(BuildContext context) {
    if (authUser.registrationMethod == 'google') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google accounts sign in through Google, not a Music Room password.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UpdatePasswordScreen()),
    );
  }

  void _onVerificationStatus(BuildContext context) {
    if (authUser.isEmailVerified) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailVerificationPendingScreen(email: authUser.email),
      ),
    );
  }

  Future<void> _onLogout(BuildContext context) async {
    final authApi = AuthApi();
    final tokenStorage = TokenStorage();

    await authApi.logout();
    await tokenStorage.clear();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SettingsColors.background,
      appBar: AppBar(
        backgroundColor: _SettingsColors.background,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w800,
            fontSize: 24,
            color: _SettingsColors.headline,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _SettingsColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _SettingsColors.border),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: ProfileAvatarImage(
                      avatar: profile.avatar,
                      avatarType: profile.avatarType,
                      fallback: const ColoredBox(
                        color: _SettingsColors.border,
                        child: Icon(Icons.person_rounded, color: _SettingsColors.muted, size: 30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: _SettingsColors.body,
                        ),
                      ),
                      
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _onEditProfile(context),
                  icon: const Icon(Icons.edit_rounded, color: _SettingsColors.headline, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SettingsRow(
            icon: Icons.account_circle_outlined,
            title: 'Connected Accounts',
            subtitle: authUser.registrationMethod == 'google' ? 'Google' : 'Email settings',
            onTap: () => _onConnectedAccounts(context),
          ),
          _SettingsRow(
            icon: Icons.key_rounded,
            title: 'Change Password',
            subtitle: 'Update security credentials',
            onTap: () => _onChangePassword(context),
          ),
          // _SettingsRow(
          //   icon: Icons.verified_rounded,
          //   title: 'Verification Status',
          //   subtitle: authUser.isEmailVerified ? 'Verified' : 'Not verified — tap to verify',
          //   subtitleColor: authUser.isEmailVerified ? _SettingsColors.verified : null,
          //   onTap: () => _onVerificationStatus(context),
          // ),
          // _SettingsRow(
          //   icon: Icons.tune_rounded,
          //   title: 'Backend Config',
          //   subtitle: ApiConfig.baseUrl,
          //   onTap: null,
          // ),
          const SizedBox(height: 32),
          Center(
            child: TextButton.icon(
              onPressed: () => _onLogout(context),
              icon: const Icon(Icons.logout_rounded, color: _SettingsColors.logout, size: 18),
              label: const Text(
                'Logout',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  color: _SettingsColors.logout,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _SettingsColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _SettingsColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _SettingsColors.background,
                child: Icon(icon, color: _SettingsColors.headline, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _SettingsColors.body,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor ?? _SettingsColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: _SettingsColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
