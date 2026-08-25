import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'profile_api.dart';
import 'profile_models.dart';
import 'view_profile_screen.dart';

class _AddFriendsColors {
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

/// Search-and-add screen backed by `GET /api/v1/profile/search/`. Lets the
/// signed-in user find people by name/email and send, accept, or see the
/// status of a friend request without leaving the results list.
class AddFriendsScreen extends StatefulWidget {
  const AddFriendsScreen({super.key});

  @override
  State<AddFriendsScreen> createState() => _AddFriendsScreenState();
}

class _AddFriendsScreenState extends State<AddFriendsScreen> {
  final _profileApi = ProfileApi();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<SearchUser>? _results;
  var _isLoading = false;
  String? _error;

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

  void _updateResult(int userId, SearchUser Function(SearchUser) update) {
    final results = _results;
    if (results == null) return;
    setState(() {
      _results = [
        for (final user in results)
          if (user.id == userId) update(user) else user,
      ];
    });
  }

  Future<void> _onAdd(SearchUser user) async {
    try {
      await _profileApi.sendFriendRequest(user.id);
      _updateResult(user.id, (u) => u.copyWith(relationshipStatus: RelationshipStatus.pendingSent));
      _showSnack('Friend request sent');
    } on ApiException catch (error) {
      _showSnack(error.message);
    }
  }

  Future<void> _onAccept(SearchUser user) async {
    final friendshipId = user.friendshipId;
    if (friendshipId == null) return;
    try {
      await _profileApi.acceptFriendRequest(friendshipId);
      _updateResult(user.id, (u) => u.copyWith(relationshipStatus: RelationshipStatus.friends));
    } on ApiException catch (error) {
      _showSnack(error.message);
    }
  }

  Future<void> _onDecline(SearchUser user) async {
    final friendshipId = user.friendshipId;
    if (friendshipId == null) return;
    try {
      await _profileApi.rejectFriendRequest(friendshipId);
      _updateResult(user.id, (u) => u.copyWith(relationshipStatus: RelationshipStatus.none));
    } on ApiException catch (error) {
      _showSnack(error.message);
    }
  }

  Future<void> _onViewProfile(SearchUser user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewProfileScreen(
          userId: user.id,
          initialFullName: user.fullName,
          relationshipStatus: user.relationshipStatus,
          friendshipId: user.friendshipId,
        ),
      ),
    );
    final query = _controller.text;
    if (query.trim().isNotEmpty) _search(query);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AddFriendsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _AddFriendsColors.body),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onQueryChanged,
                      style: const TextStyle(color: _AddFriendsColors.body),
                      decoration: InputDecoration(
                        hintText: 'Search for users...',
                        hintStyle: const TextStyle(color: _AddFriendsColors.muted),
                        prefixIcon: const Icon(Icons.search_rounded, color: _AddFriendsColors.tertiary),
                        filled: true,
                        fillColor: _AddFriendsColors.card,
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
      return const Center(child: CircularProgressIndicator(color: _AddFriendsColors.headline));
    }

    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: _AddFriendsColors.muted)),
      );
    }

    final results = _results;
    if (results == null) {
      return const Center(
        child: Text('Search by name or email to find people.', style: TextStyle(color: _AddFriendsColors.muted)),
      );
    }

    if (results.isEmpty) {
      return const Center(child: Text('No users found.', style: TextStyle(color: _AddFriendsColors.muted)));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = results[index];
        return _SearchResultRow(
          user: user,
          onAdd: () => _onAdd(user),
          onAccept: () => _onAccept(user),
          onDecline: () => _onDecline(user),
          onTap: () => _onViewProfile(user),
        );
      },
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.user,
    required this.onAdd,
    required this.onAccept,
    required this.onDecline,
    required this.onTap,
  });

  final SearchUser user;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AddFriendsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AddFriendsColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _AddFriendsColors.border,
                    child: Text(
                      user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: _AddFriendsColors.headline,
                        fontWeight: FontWeight.w700,
                      ),
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
                        color: _AddFriendsColors.body,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _trailing(),
        ],
      ),
    );
  }

  Widget _trailing() {
    return switch (user.relationshipStatus) {
      RelationshipStatus.none => _GradientPillButton(label: 'Add', onTap: onAdd),
      RelationshipStatus.pendingSent => const _OutlinedPill(label: 'Requested'),
      RelationshipStatus.friends => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: _AddFriendsColors.muted),
          SizedBox(width: 4),
          Text(
            'FRIENDS',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: _AddFriendsColors.muted,
            ),
          ),
        ],
      ),
      RelationshipStatus.pendingReceived => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: onDecline,
            child: const Text('Decline', style: TextStyle(color: _AddFriendsColors.muted)),
          ),
          _GradientPillButton(label: 'Accept', onTap: onAccept),
        ],
      ),
    };
  }
}

class _OutlinedPill extends StatelessWidget {
  const _OutlinedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AddFriendsColors.tertiary),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: _AddFriendsColors.tertiary,
        ),
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
            colors: [_AddFriendsColors.gradientStart, _AddFriendsColors.gradientEnd],
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
