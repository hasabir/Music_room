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
  static const chip = Color(0xFF232230);
  static const badgePublic = Color(0xFF2FD9F4);
  static const badgeFriends = Color(0xFFE05FA8);
  static const badgePrivate = Color(0xFF908FA0);
}

/// The signed-in user's own Profile screen.
///
/// Loads the real profile (`GET /api/v1/profile/me/`, which includes
/// `votes_count`/`playlists_count`) and friends list
/// (`GET /api/v1/profile/friends/`) from the backend. Handle, birthday,
/// per-field privacy badges, instruments/gear, and events hosted are
/// local placeholder data — see `profile_mock_data.dart` for why, and to
/// swap them for real data later.
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

  Future<void> _onFriends() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
    // Friend requests may have been accepted/declined/removed on that
    // screen, which would leave the friends count shown here stale.
    _refresh();
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
                        ),
                        const SizedBox(height: 16),
                        _FriendsCard(count: data.friends.length, onTap: _onFriends),
                        const SizedBox(height: 16),
                        _StatsRow(
                          votes: data.profile.votesCount,
                          playlists: data.profile.playlistsCount,
                        ),
                        const SizedBox(height: 24),
                        const _DetailsLabel(),
                        const SizedBox(height: 10),
                        _DetailsCard(profile: data.profile, email: data.authUser.email),
                        const SizedBox(height: 16),
                        _VibeSignatureCard(
                          genres: data.profile.favoriteGenres,
                          onEdit: () => _onMusicPreferences(data.profile),
                        ),
                        const SizedBox(height: 24),
                        const _ProfileContentTabs(),
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
      votesCount: 0,
      playlistsCount: 0,
      fieldVisibility: defaultFieldVisibility,
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
  const _ProfileCard({required this.profile, required this.authUser, required this.onEditProfile});

  final UserProfile profile;
  final AuthUser authUser;
  final VoidCallback onEditProfile;

  String get _displayName {
    if (profile.displayName.isNotEmpty) return profile.displayName;
    final name = '${authUser.firstName} ${authUser.lastName}'.trim();
    return name.isEmpty ? authUser.email : name;
  }

  /// A `@handle`-style label derived from the display name, purely for
  /// visual presentation — `Profile` has no username/handle field.
  String? get _handle {
    final slug = _displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return slug.isEmpty ? null : '@$slug';
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;

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
          if (handle != null) ...[
            const SizedBox(height: 2),
            Text(
              handle,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ProfileColors.tertiary,
              ),
            ),
          ],
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
            child: OutlinedButton.icon(
              onPressed: onEditProfile,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ProfileColors.tertiary,
                side: const BorderSide(color: _ProfileColors.tertiary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text(
                'Edit Profile',
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

class _FriendsCard extends StatelessWidget {
  const _FriendsCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: _Card(
        child: Row(
          children: [
            const Icon(Icons.groups_rounded, size: 20, color: _ProfileColors.headline),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Friends',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ProfileColors.body,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _ProfileColors.chip, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _ProfileColors.body,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: _ProfileColors.muted),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.votes, required this.playlists});

  final int votes;
  final int playlists;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatTile(value: '$votes', label: 'VOTES')),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(value: '$playlists', label: 'PLAYLISTS')),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 24,
              color: _ProfileColors.headline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _ProfileColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsLabel extends StatelessWidget {
  const _DetailsLabel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 4),
      child: Text(
        'DETAILS',
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: _ProfileColors.muted,
        ),
      ),
    );
  }
}

enum _Privacy { public, friends, private }

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.profile, required this.email});

  final UserProfile profile;
  final String email;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.location_on_rounded,
            label: 'Location',
            value: profile.location.isNotEmpty ? profile.location : 'Not set',
            privacy: _Privacy.public,
          ),
          const _DetailDivider(),
          _DetailRow(
            icon: Icons.cake_rounded,
            label: 'Birthday',
            value: mockBirthday ?? 'Not set',
            privacy: _Privacy.friends,
          ),
          const _DetailDivider(),
          _DetailRow(
            icon: Icons.mail_rounded,
            label: 'Email',
            value: email.isNotEmpty ? email : 'Not set',
            privacy: _Privacy.private,
          ),
        ],
      ),
    );
  }
}

