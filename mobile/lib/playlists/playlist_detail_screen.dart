import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import 'playlist_api.dart';
import 'playlist_collaborators_screen.dart';
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
  static const chip = Color(0xFF232230);
}

/// One playlist's detail view: cover, badges, and its ordered song list.
///
/// Whether the signed-in user can add/reorder/remove songs (`canEdit`) is
/// derived entirely from real fields — `Playlist.owner`,
/// `Playlist.editPermission`, and whether the signed-in user shows up in
/// `GET .../collaborators/` — never assumed. The backend remains the
/// final authority: any edit action that's actually rejected still
/// surfaces its exact `ApiException.message`.
///
/// Reordering is collaborative: two people can drag songs in the same
/// playlist at once, so a locally-dragged order is only ever a guess.
/// After every move (and on a timer, in case someone *else* just moved
/// something), the song list is re-fetched and the server's order
/// replaces whatever was on screen.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  static const _pollInterval = Duration(seconds: 4);

  final _playlistApi = PlaylistApi();
  final _authApi = AuthApi();
  final _tokenStorage = TokenStorage();

  Timer? _pollTimer;

  var _isLoading = true;
  String? _loadError;

  Playlist? _playlist;
  List<PlaylistSong> _songs = const [];
  List<PlaylistCollaborator> _collaborators = const [];
  AuthUser? _authUser;

  /// True while a drag gesture is in progress, so a poll tick landing
  /// mid-drag doesn't yank the list out from under the user's finger.
  var _isDragging = false;

  /// True from the moment a drop triggers a move call until the
  /// follow-up re-fetch lands, so a poll tick doesn't race that
  /// reconciliation.
  var _isSyncingOrder = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollSongs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final isFirstLoad = _playlist == null;
    if (isFirstLoad) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final results = await Future.wait([
        _playlistApi.getPlaylist(widget.playlistId),
        _playlistApi.listSongs(widget.playlistId),
        _playlistApi.listCollaborators(widget.playlistId),
        _authApi.getCurrentUser(),
      ]);
      if (!mounted) return;
      setState(() {
        _playlist = results[0] as Playlist;
        _songs = results[1] as List<PlaylistSong>;
        _collaborators = results[2] as List<PlaylistCollaborator>;
        _authUser = results[3] as AuthUser;
        _isLoading = false;
        _loadError = null;
      });
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (isFirstLoad) {
        setState(() {
          _isLoading = false;
          _loadError = error.message;
        });
      } else {
        // A failed pull-to-refresh shouldn't blank out an already-loaded
        // screen — just report it and keep showing the last known state.
        _showMessage(error.message);
      }
    }
  }

  /// Lightweight background refresh of just the song list — used both by
  /// the poll timer and to reconcile after a move/remove, since those are
  /// the fields that change out from under this screen when a
  /// collaborator edits the same playlist concurrently.
  Future<void> _refetchSongs() async {
    try {
      final songs = await _playlistApi.listSongs(widget.playlistId);
      if (!mounted) return;
      setState(() => _songs = songs);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException {
      // Silent — this runs in the background (poll tick or post-move
      // reconciliation); the next poll tick will retry.
    }
  }

  Future<void> _pollSongs() async {
    if (!mounted || _playlist == null || _isDragging || _isSyncingOrder) return;
    await _refetchSongs();
  }

  Future<void> _refetchCollaborators() async {
    try {
      final collaborators = await _playlistApi.listCollaborators(widget.playlistId);
      if (!mounted) return;
      setState(() => _collaborators = collaborators);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException {
      // Background refresh — fail silently.
    }
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onAddSong() async {
    final data = await showDialog<_NewSongInput>(
      context: context,
      builder: (_) => const _AddSongDialog(),
    );
    if (data == null) return;

    try {
      await _playlistApi.addSong(widget.playlistId, title: data.title, artist: data.artist);
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
    await _refetchSongs();
  }

  /// Called when [ReorderableListView] drops a song at [newIndex] (already
  /// adjusted by the framework for the item's removal from [oldIndex] —
  /// see [ReorderableListView.onReorderItem]). The list is reordered
  /// locally first purely so the drop animates to where it was released —
  /// that local order is never trusted as final. Once the move call
  /// resolves (success or not), the song list is always re-fetched, and
  /// the server's order replaces it.
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final movedSong = _songs[oldIndex];

    setState(() {
      final reordered = List<PlaylistSong>.from(_songs);
      reordered.insert(newIndex, reordered.removeAt(oldIndex));
      _songs = reordered;
      _isSyncingOrder = true;
    });

    try {
      await _playlistApi.moveSong(widget.playlistId, movedSong.id, newPosition: newIndex);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      // The one "stale" case the backend can actually report: the song
      // was removed by someone else between this screen's last fetch and
      // this drop. Any other failure (e.g. permissions changing
      // concurrently) surfaces its own message as-is.
      _showMessage(
        error.statusCode == 404
            ? 'That song was removed elsewhere — refreshing the list.'
            : error.message,
      );
    } finally {
      await _refetchSongs();
      if (mounted) setState(() => _isSyncingOrder = false);
    }
  }

  Future<bool> _confirmRemove(PlaylistSong song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _PlaylistColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Song?', style: TextStyle(fontFamily: 'Sora', color: _PlaylistColors.body)),
        content: Text(
          'Remove "${song.songTitle}" from this playlist?',
          style: const TextStyle(color: _PlaylistColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _PlaylistColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onRemoveSong(PlaylistSong song) async {
    // Dismissible has already animated the tile away — mirror that in
    // state so it doesn't reappear before the refetch lands.
    setState(() => _songs = _songs.where((s) => s.id != song.id).toList());

    try {
      await _playlistApi.removeSong(widget.playlistId, song.id);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      _showMessage(error.message);
    } finally {
      await _refetchSongs();
    }
  }

  void _onPlaybackUnavailable() {
    _showMessage("Playback isn't available yet.");
  }

  Future<void> _onManageCollaborators() async {
    final playlist = _playlist;
    if (playlist == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PlaylistCollaboratorsScreen(playlistId: widget.playlistId, playlistTitle: playlist.title),
      ),
    );
    await _refetchCollaborators();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PlaylistColors.background,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Column(
        children: [
          const _Header(canEdit: false, onAddSong: null, isOwner: false, onManageCollaborators: null),
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: _PlaylistColors.headline)),
          ),
        ],
      );
    }

    final playlist = _playlist;
    if (playlist == null || _loadError != null) {
      return Column(
        children: [
          const _Header(canEdit: false, onAddSong: null, isOwner: false, onManageCollaborators: null),
          Expanded(
            child: _ErrorState(
              message: _loadError ?? 'Could not load this playlist.',
              onRetry: _loadAll,
            ),
          ),
        ],
      );
    }

    final authUser = _authUser!;
    final isOwner = playlist.owner == authUser.email;
    final isCollaborator = _collaborators.any((c) => c.collaboratorEmail == authUser.email);
    final canEdit =
        isOwner ||
        playlist.editPermission == playlistEditPermissionEveryone ||
        (playlist.editPermission == playlistEditPermissionInvitedOnly && isCollaborator);

    final header = Column(
      children: [
        _CoverHero(playlist: playlist),
        const SizedBox(height: 20),
        _PlaybackRow(onTap: _onPlaybackUnavailable),
        const SizedBox(height: 24),
        if (!canEdit && playlist.editPermission == playlistEditPermissionInvitedOnly) ...[
          const _EditLockedBanner(),
          const SizedBox(height: 16),
        ],
        if (_songs.isEmpty) _EmptySongsState(canEdit: canEdit, onAddSong: _onAddSong),
      ],
    );

    return Column(
      children: [
        _Header(
          canEdit: canEdit,
          onAddSong: _onAddSong,
          isOwner: isOwner,
          onManageCollaborators: _onManageCollaborators,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            color: _PlaylistColors.headline,
            backgroundColor: _PlaylistColors.card,
            child: canEdit
                ? ReorderableListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    header: header,
                    onReorderStart: (_) => setState(() => _isDragging = true),
                    onReorderEnd: (_) => setState(() => _isDragging = false),
                    onReorderItem: _onReorder,
                    children: [
                      for (final song in _songs)
                        Padding(
                          key: ValueKey(song.id),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Dismissible(
                            key: ValueKey(song.id),
                            direction: DismissDirection.endToStart,
                            background: const _DismissBackground(),
                            confirmDismiss: (_) => _confirmRemove(song),
                            onDismissed: (_) => _onRemoveSong(song),
                            child: _SongRow(song: song),
                          ),
                        ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      header,
                      for (final song in _songs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SongRow(song: song),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canEdit,
    required this.onAddSong,
    required this.isOwner,
    required this.onManageCollaborators,
  });

  final bool canEdit;
  final VoidCallback? onAddSong;

  /// Managing collaborators is an owner-only action — the backend rejects
  /// invite/remove from anyone else (`backend/playlists/views_collaborators.py`).
  final bool isOwner;
  final VoidCallback? onManageCollaborators;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _PlaylistColors.body),
          ),
          const Expanded(
            child: Text(
              'Playlist',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _PlaylistColors.body,
              ),
            ),
          ),
          if (isOwner) ...[
            IconButton(
              onPressed: onManageCollaborators,
              style: IconButton.styleFrom(
                backgroundColor: _PlaylistColors.card,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.group_rounded, color: _PlaylistColors.body),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: canEdit ? onAddSong : null,
            style: IconButton.styleFrom(backgroundColor: _PlaylistColors.card, shape: const CircleBorder()),
            icon: Icon(
              Icons.add_rounded,
              color: canEdit ? _PlaylistColors.body : _PlaylistColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverHero extends StatelessWidget {
  const _CoverHero({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_PlaylistColors.gradientStart, _PlaylistColors.gradientEnd],
            ),
          ),
          child: const Center(
            child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 72),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          playlist.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w800,
            fontSize: 24,
            color: _PlaylistColors.body,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'By ${playlist.owner}',
          style: const TextStyle(fontSize: 13, color: _PlaylistColors.muted),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VisibilityBadge(visibility: playlist.visibility),
            const SizedBox(width: 8),
            EditPermissionBadge(editPermission: playlist.editPermission),
          ],
        ),
      ],
    );
  }
}

