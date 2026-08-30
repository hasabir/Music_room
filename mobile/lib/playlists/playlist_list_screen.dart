import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';
import 'playlist_api.dart';
import 'playlist_detail_screen.dart';
import 'playlist_models.dart';
import 'playlist_widgets.dart';

class _PlaylistColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const cardBorder = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// The "Playlist Editor" tab — the signed-in user's own/collaborated
/// playlists ("My Playlists") plus public playlists made by others
/// ("Discover"). Reachable from the bottom nav.
///
/// Loads `GET /api/v1/playlists/` (which already returns public + owned +
/// collaborated, deduped) and splits it into the two tabs client-side by
/// comparing each playlist's `owner` against the signed-in user's email —
/// the backend has no separate "discover" endpoint or "is mine" flag.
class PlaylistListScreen extends StatefulWidget {
  const PlaylistListScreen({super.key});

  @override
  State<PlaylistListScreen> createState() => _PlaylistListScreenState();
}

class _PlaylistListScreenState extends State<PlaylistListScreen> {
  final _playlistApi = PlaylistApi();
  final _authApi = AuthApi();
  final _tokenStorage = TokenStorage();

  Future<_ListData>? _dataFuture;
  var _tab = _PlaylistTab.mine;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_ListData> _load() async {
    try {
      final results = await Future.wait([_playlistApi.listPlaylists(), _authApi.getCurrentUser()]);
      return _ListData(
        playlists: results[0] as List<Playlist>,
        authUser: results[1] as AuthUser,
      );
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _dataFuture = future);
    await future.catchError((_) => const _ListData(playlists: [], authUser: null));
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
  }

  Future<void> _onCreatePlaylist() async {
    final created = await showModalBottomSheet<Playlist>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePlaylistSheet(playlistApi: _playlistApi),
    );
    if (created != null) _refresh();
  }

  Future<void> _onOpenPlaylist(Playlist playlist) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: playlist.id)));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PlaylistColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ListHeader(onCreate: _onCreatePlaylist),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TabSwitcher(tab: _tab, onChanged: (tab) => setState(() => _tab = tab)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<_ListData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _PlaylistColors.headline),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Could not load playlists.';
                    return _ErrorState(message: message, onRetry: _refresh);
                  }

                  final data = snapshot.data!;
                  final email = data.authUser?.email ?? '';
                  final visible = data.playlists
                      .where((p) => _tab == _PlaylistTab.mine ? _isMine(p, email) : !_isMine(p, email))
                      .toList();

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: _PlaylistColors.headline,
                    backgroundColor: _PlaylistColors.card,
                    child: visible.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
                            children: [
                              _EmptyState(
                                tab: _tab,
                                onCreate: _tab == _PlaylistTab.mine ? _onCreatePlaylist : null,
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final playlist = visible[index];
                              return _PlaylistHeroCard(
                                playlist: playlist,
                                onTap: () => _onOpenPlaylist(playlist),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.playlist,
        onTabSelected: (tab) => navigateToTab(context, AppTab.playlist, tab),
      ),
    );
  }
}

enum _PlaylistTab { mine, discover }

/// A playlist counts as "mine" if the signed-in user owns it, or if it's
/// private (the list endpoint only ever returns a private playlist to its
/// owner or an invited collaborator, so either way it's not something to
/// "discover").
bool _isMine(Playlist playlist, String currentUserEmail) =>
    playlist.owner == currentUserEmail || playlist.visibility == playlistVisibilityPrivate;

class _ListData {
  const _ListData({required this.playlists, required this.authUser});

  final List<Playlist> playlists;
  final AuthUser? authUser;
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Playlist Editor',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: _PlaylistColors.body,
              ),
            ),
          ),
          IconButton(
            onPressed: onCreate,
            style: IconButton.styleFrom(backgroundColor: _PlaylistColors.card, shape: const CircleBorder()),
            icon: const Icon(Icons.add_rounded, color: _PlaylistColors.body),
          ),
        ],
      ),
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.tab, required this.onChanged});

  final _PlaylistTab tab;
  final ValueChanged<_PlaylistTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _PlaylistColors.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'My Playlists',
              isSelected: tab == _PlaylistTab.mine,
              onTap: () => onChanged(_PlaylistTab.mine),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Discover',
              isSelected: tab == _PlaylistTab.discover,
              onTap: () => onChanged(_PlaylistTab.discover),
            ),
          ),
        ],
      ),
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _PlaylistColors.cardBorder : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: isSelected ? _PlaylistColors.body : _PlaylistColors.muted,
          ),
        ),
      ),
    );
  }
}

