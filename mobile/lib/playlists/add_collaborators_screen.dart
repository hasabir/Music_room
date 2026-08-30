import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../profile/profile_api.dart';
import '../profile/profile_models.dart';
import 'playlist_api.dart';

class _AddCollaboratorsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// Search-and-invite screen for a playlist's collaborators. Mirrors
/// `add_friends_screen.dart`'s debounced-search pattern (same
/// `GET /api/v1/profile/search/` endpoint via [ProfileApi.searchUsers],
/// which already excludes the signed-in user server-side) but invites
/// directly via `POST .../collaborators/` — there's no request/accept
/// step for collaborators the way there is for friends.
class AddCollaboratorsScreen extends StatefulWidget {
  const AddCollaboratorsScreen({
    super.key,
    required this.playlistId,
    required this.existingCollaboratorIds,
  });

  final int playlistId;

  /// User ids already invited, so results can show "Collaborator" instead
  /// of an actionable "Add" button.
  final Set<int> existingCollaboratorIds;

  @override
  State<AddCollaboratorsScreen> createState() => _AddCollaboratorsScreenState();
}

class _AddCollaboratorsScreenState extends State<AddCollaboratorsScreen> {
  final _profileApi = ProfileApi();
  final _playlistApi = PlaylistApi();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<SearchUser>? _results;
  var _isLoading = false;
  String? _error;
  late Set<int> _invitedIds;

  @override
  void initState() {
    super.initState();
    _invitedIds = {...widget.existingCollaboratorIds};
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await _profileApi.searchUsers(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _onInvite(SearchUser user) async {
    try {
      await _playlistApi.inviteCollaborator(widget.playlistId, user.id);
      if (!mounted) return;
      setState(() => _invitedIds = {..._invitedIds, user.id});
      _showSnack('${user.fullName} can now edit this playlist.');
    } on ApiException catch (error) {
      _showSnack(error.message);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AddCollaboratorsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _AddCollaboratorsColors.body),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onQueryChanged,
                      style: const TextStyle(color: _AddCollaboratorsColors.body),
                      decoration: InputDecoration(
                        hintText: 'Search for people to invite...',
                        hintStyle: const TextStyle(color: _AddCollaboratorsColors.muted),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: _AddCollaboratorsColors.tertiary,
                        ),
                        filled: true,
                        fillColor: _AddCollaboratorsColors.card,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _AddCollaboratorsColors.headline));
    }

    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: _AddCollaboratorsColors.muted)),
      );
    }

    final results = _results;
    if (results == null) {
      return const Center(
        child: Text(
          'Search by name or email to find people.',
          style: TextStyle(color: _AddCollaboratorsColors.muted),
        ),
      );
    }

    if (results.isEmpty) {
      return const Center(
        child: Text('No users found.', style: TextStyle(color: _AddCollaboratorsColors.muted)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = results[index];
        return _SearchResultRow(
          user: user,
          isInvited: _invitedIds.contains(user.id),
          onInvite: () => _onInvite(user),
        );
      },
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.user, required this.isInvited, required this.onInvite});

  final SearchUser user;
  final bool isInvited;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AddCollaboratorsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AddCollaboratorsColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _AddCollaboratorsColors.border,
            child: Text(
              user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?',
              style: const TextStyle(color: _AddCollaboratorsColors.headline, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              user.fullName,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _AddCollaboratorsColors.body,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (isInvited)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: _AddCollaboratorsColors.muted),
                SizedBox(width: 4),
                Text(
                  'COLLABORATOR',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: _AddCollaboratorsColors.muted,
                  ),
                ),
              ],
            )
          else
            _GradientPillButton(label: 'Add', onTap: onInvite),
        ],
      ),
    );
  }
}

class _GradientPillButton extends StatelessWidget {
  const _GradientPillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [_AddCollaboratorsColors.gradientStart, _AddCollaboratorsColors.gradientEnd],
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }
}
