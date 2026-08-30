import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';
import 'create_playlist_screen.dart';
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
    final created = await Navigator.of(
      context,
    ).push<Playlist>(MaterialPageRoute(builder: (_) => const CreatePlaylistScreen()));
    if (created != null) await _addPlaylistLocally(created);
  }

  /// Inserts a freshly created playlist into the already-loaded list right
  /// away, so it appears the instant creation succeeds instead of only
  /// after a manual pull-to-refresh. Falls back to a full [_refresh] if
  /// nothing's loaded yet (e.g. the initial load failed).
  Future<void> _addPlaylistLocally(Playlist playlist) async {
    _ListData? current;
    try {
      current = await _dataFuture;
    } catch (_) {
      current = null;
    }
    if (!mounted) return;

    if (current == null) {
      await _refresh();
      return;
    }

    setState(() {
      _dataFuture = Future.value(
        _ListData(playlists: [playlist, ...current!.playlists], authUser: current.authUser),
      );
    });
  }

  Future<void> _onOpenPlaylist(Playlist playlist) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: playlist.id)));
    _refresh();
  }

  Future<void> _onDeletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _PlaylistColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Playlist?', style: TextStyle(fontFamily: 'Sora', color: _PlaylistColors.body)),
        content: Text(
          '"${playlist.title}" and all of its songs will be permanently deleted.',
          style: const TextStyle(color: _PlaylistColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _PlaylistColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _playlistApi.deletePlaylist(playlist.id);
      _refresh();
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
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
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final playlist = visible[index];
                              return _PlaylistHeroCard(
                                playlist: playlist,
                                isOwner: playlist.owner == email,
                                onTap: () => _onOpenPlaylist(playlist),
                                onDelete: () => _onDeletePlaylist(playlist),
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
  const _PlaylistHeroCard({
    required this.playlist,
    required this.onTap,
    required this.isOwner,
    required this.onDelete,
  });

  final Playlist playlist;
  final VoidCallback onTap;

  /// Deleting is an owner-only action — the backend rejects it from
  /// anyone else (`PlaylistDetailView.perform_destroy`).
  final bool isOwner;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _PlaylistColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _PlaylistColors.cardBorder),
        ),
        child: Row(
          children: [
            PlaylistCoverThumb(playlist: playlist, size: 56, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _PlaylistColors.body,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${playlist.songCount} ${playlist.songCount == 1 ? 'track' : 'tracks'} · ${playlist.owner}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _PlaylistColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VisibilityBadge(visibility: playlist.visibility),
                      const SizedBox(width: 8),
                      EditPermissionBadge(editPermission: playlist.editPermission),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<_PlaylistAction>(
              icon: const Icon(Icons.more_vert_rounded, color: _PlaylistColors.muted),
              color: _PlaylistColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (action) {
                switch (action) {
                  case _PlaylistAction.open:
                    onTap();
                  case _PlaylistAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PlaylistAction.open,
                  child: Text('Open', style: TextStyle(color: _PlaylistColors.body)),
                ),
                if (isOwner)
                  const PopupMenuItem(
                    value: _PlaylistAction.delete,
                    child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlaylistAction { open, delete }

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

