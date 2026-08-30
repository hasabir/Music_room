import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'profile_api.dart';
import 'profile_models.dart';

class _ViewProfileColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const description = Color(0xFFC7C4D7);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const destructive = Color(0xFFE0555F);
  static const chip = Color(0xFF232230);
}

/// Read-only view of another user's profile, backed by
/// `GET /api/v1/profile/profile/<user_id>/` (filtered by visibility rules
/// server-side) plus the friend-request actions already used elsewhere.
///
/// Votes and Playlists counts both come straight from the backend
/// (`votes_count`/`playlists_count` on the profile response — both are
/// always returned regardless of the visibility filtering applied to the
/// rest of the profile, per `UserProfileView` on the backend). "Listening
/// Now" and a "Recent Activity" feed from the original design are
/// deliberately not shown: there's no backend concept of either, and
/// faking them would assert real-time behavior about a specific person
/// rather than read as generic UI chrome.
class ViewProfileScreen extends StatefulWidget {
  const ViewProfileScreen({
    super.key,
    required this.userId,
    required this.initialFullName,
    required this.relationshipStatus,
    this.friendshipId,
  });

  final int userId;
  final String initialFullName;
  final RelationshipStatus relationshipStatus;
  final int? friendshipId;

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  final _profileApi = ProfileApi();

  late Future<OtherUserProfile> _profileFuture;
  late RelationshipStatus _relationshipStatus;
  int? _friendshipId;
  var _isActing = false;

  @override
  void initState() {
    super.initState();
    _relationshipStatus = widget.relationshipStatus;
    _friendshipId = widget.friendshipId;
    _profileFuture = _profileApi.getUserProfile(widget.userId);
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isActing = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _onAdd() => _runAction(() async {
    await _profileApi.sendFriendRequest(widget.userId);
    setState(() => _relationshipStatus = RelationshipStatus.pendingSent);
  });

  Future<void> _onCancel() => _runAction(() async {
    await _profileApi.cancelFriendRequest(widget.userId);
    setState(() => _relationshipStatus = RelationshipStatus.none);
  });

  Future<void> _onRemove() => _runAction(() async {
    await _profileApi.removeFriend(widget.userId);
    setState(() => _relationshipStatus = RelationshipStatus.none);
  });

  Future<void> _onAccept() => _runAction(() async {
    final friendshipId = _friendshipId;
    if (friendshipId == null) return;
    await _profileApi.acceptFriendRequest(friendshipId);
    setState(() => _relationshipStatus = RelationshipStatus.friends);
  });

  Future<void> _onDecline() => _runAction(() async {
    final friendshipId = _friendshipId;
    if (friendshipId == null) return;
    await _profileApi.rejectFriendRequest(friendshipId);
    setState(() => _relationshipStatus = RelationshipStatus.none);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ViewProfileColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: 'View Profile'),
            Expanded(
              child: FutureBuilder<OtherUserProfile>(
                future: _profileFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _ViewProfileColors.headline),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Text(
                        'Could not load this profile.',
                        style: const TextStyle(color: _ViewProfileColors.muted),
                      ),
                    );
                  }

                  final profile = snapshot.data!;
                  final name = profile.displayName.isNotEmpty
                      ? profile.displayName
                      : widget.initialFullName;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _ProfileCard(
                        name: name,
                        profileImageUrl: profile.profileImageUrl,
                        bio: profile.bio,
                        birthday: profile.birthday,
                        genres: profile.favoriteGenres,
                        relationshipStatus: _relationshipStatus,
                        isActing: _isActing,
                        onAdd: _onAdd,
                        onRemove: _onRemove,
                        onCancel: _onCancel,
                        onAccept: _onAccept,
                        onDecline: _onDecline,
                      ),
                      const SizedBox(height: 16),
                      _StatsRow(votes: profile.votesCount, playlists: profile.playlistsCount),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _ViewProfileColors.body),
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _ViewProfileColors.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.profileImageUrl,
    required this.bio,
    required this.birthday,
    required this.genres,
    required this.relationshipStatus,
    required this.isActing,
    required this.onAdd,
    required this.onRemove,
    required this.onCancel,
    required this.onAccept,
    required this.onDecline,
  });

  final String name;
  final String? profileImageUrl;
  final String bio;
  final DateTime? birthday;
  final List<String> genres;
  final RelationshipStatus relationshipStatus;
  final bool isActing;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _ViewProfileColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _ViewProfileColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_ViewProfileColors.tertiary, _ViewProfileColors.headline]),
            ),
            child: ClipOval(
              child: profileImageUrl != null
                  ? Image.network(
                      profileImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _AvatarFallback(),
                    )
                  : const _AvatarFallback(),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 26,
              color: _ViewProfileColors.body,
            ),
          ),
          const SizedBox(height: 14),
          _RelationshipAction(
            status: relationshipStatus,
            isActing: isActing,
            onAdd: onAdd,
            onRemove: onRemove,
            onCancel: onCancel,
            onAccept: onAccept,
            onDecline: onDecline,
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              bio,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 14,
                height: 1.4,
                color: _ViewProfileColors.description,
              ),
            ),
          ],
          if (birthday != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cake_outlined, size: 14, color: _ViewProfileColors.muted),
                const SizedBox(width: 6),
                Text(
                  formatBirthday(birthday!),
                  style: const TextStyle(fontSize: 13, color: _ViewProfileColors.muted),
                ),
              ],
            ),
          ],
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: genres.map((code) => _Chip(label: musicGenreLabels[code] ?? code)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _RelationshipAction extends StatelessWidget {
  const _RelationshipAction({
    required this.status,
    required this.isActing,
    required this.onAdd,
    required this.onRemove,
    required this.onCancel,
    required this.onAccept,
    required this.onDecline,
  });

  final RelationshipStatus status;
  final bool isActing;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      RelationshipStatus.none => _OutlinedActionButton(
        label: 'Add Friend',
        icon: Icons.person_add_alt_1_rounded,
        color: _ViewProfileColors.tertiary,
        onTap: isActing ? null : onAdd,
      ),
      RelationshipStatus.friends => _OutlinedActionButton(
        label: 'Remove friend',
        icon: Icons.person_remove_rounded,
        color: _ViewProfileColors.destructive,
        onTap: isActing ? null : onRemove,
      ),
      RelationshipStatus.pendingSent => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OutlinedActionButton(
            label: 'Requested',
            icon: Icons.person_add_alt_1_rounded,
            color: _ViewProfileColors.tertiary,
            onTap: null,
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: isActing ? null : onCancel,
            child: const Text(
              'Cancel',
              style: TextStyle(color: _ViewProfileColors.destructive),
            ),
          ),
        ],
      ),
      RelationshipStatus.pendingReceived => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: isActing ? null : onDecline,
            child: const Text('Decline', style: TextStyle(color: _ViewProfileColors.muted)),
          ),
          const SizedBox(width: 8),
          _OutlinedActionButton(
            label: 'Accept',
            icon: Icons.check_rounded,
            color: _ViewProfileColors.tertiary,
            onTap: isActing ? null : onAccept,
          ),
        ],
      ),
    };
  }
}

class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: color,
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700)),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _ViewProfileColors.chip,
      child: Icon(Icons.person_rounded, color: _ViewProfileColors.muted, size: 44),
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
        color: _ViewProfileColors.chip,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ViewProfileColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _ViewProfileColors.body,
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
        color: _ViewProfileColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ViewProfileColors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 24,
              color: _ViewProfileColors.headline,
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
              color: _ViewProfileColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