class _DetailDivider extends StatelessWidget {
  const _DetailDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: _ProfileColors.cardBorder),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.privacy,
  });

  final IconData icon;
  final String label;
  final String value;
  final _Privacy privacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _ProfileColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: _ProfileColors.body,
                ),
              ),
            ),
            _PrivacyBadge(privacy: privacy),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(value, style: const TextStyle(fontSize: 14, color: _ProfileColors.description)),
        ),
      ],
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge({required this.privacy});

  final _Privacy privacy;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (privacy) {
      _Privacy.public => ('Public', Icons.public_rounded, _ProfileColors.badgePublic),
      _Privacy.friends => ('Friends', Icons.people_alt_rounded, _ProfileColors.badgeFriends),
      _Privacy.private => ('Private', Icons.lock_rounded, _ProfileColors.badgePrivate),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _VibeSignatureCard extends StatelessWidget {
  const _VibeSignatureCard({required this.genres, required this.onEdit});

  final List<String> genres;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vibe Signature',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: _ProfileColors.body,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Aesthetic & tonal preferences',
                      style: TextStyle(fontSize: 12, color: _ProfileColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_rounded, size: 18, color: _ProfileColors.headline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _ChipsLabel('TOP GENRES'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...genres.map((code) => _Chip(label: musicGenreLabels[code] ?? code)),
              _Chip(label: '+ Add', outlined: true, onTap: onEdit),
            ],
          ),
          const SizedBox(height: 18),
          const _ChipsLabel('INSTRUMENTS / GEAR'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: mockInstruments.map((label) => _Chip(label: label)).toList(),
          ),
        ],
      ),
    );
  }
}

class _ChipsLabel extends StatelessWidget {
  const _ChipsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _ProfileColors.muted,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.outlined = false, this.onTap});

  final String label;
  final bool outlined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : _ProfileColors.chip,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlined ? _ProfileColors.tertiary : _ProfileColors.cardBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: outlined ? _ProfileColors.tertiary : _ProfileColors.body,
        ),
      ),
    );

    if (onTap == null) return chip;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: chip);
  }
}

enum _ProfileContentTab { playlists, eventsHosted }

class _ProfileContentTabs extends StatefulWidget {
  const _ProfileContentTabs();

  @override
  State<_ProfileContentTabs> createState() => _ProfileContentTabsState();
}

class _ProfileContentTabsState extends State<_ProfileContentTabs> {
  var _tab = _ProfileContentTab.playlists;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _TabButton(
              label: 'Playlists',
              isSelected: _tab == _ProfileContentTab.playlists,
              onTap: () => setState(() => _tab = _ProfileContentTab.playlists),
            ),
            const SizedBox(width: 20),
            _TabButton(
              label: 'Events Hosted',
              isSelected: _tab == _ProfileContentTab.eventsHosted,
              onTap: () => setState(() => _tab = _ProfileContentTab.eventsHosted),
            ),
            const Spacer(),
            const Icon(Icons.sort_rounded, color: _ProfileColors.muted),
          ],
        ),
        const SizedBox(height: 16),
        if (_tab == _ProfileContentTab.playlists)
          ...mockPlaylists.map(
            (playlist) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlaylistCard(playlist: playlist),
            ),
          )
        else
          ...mockHostedEvents.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HostedEventCard(event: event),
            ),
          ),
        const SizedBox(height: 4),
        _CreatePlaylistButton(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating playlists is coming soon.')),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: isSelected ? _ProfileColors.body : _ProfileColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 20,
            color: isSelected ? _ProfileColors.tertiary : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final MockPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [_ProfileColors.gradientStart, _ProfileColors.tertiary],
              ),
            ),
            child: const Icon(Icons.queue_music_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _ProfileColors.body,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  playlist.subtitle,
                  style: const TextStyle(fontSize: 12, color: _ProfileColors.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _ProfileColors.chip, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${playlist.trackCount} Tracks',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _ProfileColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostedEventCard extends StatelessWidget {
  const _HostedEventCard({required this.event});

  final MockHostedEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: _ProfileColors.chip, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.podcasts_rounded, color: _ProfileColors.headline),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _ProfileColors.body,
                  ),
                ),
                const SizedBox(height: 2),
                Text(event.subtitle, style: const TextStyle(fontSize: 12, color: _ProfileColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePlaylistButton extends StatelessWidget {
  const _CreatePlaylistButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _ProfileColors.cardBorder),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: _ProfileColors.muted),
            SizedBox(height: 6),
            Text(
              'Create New Playlist',
              style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600, color: _ProfileColors.muted),
            ),
          ],
        ),
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