class _PlaylistHeroCard extends StatelessWidget {
  const _PlaylistHeroCard({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: _PlaylistColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _PlaylistColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_PlaylistColors.gradientStart, _PlaylistColors.gradientEnd],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 56),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${playlist.songCount} ${playlist.songCount == 1 ? 'track' : 'tracks'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: _PlaylistColors.body,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'By ${playlist.owner}',
                    style: const TextStyle(fontSize: 13, color: _PlaylistColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      VisibilityBadge(visibility: playlist.visibility),
                      const SizedBox(width: 8),
                      EditPermissionBadge(editPermission: playlist.editPermission),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab, required this.onCreate});

  final _PlaylistTab tab;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final message = tab == _PlaylistTab.mine
        ? "You don't have any playlists yet."
        : 'No public playlists to discover yet.';

    return Column(
      children: [
        const Icon(Icons.queue_music_rounded, size: 40, color: _PlaylistColors.muted),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _PlaylistColors.body)),
        if (onCreate != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onCreate,
            style: OutlinedButton.styleFrom(
              foregroundColor: _PlaylistColors.tertiary,
              side: const BorderSide(color: _PlaylistColors.tertiary),
            ),
            child: const Text('Create a Playlist'),
          ),
        ],
      ],
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
            const Icon(Icons.wifi_off_rounded, color: _PlaylistColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _PlaylistColors.body)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => onRetry(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _PlaylistColors.tertiary,
                side: const BorderSide(color: _PlaylistColors.tertiary),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePlaylistSheet extends StatefulWidget {
  const _CreatePlaylistSheet({required this.playlistApi});

  final PlaylistApi playlistApi;

  @override
  State<_CreatePlaylistSheet> createState() => _CreatePlaylistSheetState();
}

class _CreatePlaylistSheetState extends State<_CreatePlaylistSheet> {
  final _titleController = TextEditingController();
  var _visibility = playlistVisibilityPublic;
  var _editPermission = playlistEditPermissionEveryone;
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your playlist a title.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final playlist = await widget.playlistApi.createPlaylist(
        title: title,
        visibility: _visibility,
        editPermission: _editPermission,
      );
      if (!mounted) return;
      Navigator.of(context).pop(playlist);
    } on ApiException catch (error) {
      setState(() {
        _isSubmitting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          color: _PlaylistColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create Playlist',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: _PlaylistColors.body,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              style: const TextStyle(color: _PlaylistColors.body),
              decoration: InputDecoration(
                hintText: 'Playlist title',
                hintStyle: const TextStyle(color: _PlaylistColors.muted),
                filled: true,
                fillColor: _PlaylistColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _SheetLabel('VISIBILITY'),
            const SizedBox(height: 8),
            _SegmentedChoice(
              options: const {playlistVisibilityPublic: 'Public', playlistVisibilityPrivate: 'Private'},
              value: _visibility,
              onChanged: (value) => setState(() => _visibility = value),
            ),
            const SizedBox(height: 20),
            const _SheetLabel('WHO CAN EDIT'),
            const SizedBox(height: 8),
            _SegmentedChoice(
              options: const {
                playlistEditPermissionEveryone: 'Everyone',
                playlistEditPermissionInvitedOnly: 'Invite Only',
              },
              value: _editPermission,
              onChanged: (value) => setState(() => _editPermission = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _PlaylistColors.tertiary,
                  foregroundColor: _PlaylistColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _PlaylistColors.background),
                      )
                    : const Text(
                        'Create',
                        style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

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
        color: _PlaylistColors.muted,
      ),
    );
  }
}

class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({required this.options, required this.value, required this.onChanged});

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in options.entries) ...[
          if (entry.key != options.keys.first) const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(entry.key),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: entry.key == value ? _PlaylistColors.tertiary.withValues(alpha: 0.15) : _PlaylistColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: entry.key == value ? _PlaylistColors.tertiary : _PlaylistColors.cardBorder,
                  ),
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: entry.key == value ? _PlaylistColors.tertiary : _PlaylistColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
