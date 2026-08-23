import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';
import '../settings/settings_screen.dart';
import 'connections_screen.dart';
import 'edit_profile_screen.dart';
import 'music_preferences_screen.dart';
import 'profile_api.dart';
import 'profile_mock_data.dart';
import 'profile_models.dart';

class _ProfileColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const cardBorder = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const description = Color(0xFFC7C4D7);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
  static const chip = Color(0xFF232230);
  static const online = Color(0xFF3DDC97);
  static const liveBadge = Color(0xFF6C6FF0);
}

/// The signed-in user's own Profile screen.
///
/// Loads the real profile (`GET /api/v1/profile/me/`) and friends list
/// (`GET /api/v1/profile/friends/`) from the backend. "friends" presence and
/// "Active Sessions" are local placeholder data — see
/// `profile_mock_data.dart` for why, and to swap them for real data later.
class PersonalProfileScreen extends StatefulWidget {
  const PersonalProfileScreen({super.key});

  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  final _profileApi = ProfileApi();
  final _authApi = AuthApi();
  final _tokenStorage = TokenStorage();

  Future<_ProfileData>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_ProfileData> _load() async {
    try {
      final results = await Future.wait([
        _profileApi.getMyProfile(),
        _profileApi.getFriends(),
        _authApi.getCurrentUser(),
      ]);
      return _ProfileData(
        profile: results[0] as UserProfile,
        friends: results[1] as List<Friend>,
        authUser: results[2] as AuthUser,
      );
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _dataFuture = future;
    });
    await future.catchError((_) => _ProfileData.empty());
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _onEditProfile(UserProfile profile, String email) async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile, email: email)),
    );
    _applyUpdatedProfile(updated);
  }

  Future<void> _onMusicPreferences(UserProfile profile) async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(builder: (_) => MusicPreferencesScreen(profile: profile)),
    );
    _applyUpdatedProfile(updated);
  }

  void _applyUpdatedProfile(UserProfile? updated) {
    if (updated == null) return;
    final merged = Future.value(_currentData!.copyWith(profile: updated));
    setState(() {
      _dataFuture = merged;
    });
  }

  void _onConnections() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
  }

  void _onSettings() {
    final data = _currentData;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still loading your profile — try again in a moment.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(profile: data.profile, authUser: data.authUser),
      ),
    );
  }

  _ProfileData? _currentData;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onSettingsTap: _onSettings),
            Expanded(
              child: FutureBuilder<_ProfileData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _ProfileColors.headline),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Could not load your profile.';
                    return _ErrorState(message: message, onRetry: _refresh);
                  }

                  _currentData = snapshot.data;
                  final data = snapshot.data!;

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: _ProfileColors.headline,
                    backgroundColor: _ProfileColors.card,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _ProfileCard(
                          profile: data.profile,
                          authUser: data.authUser,
                          onEditProfile: () => _onEditProfile(data.profile, data.authUser.email),
                          onConnections: _onConnections,
                        ),
                        const SizedBox(height: 16),
                        _SonicSignatureCard(
                          genres: data.profile.favoriteGenres,
                          onEdit: () => _onMusicPreferences(data.profile),
                        ),
                        const SizedBox(height: 16),
                        _friendsCard(friends: data.friends),
                        const SizedBox(height: 24),
                        const _SectionHeader(icon: Icons.podcasts_rounded, title: 'Active Sessions'),
                        const SizedBox(height: 12),
                        const _LiveSessionCard(),
                        const SizedBox(height: 12),
                        const _UpcomingSessionCard(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.profile,
        onTabSelected: (tab) => navigateToTab(context, AppTab.profile, tab),
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({required this.profile, required this.friends, required this.authUser});

  factory _ProfileData.empty() => _ProfileData(
    profile: const UserProfile(
      id: 0,
      displayName: '',
      bio: '',
      location: '',
      favoriteArtist: '',
      phoneNumber: '',
      profileImageUrl: null,
      favoriteGenres: [],
    ),
    friends: const [],
    authUser: const AuthUser(
      id: 0,
      email: '',
      firstName: '',
      lastName: '',
      isEmailVerified: false,
      registrationMethod: 'email',
      hasGoogleLinked: false,
    ),
  );

  final UserProfile profile;
  final List<Friend> friends;
  final AuthUser authUser;

  _ProfileData copyWith({UserProfile? profile}) =>
      _ProfileData(profile: profile ?? this.profile, friends: friends, authUser: authUser);
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettingsTap});

  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [_ProfileColors.gradientStart, _ProfileColors.tertiary],
              ),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            'Music Room',
            style: TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: _ProfileColors.headline,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettingsTap,
            icon: const Icon(Icons.settings_rounded, color: _ProfileColors.body),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: _ProfileColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ProfileColors.body),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => onRetry(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ProfileColors.tertiary,
                side: const BorderSide(color: _ProfileColors.tertiary),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.authUser,
    required this.onEditProfile,
    required this.onConnections,
  });

  final UserProfile profile;
  final AuthUser authUser;
  final VoidCallback onEditProfile;
  final VoidCallback onConnections;

  String get _displayName {
    if (profile.displayName.isNotEmpty) return profile.displayName;
    final name = '${authUser.firstName} ${authUser.lastName}'.trim();
    return name.isEmpty ? authUser.email : name;
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [_ProfileColors.tertiary, _ProfileColors.gradientStart],
              ),
            ),
            child: ClipOval(
              child: profile.profileImageUrl != null
                  ? Image.network(
                      profile.profileImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _AvatarFallback(),
                    )
                  : const _AvatarFallback(),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 28,
              color: _ProfileColors.body,
            ),
          ),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              profile.bio,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 14,
                height: 1.4,
                color: _ProfileColors.description,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [_ProfileColors.gradientStart, _ProfileColors.gradientEnd],
                ),
              ),
              child: ElevatedButton.icon(
                onPressed: onEditProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onConnections,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ProfileColors.tertiary,
                side: const BorderSide(color: _ProfileColors.tertiary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text(
                'Connections',
                style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _ProfileColors.chip,
      child: Icon(Icons.person_rounded, color: _ProfileColors.muted, size: 44),
    );
  }
}

