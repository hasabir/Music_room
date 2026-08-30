import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import '../home/home_screen.dart';
import 'add_song_search_screen.dart';
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
  // The WebSocket below delivers normal updates immediately. Polling remains
  // as a low-frequency fallback for a temporarily unavailable socket.
  static const _pollInterval = Duration(seconds: 30);
  static const _liveUpdateReconnectDelay = Duration(seconds: 2);

  final _playlistApi = PlaylistApi();
  final _authApi = AuthApi();
  final _tokenStorage = TokenStorage();
  final _audioPlayer = AudioPlayer();

  Timer? _pollTimer;
  StreamSubscription<void>? _previewCompleteSub;
  WebSocket? _playlistSocket;
  StreamSubscription<dynamic>? _playlistSocketSub;
  Timer? _liveUpdateReconnectTimer;
  var _isConnectingLiveUpdates = false;

  /// Id of the `PlaylistSong` whose 30-second preview is currently
  /// playing, if any. There's no full-track playback yet (see
  /// `_PlaybackRow`), so this preview doubles as the only way to actually
  /// hear a song that's already in the playlist.
  int? _playingSongId;

  /// Ids of the songs queued for shuffled auto-advance playback, in the
  /// randomized order they'll play, plus where we are in that order.
  /// Empty/-1 when playback isn't an auto-advancing shuffle (e.g. a single
  /// song was tapped directly from the list).
  List<int> _shuffleQueue = const [];
  int _shuffleIndex = -1;
  var _isShufflePlayback = false;

  var _isLoading = true;
  String? _loadError;
  int? _loadErrorStatusCode;

  Playlist? _playlist;
  List<PlaylistSong> _songs = const [];
  List<PlaylistCollaborator> _collaborators = const [];
  AuthUser? _authUser;

  /// The signed-in user's own access request for this playlist, if any —
  /// drives the "Request Access" / "Request Sent" affordance on both the
  /// access-denied screen and the view-only banner.
  PlaylistAccessRequest? _myAccessRequest;
  var _isRequestingAccess = false;

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
    _connectLiveUpdates();
    _previewCompleteSub = _audioPlayer.onPlayerComplete.listen(
      (_) {
        if (mounted) unawaited(_advanceAfterPreview());
      },
      onError: (Object error, [StackTrace? stackTrace]) {
        // A native playback error (e.g. an expired/broken preview URL)
        // surfaces here rather than from the `play()` call that started
        // it. Treat it like the track ending so a shuffle session skips
        // past the broken preview instead of crashing.
        if (!mounted) return;
        _showMessage('Could not play preview.');
        unawaited(_advanceAfterPreview());
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _previewCompleteSub?.cancel();
    _liveUpdateReconnectTimer?.cancel();
    _playlistSocketSub?.cancel();
    _playlistSocket?.close();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final isFirstLoad = _playlist == null;
    if (isFirstLoad) {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _loadErrorStatusCode = null;
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
      final playlist = results[0] as Playlist;
      final authUser = results[3] as AuthUser;
      setState(() {
        _playlist = playlist;
        _songs = results[1] as List<PlaylistSong>;
        _collaborators = results[2] as List<PlaylistCollaborator>;
        _authUser = authUser;
        _isLoading = false;
        _loadError = null;
        _loadErrorStatusCode = null;
      });
      if (playlist.owner != authUser.email) {
        unawaited(_loadMyAccessRequest());
      }
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (isFirstLoad) {
        setState(() {
          _isLoading = false;
          _loadError = error.message;
          _loadErrorStatusCode = error.statusCode;
        });
        if (error.statusCode == 403) {
          unawaited(_loadMyAccessRequest());
        }
      } else {
        // A failed pull-to-refresh shouldn't blank out an already-loaded
        // screen — just report it and keep showing the last known state.
        _showMessage(error.message);
      }
    }
  }

  /// Best-effort fetch of the signed-in user's own access request for this
  /// playlist — works even without access to the playlist itself, so it's
  /// safe to call right after a 403 on the main load.
  Future<void> _loadMyAccessRequest() async {
    try {
      final request = await _playlistApi.getMyAccessRequest(widget.playlistId);
      if (!mounted) return;
      setState(() => _myAccessRequest = request);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException {
      // Silent — this is a secondary, best-effort fetch.
    }
  }

  Future<void> _onRequestAccess() async {
    setState(() => _isRequestingAccess = true);
    try {
      final request = await _playlistApi.requestAccess(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _myAccessRequest = request;
        _isRequestingAccess = false;
      });
      _showMessage('Access request sent to the playlist owner.');
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isRequestingAccess = false);
      _showMessage(error.message);
    }
  }

  void _onReturnHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
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

  /// Subscribes to the playlist's existing server broadcast. The server sends
  /// the complete, authoritative song list after every add, removal, or move,
  /// so all open playlist screens update without waiting for the poll timer.
  void _connectLiveUpdates() {
    if (!mounted || _isConnectingLiveUpdates || _playlistSocket != null) return;
    unawaited(_openLiveUpdates());
  }

  Future<void> _openLiveUpdates() async {
    _isConnectingLiveUpdates = true;
    try {
      final token = await _tokenStorage.readAccessToken();
      if (!mounted || token == null || token.isEmpty) return;

      final baseUri = Uri.parse(ApiConfig.baseUrl);
      final socketUri = baseUri.replace(
        scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws/playlists/${widget.playlistId}/',
        queryParameters: {'token': token},
      );
      final socket = await WebSocket.connect(socketUri.toString());
      if (!mounted) {
        await socket.close();
        return;
      }

      _playlistSocket = socket;
      _playlistSocketSub = socket.listen(
        _onLiveUpdate,
        onDone: _handleLiveUpdatesDisconnected,
        onError: (_, __) => _handleLiveUpdatesDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleLiveUpdatesReconnect();
    } finally {
      _isConnectingLiveUpdates = false;
    }
  }

  void _onLiveUpdate(dynamic message) {
    if (message is! String || !mounted || _isDragging || _isSyncingOrder) return;
    try {
      final payload = jsonDecode(message);
      if (payload is! Map<String, dynamic> ||
          payload['playlist_id'] != widget.playlistId ||
          payload['songs'] is! List) {
        return;
      }
      final songs = (payload['songs'] as List)
          .whereType<Map>()
          .map((song) => PlaylistSong.fromJson(Map<String, dynamic>.from(song)))
          .toList();
      setState(() => _songs = songs);
    } on FormatException {
      // Ignore a malformed broadcast. The fallback poll will reconcile state.
    }
  }

  void _handleLiveUpdatesDisconnected() {
    _playlistSocketSub?.cancel();
    _playlistSocketSub = null;
    _playlistSocket = null;
    _scheduleLiveUpdatesReconnect();
  }

  void _scheduleLiveUpdatesReconnect() {
    if (!mounted) return;
    _liveUpdateReconnectTimer?.cancel();
    _liveUpdateReconnectTimer = Timer(
      _liveUpdateReconnectDelay,
      _connectLiveUpdates,
    );
  }

  Future<void> _refetchCollaborators() async {
    try {
      final collaborators = await _playlistApi.listCollaborators(
        widget.playlistId,
      );
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
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the search screen and, once it's popped, merges whatever it
  /// added straight into [_songs] — no need to re-fetch the whole list
  /// from the backend just to learn about songs it already told us it
  /// created (`AddSongSearchScreen` hands back every `PlaylistSong` it
  /// successfully added). The poll timer still catches anything a
  /// concurrent collaborator added meanwhile.
  Future<void> _onAddSong() async {
    final addedSongs = await Navigator.of(context).push<List<PlaylistSong>>(
      MaterialPageRoute(
        builder: (_) => AddSongSearchScreen(playlistId: widget.playlistId),
      ),
    );
    if (addedSongs == null || addedSongs.isEmpty || !mounted) return;

    setState(() {
      final merged = List<PlaylistSong>.from(_songs);
      for (final song in addedSongs) {
        if (!merged.any((existing) => existing.id == song.id)) merged.add(song);
      }
      _songs = merged;
    });
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
      await _playlistApi.moveSong(
        widget.playlistId,
        movedSong.id,
        newPosition: newIndex,
      );
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
        title: const Text(
          'Remove Song?',
          style: TextStyle(fontFamily: 'Sora', color: _PlaylistColors.body),
        ),
        content: Text(
          'Remove "${song.songTitle}" from this playlist?',
          style: const TextStyle(color: _PlaylistColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _PlaylistColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
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

  /// Tapping a specific song in the list plays just that preview — no
  /// auto-advance to another track once it finishes.
  Future<void> _onToggleSongPreview(PlaylistSong song) async {
    if (song.songExternalId.isEmpty && song.songPreviewUrl.isEmpty) {
      _showMessage('No preview available for this track.');
      return;
    }

    if (_playingSongId == song.id) {
      await _stopPlayback();
      return;
    }

    _shuffleQueue = const [];
    _shuffleIndex = -1;
    _isShufflePlayback = false;
    await _playPreview(song);
  }

  /// The header play button starts a shuffled auto-advance session across
  /// every previewable song, rather than always going in list order.
  Future<void> _onHeaderPlayTap() async {
    if (_playingSongId != null) {
      await _stopPlayback();
      return;
    }

    final playable =
        _songs
            .where(
              (s) => s.songExternalId.isNotEmpty || s.songPreviewUrl.isNotEmpty,
            )
            .toList()
          ..shuffle(Random());
    if (playable.isEmpty) {
      _showMessage('No preview available for this track.');
      return;
    }

    _shuffleQueue = playable.map((s) => s.id).toList();
    _shuffleIndex = 0;
    _isShufflePlayback = true;
    await _playPreview(playable.first);
  }

  Future<void> _playPreview(PlaylistSong song) async {
    try {
      await _audioPlayer.stop();
      final previewUrl = song.songExternalId.isEmpty
          ? song.songPreviewUrl
          : await _playlistApi.resolvePreviewUrl(song.songExternalId);
      if (previewUrl.isEmpty) throw StateError('No preview URL available.');
      await _audioPlayer.play(UrlSource(previewUrl));
      if (!mounted) return;
      setState(() => _playingSongId = song.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _playingSongId = null);
      _showMessage('Could not play preview.');
    }
  }

  Future<void> _stopPlayback() async {
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _playingSongId = null;
      _shuffleQueue = const [];
      _shuffleIndex = -1;
      _isShufflePlayback = false;
    });
  }

  /// Advances a shuffle session to its next queued song when a preview
  /// finishes naturally; a non-shuffle (single tap) preview just stops.
  Future<void> _advanceAfterPreview() async {
    if (!_isShufflePlayback) {
      final playingSongId = _playingSongId;
      final playingIndex = _songs.indexWhere((song) => song.id == playingSongId);
      for (var index = playingIndex + 1; index < _songs.length; index++) {
        final nextSong = _songs[index];
        if (nextSong.songExternalId.isNotEmpty || nextSong.songPreviewUrl.isNotEmpty) {
          await _playPreview(nextSong);
          return;
        }
      }
      if (!mounted) return;
      setState(() => _playingSongId = null);
      return;
    }

    while (_shuffleIndex >= 0 && _shuffleIndex + 1 < _shuffleQueue.length) {
      _shuffleIndex++;
      final nextId = _shuffleQueue[_shuffleIndex];
      PlaylistSong? nextSong;
      for (final s in _songs) {
        if (s.id == nextId) {
          nextSong = s;
          break;
        }
      }
      if (nextSong != null) {
        await _playPreview(nextSong);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _playingSongId = null;
      _shuffleQueue = const [];
      _shuffleIndex = -1;
      _isShufflePlayback = false;
    });
  }

  Future<void> _onManageCollaborators() async {
    final playlist = _playlist;
    if (playlist == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistCollaboratorsScreen(
          playlistId: widget.playlistId,
          playlistTitle: playlist.title,
        ),
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
          const _Header(
            title: 'Playlist',
            canEdit: false,
            onAddSong: null,
            isOwner: false,
            onManageCollaborators: null,
          ),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: _PlaylistColors.headline),
            ),
          ),
        ],
      );
    }

    final playlist = _playlist;
    if (playlist == null || _loadError != null) {
      final isAccessDenied = _loadErrorStatusCode == 403;
      return Column(
        children: [
          _Header(
            title: isAccessDenied ? 'Music Room' : 'Playlist',
            canEdit: false,
            onAddSong: null,
            isOwner: false,
            onManageCollaborators: null,
          ),
          Expanded(
            child: isAccessDenied
                ? _AccessDeniedState(
                    myRequest: _myAccessRequest,
                    isRequesting: _isRequestingAccess,
                    onRequestAccess: _onRequestAccess,
                    onReturnHome: _onReturnHome,
                  )
                : _ErrorState(
                    message: _loadError ?? 'Could not load this playlist.',
                    onRetry: _loadAll,
                  ),
          ),
        ],
      );
    }

    final authUser = _authUser!;
    final isOwner = playlist.owner == authUser.email;
    final isCollaborator = _collaborators.any(
      (c) => c.collaboratorEmail == authUser.email,
    );
    final canEdit =
        isOwner ||
        playlist.editPermission == playlistEditPermissionEveryone ||
        (playlist.editPermission == playlistEditPermissionInvitedOnly &&
            isCollaborator);

    final header = Column(
      children: [
        _CoverHero(playlist: playlist),
        const SizedBox(height: 20),
        _PlaybackRow(
          isPlaying: _playingSongId != null,
          onPlayTap: _songs.isEmpty ? _onPlaybackUnavailable : _onHeaderPlayTap,
          onShuffleTap: _onPlaybackUnavailable,
        ),
        if (_collaborators.isNotEmpty || isOwner) ...[
          const SizedBox(height: 14),
          _CollaboratorsRow(
            collaborators: _collaborators,
            isOwner: isOwner,
            onInvite: _onManageCollaborators,
          ),
        ],
        const SizedBox(height: 24),
        if (!canEdit &&
            playlist.editPermission == playlistEditPermissionInvitedOnly) ...[
          _EditLockedBanner(
            myRequest: _myAccessRequest,
            isRequesting: _isRequestingAccess,
            onRequestAccess: _onRequestAccess,
          ),
          const SizedBox(height: 16),
        ],
        if (_songs.isEmpty)
          _EmptySongsState(canEdit: canEdit, onAddSong: _onAddSong),
      ],
    );

    return Column(
      children: [
        _Header(
          title: 'Playlist',
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
                    buildDefaultDragHandles: false,
                    onReorderStart: (_) => setState(() => _isDragging = true),
                    onReorderEnd: (_) => setState(() => _isDragging = false),
                    onReorderItem: _onReorder,
                    children: [
                      for (var i = 0; i < _songs.length; i++)
                        Padding(
                          key: ValueKey(_songs[i].id),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Dismissible(
                            key: ValueKey(_songs[i].id),
                            direction: DismissDirection.endToStart,
                            background: const _DismissBackground(),
                            confirmDismiss: (_) => _confirmRemove(_songs[i]),
                            onDismissed: (_) => _onRemoveSong(_songs[i]),
                            child: _SongRow(
                              song: _songs[i],
                              isPlaying: _playingSongId == _songs[i].id,
                              onTogglePreview: () =>
                                  _onToggleSongPreview(_songs[i]),
                              dragHandle: ReorderableDragStartListener(
                                index: i,
                                child: const Icon(
                                  Icons.drag_handle_rounded,
                                  color: _PlaylistColors.muted,
                                ),
                              ),
                            ),
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
                          child: _SongRow(
                            song: song,
                            isPlaying: _playingSongId == song.id,
                            onTogglePreview: () => _onToggleSongPreview(song),
                          ),
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
    required this.title,
    required this.canEdit,
    required this.onAddSong,
    required this.isOwner,
    required this.onManageCollaborators,
  });

  final String title;
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
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: _PlaylistColors.body,
            ),
          ),
          Expanded(
            child: Text(
              title,
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
              icon: const Icon(
                Icons.group_rounded,
                color: _PlaylistColors.body,
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: canEdit ? onAddSong : null,
            style: IconButton.styleFrom(
              backgroundColor: _PlaylistColors.card,
              shape: const CircleBorder(),
            ),
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
        PlaylistCoverThumb(playlist: playlist, size: 200, radius: 28),
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

/// Play/shuffle controls. The play button plays/pauses the 30-second
/// preview of the playlist's top song (there's no full-track playback
/// engine yet); shuffle still just surfaces a "not available yet"
/// message.
class _PlaybackRow extends StatelessWidget {
  const _PlaybackRow({
    required this.isPlaying,
    required this.onPlayTap,
    required this.onShuffleTap,
  });

  final bool isPlaying;
  final VoidCallback onPlayTap;
  final VoidCallback onShuffleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: onPlayTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _PlaylistColors.tertiary,
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _PlaylistColors.background,
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 16),
        InkWell(
          onTap: onShuffleTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _PlaylistColors.cardBorder),
            ),
            child: const Icon(
              Icons.shuffle_rounded,
              color: _PlaylistColors.body,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the signed-in user can see the playlist but can't edit it
/// (a public, invited_only-edit playlist they're not a collaborator on).
/// Lets them ask the owner for edit rights — approving that request just
/// makes them a [PlaylistCollaborator], same mechanism as [_AccessDeniedState].
class _EditLockedBanner extends StatelessWidget {
  const _EditLockedBanner({
    required this.myRequest,
    required this.isRequesting,
    required this.onRequestAccess,
  });

  final PlaylistAccessRequest? myRequest;
  final bool isRequesting;
  final VoidCallback onRequestAccess;

  @override
  Widget build(BuildContext context) {
    final alreadyRequested = myRequest?.status == playlistAccessRequestPending;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 15, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'VIEW ONLY MODE',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Only invited collaborators can edit this playlist.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _PlaylistColors.muted),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: alreadyRequested || isRequesting
                ? null
                : onRequestAccess,
            style: TextButton.styleFrom(
              foregroundColor: _PlaylistColors.tertiary,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              alreadyRequested ? 'Request sent' : 'Request access to edit',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: alreadyRequested
                    ? _PlaylistColors.muted
                    : _PlaylistColors.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar stack (owner + collaborators) shown under the cover, with an
/// "Invite" pill for the owner. Purely presentational beyond the invite tap.
class _CollaboratorsRow extends StatelessWidget {
  const _CollaboratorsRow({
    required this.collaborators,
    required this.isOwner,
    required this.onInvite,
  });

  final List<PlaylistCollaborator> collaborators;
  final bool isOwner;
  final VoidCallback? onInvite;

  static const _maxShown = 4;
  static const _overlap = 22.0;
  static const _avatarSize = 32.0;

  @override
  Widget build(BuildContext context) {
    final shown = collaborators.take(_maxShown).toList();
    final overflow = collaborators.length - shown.length;
    final avatarSlots = shown.length + (overflow > 0 ? 1 : 0);
    final stackWidth = avatarSlots == 0
        ? 0.0
        : _avatarSize + (avatarSlots - 1) * _overlap;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (avatarSlots > 0)
          SizedBox(
            width: stackWidth,
            height: _avatarSize,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * _overlap,
                    child: _Avatar(email: shown[i].collaboratorEmail),
                  ),
                if (overflow > 0)
                  Positioned(
                    left: shown.length * _overlap,
                    child: Container(
                      width: _avatarSize,
                      height: _avatarSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _PlaylistColors.chip,
                        border: Border.fromBorderSide(
                          BorderSide(
                            color: _PlaylistColors.background,
                            width: 2,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '+$overflow',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _PlaylistColors.body,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (isOwner) ...[
          if (avatarSlots > 0) const SizedBox(width: 10),
          _InviteChip(onTap: onInvite),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _PlaylistColors.chip,
        border: Border.fromBorderSide(
          BorderSide(color: _PlaylistColors.background, width: 2),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        email.isNotEmpty ? email[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _PlaylistColors.headline,
        ),
      ),
    );
  }
}

class _InviteChip extends StatelessWidget {
  const _InviteChip({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _PlaylistColors.gradientStart,
              _PlaylistColors.gradientEnd,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_alt_1_rounded, size: 14, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'Invite',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the whole playlist when the signed-in user can't see
/// it at all (a private playlist they're not invited to) — the backend's
/// `PlaylistDetailView` 403s before returning anything else, so this is
/// the only state available to render.
class _AccessDeniedState extends StatelessWidget {
  const _AccessDeniedState({
    required this.myRequest,
    required this.isRequesting,
    required this.onRequestAccess,
    required this.onReturnHome,
  });

  final PlaylistAccessRequest? myRequest;
  final bool isRequesting;
  final VoidCallback onRequestAccess;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) {
    final status = myRequest?.status;
    final alreadyRequested = status == playlistAccessRequestPending;
    final wasDenied = status == playlistAccessRequestDenied;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _PlaylistColors.card,
                border: Border.all(color: _PlaylistColors.cardBorder, width: 2),
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 40,
                color: _PlaylistColors.body,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Private Playlist',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: _PlaylistColors.body,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              wasDenied ? 'Your request to join this playlist was declined.' : 'This playlist is private. Ask the owner to invite you to gain access.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _PlaylistColors.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: alreadyRequested
                      ? null
                      : const LinearGradient(
                          colors: [
                            _PlaylistColors.gradientStart,
                            _PlaylistColors.gradientEnd,
                          ],
                        ),
                  color: alreadyRequested ? _PlaylistColors.card : null,
                  border: alreadyRequested
                      ? Border.all(color: _PlaylistColors.cardBorder)
                      : null,
                ),
                child: ElevatedButton(
                  onPressed: alreadyRequested || isRequesting
                      ? null
                      : onRequestAccess,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: isRequesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          alreadyRequested
                              ? 'REQUEST SENT'
                              : (wasDenied
                                    ? 'REQUEST ACCESS AGAIN'
                                    : 'REQUEST ACCESS'),
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.6,
                            color: alreadyRequested
                                ? _PlaylistColors.muted
                                : Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: onReturnHome,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _PlaylistColors.body,
                  side: const BorderSide(color: _PlaylistColors.cardBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'RETURN HOME',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ),
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
          const Icon(
            Icons.music_off_rounded,
            size: 36,
            color: _PlaylistColors.muted,
          ),
          const SizedBox(height: 12),
          const Text(
            'No songs yet.',
            style: TextStyle(color: _PlaylistColors.body),
          ),
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
  const _SongRow({
    required this.song,
    required this.isPlaying,
    required this.onTogglePreview,
    this.dragHandle,
  });

  final PlaylistSong song;
  final bool isPlaying;
  final VoidCallback onTogglePreview;

  /// A [ReorderableDragStartListener]-wrapped handle icon, present only
  /// when this row is rendered inside an editable (reorderable) list.
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _PlaylistColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPlaying
              ? _PlaylistColors.tertiary
              : _PlaylistColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          _SongArt(
            url: song.songAlbumArtUrl,
            isPlaying: isPlaying,
            onTap: onTogglePreview,
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: _PlaylistColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (song.songDurationSeconds != null) ...[
            const SizedBox(width: 8),
            Text(
              _formatDuration(song.songDurationSeconds!),
              style: const TextStyle(
                fontSize: 12,
                color: _PlaylistColors.muted,
              ),
            ),
          ],
          if (dragHandle != null) ...[const SizedBox(width: 8), dragHandle!],
        ],
      ),
    );
  }
}

/// Cover art for a playlist row. Tapping it plays/pauses the song's
/// 30-second preview — same interaction as the search screen's artwork.
/// There's no full-track playback yet, so this preview is the only way
/// to actually hear a song that's already in the playlist.
class _SongArt extends StatelessWidget {
  const _SongArt({
    required this.url,
    required this.isPlaying,
    required this.onTap,
  });

  final String url;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: url.isEmpty
                  ? Container(
                      color: _PlaylistColors.chip,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: _PlaylistColors.headline,
                        size: 20,
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: _PlaylistColors.chip,
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: _PlaylistColors.headline,
                          size: 20,
                        ),
                      ),
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black.withValues(alpha: isPlaying ? 0.35 : 0.15),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
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
            const Icon(
              Icons.wifi_off_rounded,
              color: _PlaylistColors.muted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _PlaylistColors.body),
            ),
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