/// Play/shuffle controls. Presentational only — this app has no audio
/// playback engine yet, so both just surface a "not available yet"
/// message rather than pretending to play anything.
class _PlaybackRow extends StatelessWidget {
  const _PlaybackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: _PlaylistColors.tertiary),
            child: const Icon(Icons.play_arrow_rounded, color: _PlaylistColors.background, size: 30),
          ),
        ),
        const SizedBox(width: 16),
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _PlaylistColors.cardBorder),
            ),
            child: const Icon(Icons.shuffle_rounded, color: _PlaylistColors.body, size: 20),
          ),
        ),
      ],
    );
  }
}

class _EditLockedBanner extends StatelessWidget {
  const _EditLockedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: _PlaylistColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _PlaylistColors.cardBorder),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded, size: 15, color: _PlaylistColors.muted),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'ONLY INVITED COLLABORATORS CAN EDIT THIS PLAYLIST',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: _PlaylistColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySongsState extends StatelessWidget {
  const _EmptySongsState({required this.canEdit, required this.onAddSong});

  final bool canEdit;
  final VoidCallback onAddSong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.music_off_rounded, size: 36, color: _PlaylistColors.muted),
          const SizedBox(height: 12),
          const Text('No songs yet.', style: TextStyle(color: _PlaylistColors.body)),
          if (canEdit) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onAddSong,
              style: OutlinedButton.styleFrom(
                foregroundColor: _PlaylistColors.tertiary,
                side: const BorderSide(color: _PlaylistColors.tertiary),
              ),
              child: const Text('Add a Song'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song});

  final PlaylistSong song;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _PlaylistColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _PlaylistColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: _PlaylistColors.chip, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.music_note_rounded, color: _PlaylistColors.headline, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.songTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _PlaylistColors.body,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.songArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _PlaylistColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
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

class _NewSongInput {
  const _NewSongInput({required this.title, required this.artist});

  final String title;
  final String artist;
}

class _AddSongDialog extends StatefulWidget {
  const _AddSongDialog();

  @override
  State<_AddSongDialog> createState() => _AddSongDialogState();
}

class _AddSongDialogState extends State<_AddSongDialog> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();
    if (title.isEmpty || artist.isEmpty) {
      setState(() => _error = 'Title and artist are both required.');
      return;
    }
    Navigator.of(context).pop(_NewSongInput(title: title, artist: artist));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _PlaylistColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add a Song', style: TextStyle(fontFamily: 'Sora', color: _PlaylistColors.body)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            style: const TextStyle(color: _PlaylistColors.body),
            decoration: const InputDecoration(
              labelText: 'Title',
              labelStyle: TextStyle(color: _PlaylistColors.muted),
            ),
          ),
          TextField(
            controller: _artistController,
            style: const TextStyle(color: _PlaylistColors.body),
            decoration: const InputDecoration(
              labelText: 'Artist',
              labelStyle: TextStyle(color: _PlaylistColors.muted),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: _PlaylistColors.muted)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Add', style: TextStyle(color: _PlaylistColors.tertiary)),
        ),
      ],
    );
  }
}
