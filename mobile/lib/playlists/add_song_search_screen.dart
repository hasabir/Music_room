import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import 'playlist_api.dart';
import 'playlist_models.dart';

class _AddSongColors {
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

/// Search-and-add screen for a playlist's songs. Mirrors
/// `add_collaborators_screen.dart`'s debounced-search pattern, but against
/// `GET /api/v1/tracks/search/` (`TrackSearchView`, which proxies Deezer)
/// instead of the user search endpoint. Tapping a result's artwork plays
/// its 30-second `preview_url` straight from Deezer's CDN; only one
/// preview plays at a time. Tapping "Add" sends the track's
/// title/artist/duration/external id to `PlaylistApi.addSong` — the exact
/// same call a manually-typed song would make.
class AddSongSearchScreen extends StatefulWidget {
  const AddSongSearchScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<AddSongSearchScreen> createState() => _AddSongSearchScreenState();
}

class _AddSongSearchScreenState extends State<AddSongSearchScreen> {
  final _playlistApi = PlaylistApi();
  final _tokenStorage = TokenStorage();
  final _controller = TextEditingController();
  final _previewPlayer = AudioPlayer();
  Timer? _debounce;
  StreamSubscription<void>? _completeSub;

  List<TrackSearchResult>? _results;
  var _isLoading = false;
  String? _error;

  String? _playingExternalId;
  var _addedExternalIds = <String>{};
  var _addingExternalIds = <String>{};

  /// Every song successfully added this screen, in the order they were
  /// added — handed back to [PlaylistDetailScreen] on pop so it can drop
  /// them straight into its own list instead of re-fetching from the
  /// backend just to learn what it already knows.
  final _addedSongs = <PlaylistSong>[];

  @override
  void initState() {
    super.initState();
    _completeSub = _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingExternalId = null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _completeSub?.cancel();
    _previewPlayer.dispose();
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
      final results = await _playlistApi.searchTracks(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _error = null;
      });
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _onTogglePreview(TrackSearchResult track) async {
    if (track.previewUrl.isEmpty) {
      _showSnack('No preview available for this track.');
      return;
    }

    if (_playingExternalId == track.externalId) {
      await _previewPlayer.stop();
      if (!mounted) return;
      setState(() => _playingExternalId = null);
      return;
    }

    try {
      final previewUrl = track.externalId.isEmpty
          ? track.previewUrl
          : await _playlistApi.resolvePreviewUrl(track.externalId);
      if (previewUrl.isEmpty) throw StateError('No preview URL available.');
      await _previewPlayer.stop();
      await _previewPlayer.play(UrlSource(previewUrl));
      if (!mounted) return;
      setState(() => _playingExternalId = track.externalId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _playingExternalId = null);
      _showSnack('Could not play preview.');
    }
  }

  Future<void> _onAdd(TrackSearchResult track) async {
    if (_addedExternalIds.contains(track.externalId) ||
        _addingExternalIds.contains(track.externalId)) {
      return;
    }

    setState(
      () => _addingExternalIds = {..._addingExternalIds, track.externalId},
    );
    try {
      final playlistSong = await _playlistApi.addSong(
        widget.playlistId,
        title: track.title,
        artist: track.artist,
        durationSeconds: track.durationSeconds,
        externalId: track.externalId,
        albumArtUrl: track.albumArtUrl,
        previewUrl: track.previewUrl,
      );
      if (!mounted) return;
      setState(() {
        _addedExternalIds = {..._addedExternalIds, track.externalId};
        _addedSongs.add(playlistSong);
      });
      _showSnack('Added "${track.title}" to the playlist.');
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      _showSnack(error.message);
    } finally {
      if (mounted) {
        setState(
          () =>
              _addingExternalIds = {..._addingExternalIds}
                ..remove(track.externalId),
        );
      }
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_addedSongs);
      },
      child: Scaffold(
        backgroundColor: _AddSongColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(_addedSongs),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: _AddSongColors.body,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: _onQueryChanged,
                        style: const TextStyle(color: _AddSongColors.body),
                        decoration: InputDecoration(
                          hintText: 'Search for a song to add...',
                          hintStyle: const TextStyle(
                            color: _AddSongColors.muted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _AddSongColors.tertiary,
                          ),
                          filled: true,
                          fillColor: _AddSongColors.card,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
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
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _AddSongColors.headline),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: _AddSongColors.muted),
        ),
      );
    }

    final results = _results;
    if (results == null) {
      return const Center(
        child: Text(
          'Search by title or artist to find a song.',
          style: TextStyle(color: _AddSongColors.muted),
        ),
      );
    }

    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No tracks found.',
          style: TextStyle(color: _AddSongColors.muted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final track = results[index];
        return _TrackRow(
          track: track,
          isPlaying: _playingExternalId == track.externalId,
          isAdded: _addedExternalIds.contains(track.externalId),
          isAdding: _addingExternalIds.contains(track.externalId),
          onTogglePreview: () => _onTogglePreview(track),
          onAdd: () => _onAdd(track),
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.isPlaying,
    required this.isAdded,
    required this.isAdding,
    required this.onTogglePreview,
    required this.onAdd,
  });

  final TrackSearchResult track;
  final bool isPlaying;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback onTogglePreview;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTogglePreview,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _AddSongColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isPlaying
                  ? _AddSongColors.tertiary
                  : _AddSongColors.border,
            ),
          ),
          child: Row(
            children: [
              _AlbumArt(
                track: track,
                isPlaying: isPlaying,
                onTap: onTogglePreview,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: _AddSongColors.body,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _AddSongColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isAdding)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _AddSongColors.headline,
                  ),
                )
              else if (isAdded)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 22,
                  color: _AddSongColors.tertiary,
                )
              else
                _GradientPillButton(label: 'Add', onTap: onAdd),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({
    required this.track,
    required this.isPlaying,
    required this.onTap,
  });

  final TrackSearchResult track;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: track.albumArtUrl.isEmpty
                  ? Container(
                      color: _AddSongColors.border,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: _AddSongColors.headline,
                        size: 20,
                      ),
                    )
                  : Image.network(
                      track.albumArtUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: _AddSongColors.border,
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: _AddSongColors.headline,
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
                size: 22,
              ),
            ),
          ],
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
            colors: [_AddSongColors.gradientStart, _AddSongColors.gradientEnd],
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
