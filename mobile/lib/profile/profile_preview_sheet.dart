import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'profile_api.dart';
import 'profile_avatar.dart';
import 'profile_models.dart';
import 'view_profile_screen.dart';

class _PreviewColors {
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const description = Color(0xFFC7C4D7);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
}

/// Opens a bottom-sheet preview of [userId]'s profile — photo, name,
/// username, bio, and a friend-request action — for anywhere a person's
/// avatar shows up outside the dedicated search/friends flows (currently:
/// an event's participants list — see `_ParticipantRow` in
/// `track_vote/event_detail_screen.dart`).
///
/// [initialName]/[initialUsername]/[initialAvatar]/[initialAvatarType]
/// render immediately from whatever the caller already has on hand (e.g.
/// an `EventGuest`/`EventMembership` row) so the sheet never opens empty;
/// bio and relationship status always come from a fresh
/// `GET /profile/profile/<user_id>/` fetch instead, since neither is
/// safe to infer from stale list data — bio is visibility-gated, and a
/// friend request could have been sent/accepted since the list last
/// loaded.
///
/// [currentUserId] is the signed-in user's own id — pass it whenever the
/// caller has it on hand. If it matches [userId] (the row being tapped is
/// the signed-in user themselves — e.g. their own row in an event's
/// participant list), this is a deliberate no-op: there's nothing
/// meaningful to preview or friend-request about yourself, so no sheet
/// opens at all.
///
/// Returns the same future `showModalBottomSheet` would — callers that
/// need to refresh their own list after a friend-request action taken
/// inside the sheet (e.g. a search results list) can `await` it, same as
/// they would `Navigator.push`ing a full screen. Resolves immediately
/// (already-completed future) for the self no-op case.
Future<void> showProfilePreview(
  BuildContext context, {
  required int userId,
  required int? currentUserId,
  required String initialName,
  String? initialUsername,
  String? initialAvatar,
  String? initialAvatarType,
}) {
  if (currentUserId != null && currentUserId == userId) return Future.value();

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: _PreviewColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ProfilePreviewSheet(
      userId: userId,
      initialName: initialName,
      initialUsername: initialUsername,
      initialAvatar: initialAvatar,
      initialAvatarType: initialAvatarType,
    ),
  );
}

class ProfilePreviewSheet extends StatefulWidget {
  const ProfilePreviewSheet({
    super.key,
    required this.userId,
    required this.initialName,
    this.initialUsername,
    this.initialAvatar,
    this.initialAvatarType,
  });

  final int userId;
  final String initialName;
  final String? initialUsername;
  final String? initialAvatar;
  final String? initialAvatarType;

  @override
  State<ProfilePreviewSheet> createState() => _ProfilePreviewSheetState();
}

class _ProfilePreviewSheetState extends State<ProfilePreviewSheet> {
  final _profileApi = ProfileApi();
  late final Future<OtherUserProfile> _profileFuture;

  /// Seeded from the fetched profile's own `relationship_status`/
  /// `friendship_id` (there's no earlier source — unlike
  /// [ViewProfileScreen], whose caller already knows this from a search
  /// result). `null` until that first fetch resolves; mutated locally
  /// afterward by the actions below, same as [ViewProfileScreen].
  RelationshipStatus? _relationshipStatus;
  int? _friendshipId;
  var _isActing = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<OtherUserProfile> _loadProfile() async {
    final profile = await _profileApi.getUserProfile(widget.userId);
    if (mounted) {
      setState(() {
        _relationshipStatus = profile.relationshipStatus;
        _friendshipId = profile.friendshipId;
      });
    }
    return profile;
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

  /// Captures the Navigator before popping this sheet, then pushes on
  /// that same captured reference — safe regardless of what popping does
  /// to this widget's own `context` afterward.
  void _openFullProfile(String displayName) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ViewProfileScreen(
          userId: widget.userId,
          initialFullName: displayName,
          relationshipStatus: _relationshipStatus ?? RelationshipStatus.none,
          friendshipId: _friendshipId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FutureBuilder<OtherUserProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final name = (profile?.displayName.isNotEmpty ?? false)
                ? profile!.displayName
                : widget.initialName;
            final username = (profile?.username.isNotEmpty ?? false)
                ? profile!.username
                : (widget.initialUsername ?? '');
            final avatar = profile?.avatar ?? widget.initialAvatar;
            final avatarType =
                profile?.avatarType ?? widget.initialAvatarType ?? profileAvatarTypePreset;
            final isLoading = snapshot.connectionState == ConnectionState.waiting;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_PreviewColors.tertiary, _PreviewColors.headline],
                    ),
                  ),
                  child: ClipOval(
                    child: ProfileAvatarImage(
                      avatar: avatar,
                      avatarType: avatarType,
                      fallback: const ColoredBox(
                        color: _PreviewColors.border,
                        child: Icon(
                          Icons.person_rounded,
                          color: _PreviewColors.muted,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  name.isEmpty ? 'Unknown' : name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: _PreviewColors.body,
                  ),
                ),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: const TextStyle(fontSize: 13, color: _PreviewColors.muted),
                  ),
                ],
                const SizedBox(height: 16),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _PreviewColors.tertiary,
                      ),
                    ),
                  )
                else if (snapshot.hasError)
                  const Text(
                    'Could not load this profile.',
                    style: TextStyle(color: _PreviewColors.muted),
                  )
                else ...[
                  if (_relationshipStatus != null)
                    RelationshipActionRow(
                      status: _relationshipStatus!,
                      isActing: _isActing,
                      onAdd: _onAdd,
                      onRemove: _onRemove,
                      onCancel: _onCancel,
                      onAccept: _onAccept,
                      onDecline: _onDecline,
                    ),
                  if ((profile?.bio ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      profile!.bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: _PreviewColors.description,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openFullProfile(name),
                    icon: const Icon(Icons.person_rounded, size: 18),
                    label: const Text('View Full Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _PreviewColors.tertiary,
                      side: const BorderSide(color: _PreviewColors.tertiary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