class _SonicSignatureCard extends StatelessWidget {
  const _SonicSignatureCard({required this.genres, required this.onEdit});

  final List<String> genres;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionHeader(icon: Icons.bar_chart_rounded, title: 'Sonic Signature'),
              ),
              IconButton(
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_rounded, size: 18, color: _ProfileColors.headline),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (genres.isEmpty)
            const Text(
              'Add your favorite genres in Music Preferences.',
              style: TextStyle(color: _ProfileColors.muted, fontSize: 13),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: genres
                  .map((code) => _Chip(label: musicGenreLabels[code] ?? code))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _ProfileColors.chip,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _ProfileColors.body,
        ),
      ),
    );
  }
}

class _friendsCard extends StatelessWidget {
  const _friendsCard({required this.friends});

  final List<Friend> friends;

  @override
  Widget build(BuildContext context) {
    final onlineCount = friends
        .where((friend) => MockPresence.forFriendId(friend.id).isOnline)
        .length;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionHeader(icon: Icons.groups_rounded, title: 'friends'),
              ),
              Text(
                '$onlineCount ONLINE',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _ProfileColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (friends.isEmpty)
            const Text(
              'No friends yet — add friends to see them here.',
              style: TextStyle(color: _ProfileColors.muted, fontSize: 13),
            )
          else
            Column(
              children: friends
                  .take(4)
                  .map(
                    (friend) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _friendsRow(friend: friend),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _friendsRow extends StatelessWidget {
  const _friendsRow({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final presence = MockPresence.forFriendId(friend.id);

    return Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _ProfileColors.chip,
              child: Text(
                friend.firstName.isNotEmpty ? friend.firstName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: _ProfileColors.headline,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (presence.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _ProfileColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: _ProfileColors.card, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                friend.fullName,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: _ProfileColors.body,
                ),
              ),
              Text(
                presence.activity,
                style: const TextStyle(fontSize: 12, color: _ProfileColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _ProfileColors.headline),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: _ProfileColors.body,
          ),
        ),
      ],
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ProfileColors.gradientStart.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _ProfileColors.liveBadge,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.more_horiz_rounded, color: _ProfileColors.muted),
            ],
          ),
          const SizedBox(height: 68),
          Text(
            mockActiveSession.title,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: _ProfileColors.body,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 14, color: _ProfileColors.muted),
              const SizedBox(width: 4),
              Text(
                mockActiveSession.subtitle,
                style: const TextStyle(fontSize: 13, color: _ProfileColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingSessionCard extends StatelessWidget {
  const _UpcomingSessionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _ProfileColors.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.queue_music_rounded, size: 14, color: _ProfileColors.muted),
                SizedBox(width: 4),
                Text(
                  'UP NEXT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _ProfileColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text(
            mockUpcomingSession.title,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: _ProfileColors.body,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 14, color: _ProfileColors.muted),
              const SizedBox(width: 4),
              Text(
                mockUpcomingSession.subtitle,
                style: const TextStyle(fontSize: 13, color: _ProfileColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: child,
    );
  }
}
