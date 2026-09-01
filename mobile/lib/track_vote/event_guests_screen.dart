import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../core/api/api_client.dart';
import '../profile/profile_api.dart';
import '../profile/profile_avatar.dart';
import '../profile/profile_models.dart';
import '../profile/profile_preview_sheet.dart';
import 'event_api.dart';
import 'event_models.dart';

class _GuestColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
}

/// Host-only guest management. User lookup deliberately reuses the same
/// debounced `ProfileApi.searchUsers` endpoint and result model as Add Friends.
class EventGuestsScreen extends StatefulWidget {
  const EventGuestsScreen({super.key, required this.eventId});
  final int eventId;

  @override
  State<EventGuestsScreen> createState() => _EventGuestsScreenState();
}

class _EventGuestsScreenState extends State<EventGuestsScreen> {
  final _eventApi = EventApi();
  final _profileApi = ProfileApi();
  final _authApi = AuthApi();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<EventGuest> _guests = const [];
  List<SearchUser>? _searchResults;
  var _isLoading = true;
  var _isSearching = false;
  int? _changingUserId;
  int? _currentUserId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGuests();
    _authApi.getCurrentUser().then((user) {
      if (mounted) setState(() => _currentUserId = user.id);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGuests() async {
    try {
      final guests = await _eventApi.listGuests(widget.eventId);
      if (!mounted) return;
      setState(() {
        _guests = guests;
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

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await _profileApi.searchUsers(query);
      if (!mounted || query != _searchController.text) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _invite(SearchUser user) async {
    setState(() => _changingUserId = user.id);
    try {
      await _eventApi.inviteGuest(widget.eventId, user.id);
      await _loadGuests();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${user.fullName} invited.')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _changingUserId = null);
    }
  }

  Future<void> _remove(EventGuest guest) async {
    setState(() => _changingUserId = guest.guest);
    try {
      await _eventApi.removeGuest(widget.eventId, guest.guest);
      await _loadGuests();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _changingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _GuestColors.background,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: _GuestColors.body,
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Manage Guests',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _GuestColors.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onQueryChanged,
              style: const TextStyle(color: _GuestColors.body),
              decoration: InputDecoration(
                hintText: 'Find a friend to invite...',
                hintStyle: const TextStyle(color: _GuestColors.muted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _GuestColors.tertiary,
                ),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _GuestColors.tertiary,
                          ),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: _GuestColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildBody()),
        ],
      ),
    ),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _GuestColors.tertiary),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: _GuestColors.muted)),
      );
    }
    final results = _searchResults;
    if (results != null) {
      return _SearchResults(
        results: results,
        guestIds: _guests.map((guest) => guest.guest).toSet(),
        changingUserId: _changingUserId,
        currentUserId: _currentUserId,
        onInvite: _invite,
      );
    }
    return _GuestList(
      guests: _guests,
      changingUserId: _changingUserId,
      currentUserId: _currentUserId,
      onRemove: _remove,
    );
  }
}

class _GuestList extends StatelessWidget {
  const _GuestList({
    required this.guests,
    required this.changingUserId,
    required this.currentUserId,
    required this.onRemove,
  });
  final List<EventGuest> guests;
  final int? changingUserId;
  final int? currentUserId;
  final ValueChanged<EventGuest> onRemove;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    itemCount: guests.isEmpty ? 2 : guests.length + 1,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      if (index == 0) {
        return const Text(
          'INVITED GUESTS',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: _GuestColors.muted,
          ),
        );
      }
      if (guests.isEmpty) {
        return const Text(
          'No guests have been invited yet.',
          style: TextStyle(color: _GuestColors.muted),
        );
      }
      final guest = guests[index - 1];
      final name = guest.guestDisplayName.isNotEmpty
          ? guest.guestDisplayName
          : guest.guestEmail;
      return _GuestCard(
        userId: guest.guest,
        currentUserId: currentUserId,
        name: name,
        username: guest.guestUsername,
        avatar: guest.guestAvatar,
        avatarType: guest.guestAvatarType,
        trailing: IconButton(
          onPressed: changingUserId == guest.guest
              ? null
              : () => onRemove(guest),
          icon: const Icon(
            Icons.person_remove_rounded,
            color: Color(0xFFFFB4AB),
          ),
          tooltip: 'Remove guest',
        ),
      );
    },
  );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.guestIds,
    required this.changingUserId,
    required this.currentUserId,
    required this.onInvite,
  });
  final List<SearchUser> results;
  final Set<int> guestIds;
  final int? changingUserId;
  final int? currentUserId;
  final ValueChanged<SearchUser> onInvite;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No users found.',
          style: TextStyle(color: _GuestColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = results[index];
        final invited = guestIds.contains(user.id);
        return _GuestCard(
          userId: user.id,
          currentUserId: currentUserId,
          name: user.fullName,
          username: user.username,
          avatar: user.avatar,
          avatarType: user.avatarType,
          trailing: invited
              ? const Text(
                  'INVITED',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _GuestColors.muted,
                  ),
                )
              : FilledButton(
                  onPressed: changingUserId == user.id
                      ? null
                      : () => onInvite(user),
                  style: FilledButton.styleFrom(
                    backgroundColor: _GuestColors.tertiary,
                    foregroundColor: const Color(0xFF0E0E15),
                  ),
                  child: changingUserId == user.id
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _GuestColors.background,
                          ),
                        )
                      : const Text('Invite'),
                ),
        );
      },
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({
    required this.userId,
    required this.currentUserId,
    required this.name,
    required this.username,
    required this.avatar,
    required this.avatarType,
    required this.trailing,
  });
  final int userId;
  final int? currentUserId;
  final String name;
  final String username;
  final String? avatar;
  final String avatarType;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _GuestColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _GuestColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => showProfilePreview(
              context,
              userId: userId,
              currentUserId: currentUserId,
              initialName: name,
              initialUsername: username,
              initialAvatar: avatar,
              initialAvatarType: avatarType,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: ProfileAvatarImage(
                      avatar: avatar,
                      avatarType: avatarType,
                      fallback: CircleAvatar(
                        backgroundColor: _GuestColors.border,
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                            color: _GuestColors.tertiary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w700,
                      color: _GuestColors.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        trailing,
      ],
    ),
  );
}
