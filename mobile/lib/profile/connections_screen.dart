import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'add_friends_screen.dart';
import 'profile_api.dart';
import 'profile_models.dart';
import 'view_profile_screen.dart';

class _ConnectionsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
  static const badge = Color(0xFFE05FA8);
}

/// The signed-in user's Friends screen: an accepted-friends list (backed by
/// `GET /api/v1/profile/friends/`) and a Requests tab covering both
/// directions (`GET .../friends/requests/` and `.../friends/requests/sent/`).
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _profileApi = ProfileApi();

  var _isLoading = true;
  String? _error;
  List<Friend> _friends = const [];
  List<FriendRequest> _received = const [];
  List<FriendRequest> _sent = const [];

  var _tab = _ConnectionsTab.friends;
  var _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _profileApi.getFriends(),
        _profileApi.getReceivedRequests(),
        _profileApi.getSentRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<Friend>;
        _received = results[1] as List<FriendRequest>;
        _sent = results[2] as List<FriendRequest>;
        _isLoading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load your friends.';
      });
    }
  }

  Future<void> _onAddFriends() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddFriendsScreen()));
    _load();
  }

  Future<void> _onAccept(FriendRequest request) async {
    try {
      await _profileApi.acceptFriendRequest(request.id);
      if (!mounted) return;
      setState(() {
        _received = _received.where((r) => r.id != request.id).toList();
        _friends = [
          ..._friends,
          Friend(
            id: request.otherUserId,
            firstName: request.otherUserFirstName,
            lastName: request.otherUserLastName,
          ),
        ];
      });
    } on ApiException catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _onReject(FriendRequest request) async {
    try {
      await _profileApi.rejectFriendRequest(request.id);
      if (!mounted) return;
      setState(() => _received = _received.where((r) => r.id != request.id).toList());
    } on ApiException catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _onViewFriend(Friend friend) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewProfileScreen(
          userId: friend.id,
          initialFullName: friend.fullName,
          relationshipStatus: RelationshipStatus.friends,
        ),
      ),
    );
    _load();
  }

  Future<void> _onViewRequest(FriendRequest request, RelationshipStatus status) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewProfileScreen(
          userId: request.otherUserId,
          initialFullName: request.otherUserFullName,
          relationshipStatus: status,
          friendshipId: request.id,
        ),
      ),
    );
    _load();
  }

  Future<void> _onRemoveFriend(Friend friend) async {
    try {
      await _profileApi.removeFriend(friend.id);
      if (!mounted) return;
      setState(() => _friends = _friends.where((f) => f.id != friend.id).toList());
    } on ApiException catch (error) {
      _showError(error.message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _received.length + _sent.length;

    return Scaffold(
      backgroundColor: _ConnectionsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onAddFriends: _onAddFriends),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TabSwitcher(
                tab: _tab,
                pendingCount: pendingCount,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
            if (_tab == _ConnectionsTab.friends) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SearchField(onChanged: (q) => setState(() => _searchQuery = q)),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: _ConnectionsColors.headline),
                    );
                  }

                  if (_error != null) {
                    return _ErrorState(onRetry: _load);
                  }

                  return RefreshIndicator(
                    onRefresh: _load,
                    color: _ConnectionsColors.headline,
                    backgroundColor: _ConnectionsColors.card,
                    child: _tab == _ConnectionsTab.friends
                        ? _FriendsList(
                            friends: _filteredFriends(_friends),
                            onRemove: _onRemoveFriend,
                            onTap: _onViewFriend,
                          )
                        : _RequestsList(
                            received: _received,
                            sent: _sent,
                            onAccept: _onAccept,
                            onReject: _onReject,
                            onTapReceived: (request) =>
                                _onViewRequest(request, RelationshipStatus.pendingReceived),
                            onTapSent: (request) =>
                                _onViewRequest(request, RelationshipStatus.pendingSent),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Friend> _filteredFriends(List<Friend> friends) {
    if (_searchQuery.trim().isEmpty) return friends;
    final query = _searchQuery.trim().toLowerCase();
    return friends.where((friend) => friend.fullName.toLowerCase().contains(query)).toList();
  }
}

enum _ConnectionsTab { friends, requests }

class _Header extends StatelessWidget {
  const _Header({required this.onAddFriends});

  final VoidCallback onAddFriends;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _ConnectionsColors.body),
          ),
          const Expanded(
            child: Text(
              'Friends',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: _ConnectionsColors.body,
              ),
            ),
          ),
          IconButton(
            onPressed: onAddFriends,
            style: IconButton.styleFrom(
              backgroundColor: _ConnectionsColors.card,
              shape: const CircleBorder(),
            ),
            icon: const Icon(Icons.add_rounded, color: _ConnectionsColors.body),
          ),
        ],
      ),
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.tab, required this.pendingCount, required this.onChanged});

  final _ConnectionsTab tab;
  final int pendingCount;
  final ValueChanged<_ConnectionsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _ConnectionsColors.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Friends',
              isSelected: tab == _ConnectionsTab.friends,
              onTap: () => onChanged(_ConnectionsTab.friends),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Requests',
              badgeCount: pendingCount,
              isSelected: tab == _ConnectionsTab.requests,
              onTap: () => onChanged(_ConnectionsTab.requests),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _ConnectionsColors.border : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isSelected ? _ConnectionsColors.body : _ConnectionsColors.muted,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(color: _ConnectionsColors.badge, shape: BoxShape.circle),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: _ConnectionsColors.body),
      decoration: InputDecoration(
        hintText: 'Search friends...',
        hintStyle: const TextStyle(color: _ConnectionsColors.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: _ConnectionsColors.muted),
        filled: true,
        fillColor: _ConnectionsColors.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Could not load your friends.',
              style: TextStyle(color: _ConnectionsColors.body),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => onRetry(), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({required this.friends, required this.onRemove, required this.onTap});

  final List<Friend> friends;
  final ValueChanged<Friend> onRemove;
  final ValueChanged<Friend> onTap;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return const _EmptyState(message: 'No friends yet — tap + to find people.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: friends.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _FriendRow(friend: friends[index], onRemove: onRemove, onTap: onTap),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.onRemove, required this.onTap});

  final Friend friend;
  final ValueChanged<Friend> onRemove;
  final ValueChanged<Friend> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ConnectionsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ConnectionsColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onTap(friend),
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  _Avatar(letter: friend.firstName.isNotEmpty ? friend.firstName[0].toUpperCase() : '?'),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      friend.fullName,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ConnectionsColors.body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<void>(
            color: _ConnectionsColors.card,
            icon: const Icon(Icons.more_vert_rounded, color: _ConnectionsColors.muted),
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => onRemove(friend),
                child: const Text('Remove friend', style: TextStyle(color: _ConnectionsColors.body)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({
    required this.received,
    required this.sent,
    required this.onAccept,
    required this.onReject,
    required this.onTapReceived,
    required this.onTapSent,
  });

  final List<FriendRequest> received;
  final List<FriendRequest> sent;
  final ValueChanged<FriendRequest> onAccept;
  final ValueChanged<FriendRequest> onReject;
  final ValueChanged<FriendRequest> onTapReceived;
  final ValueChanged<FriendRequest> onTapSent;

  @override
  Widget build(BuildContext context) {
    if (received.isEmpty && sent.isEmpty) {
      return const _EmptyState(message: 'No pending friend requests.');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (received.isNotEmpty) ...[
          _SectionLabel('RECEIVED • ${received.length}'),
          const SizedBox(height: 10),
          for (final request in received) ...[
            _ReceivedRequestRow(
              request: request,
              onAccept: onAccept,
              onReject: onReject,
              onTap: onTapReceived,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
        ],
        if (sent.isNotEmpty) ...[
          _SectionLabel('SENT • ${sent.length}'),
          const SizedBox(height: 10),
          for (final request in sent) ...[
            _SentRequestRow(request: request, onTap: onTapSent),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: _ConnectionsColors.muted,
      ),
    );
  }
}

class _ReceivedRequestRow extends StatelessWidget {
  const _ReceivedRequestRow({
    required this.request,
    required this.onAccept,
    required this.onReject,
    required this.onTap,
  });

  final FriendRequest request;
  final ValueChanged<FriendRequest> onAccept;
  final ValueChanged<FriendRequest> onReject;
  final ValueChanged<FriendRequest> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ConnectionsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ConnectionsColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onTap(request),
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  _Avatar(
                    letter: request.otherUserFirstName.isNotEmpty
                        ? request.otherUserFirstName[0].toUpperCase()
                        : '?',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      request.otherUserFullName,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ConnectionsColors.body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => onReject(request),
            child: const Text('Decline', style: TextStyle(color: _ConnectionsColors.muted)),
          ),
          const SizedBox(width: 4),
          _GradientPillButton(label: 'Accept', onTap: () => onAccept(request)),
        ],
      ),
    );
  }
}

class _SentRequestRow extends StatelessWidget {
  const _SentRequestRow({required this.request, required this.onTap});

  final FriendRequest request;
  final ValueChanged<FriendRequest> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(request),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _ConnectionsColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _ConnectionsColors.border),
        ),
        child: Row(
          children: [
            _Avatar(
              letter: request.otherUserFirstName.isNotEmpty
                  ? request.otherUserFirstName[0].toUpperCase()
                  : '?',
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                request.otherUserFullName,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ConnectionsColors.body,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _ConnectionsColors.tertiary),
              ),
              child: const Text(
                'Requested',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _ConnectionsColors.tertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _ConnectionsColors.muted),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: _ConnectionsColors.border,
      child: Text(
        letter,
        style: const TextStyle(color: _ConnectionsColors.headline, fontWeight: FontWeight.w700),
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
            colors: [_ConnectionsColors.gradientStart, _ConnectionsColors.gradientEnd],
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
