import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../playlists/playlist_api.dart';
import '../playlists/playlist_models.dart';
import 'event_api.dart';

class _SuggestColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// Deezer/Audius-backed song search for an event's queue, using the same
/// search endpoint and the same "FULL SONG" / "30 SEC PREVIEW" badge as
/// playlist add-song — see [_PlaybackBadge]. Before the user types
/// anything, it shows a "popular now" list (`PlaylistApi.fetchTrending`)
/// combining Audius's trending full tracks and Deezer's top chart, same
/// source priority as search; typing switches to a debounced search
/// against the query, and clearing the query falls back to the
/// already-fetched trending list rather than an empty prompt. Unlike the
/// playlist screen, there's no tap-to-preview audio here: the user opening
/// this is still inside the event, whose own track is already playing in
/// the background (see `EventDetailScreen`), so there's no way for them to
/// actually hear a separate preview clip over it. Adding a song sends it
/// through `POST /events/<id>/queue/` instead of a playlist's add-song
/// endpoint.
class SuggestTrackScreen extends StatefulWidget {
  const SuggestTrackScreen({super.key, required this.eventId});
  final int eventId;

  @override
  State<SuggestTrackScreen> createState() => _SuggestTrackScreenState();
}

class _SuggestTrackScreenState extends State<SuggestTrackScreen> {
  final _eventApi = EventApi();
  final _trackApi = PlaylistApi();
  final _tokenStorage = TokenStorage();
  final _controller = TextEditingController();
  Timer? _debounce;

  /// Deezer's top chart, fetched once on screen load and shown before the
  /// user types anything. Kept separate from [_searchResults] so clearing
  /// the search field can fall back to it instantly, with no refetch.
  List<TrackSearchResult>? _trending;
  List<TrackSearchResult>? _searchResults;
  final Set<String> _adding = <String>{};
  final Set<String> _added = <String>{};
  var _isLoading = false;
  String? _error;

  bool get _isSearching => _controller.text.trim().isNotEmpty;
  List<TrackSearchResult>? get _results =>
      _isSearching ? _searchResults : _trending;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await _trackApi.fetchTrending();
      if (!mounted) return;
      setState(() {
        _trending = results;
        _isLoading = false;
      });
    } on SessionExpiredException {
      await _signOut();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error.message;
        });
      }
    }
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
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
      final results = await _trackApi.searchTracks(query);
      if (!mounted || query != _controller.text) return;
      setState(() {
        _searchResults = results;
        _isLoading = false;
        _error = null;
      });
    } on SessionExpiredException {
      await _signOut();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _addSong(TrackSearchResult track) async {
    final key = track.externalId.isEmpty
        ? '${track.title}\u0000${track.artist}'
        : track.externalId;
    if (_adding.contains(key) || _added.contains(key)) return;
    setState(() => _adding.add(key));
    try {
      await _eventApi.addToQueue(
        widget.eventId,
        title: track.title,
        artist: track.artist,
        durationSeconds: track.durationSeconds,
        externalId: track.externalId,
        albumArtUrl: track.albumArtUrl,
        previewUrl: track.previewUrl,
        playbackType: track.playbackType,
      );
      if (!mounted) return;
      setState(() => _added.add(key));
      _showSnack('Added "${track.title}" to the event queue.');
    } on SessionExpiredException {
      await _signOut();
    } on ApiException catch (error) {
      _showSnack(error.message);
    } finally {
      if (mounted) setState(() => _adding.remove(key));
    }
  }

  Future<void> _signOut() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _SuggestColors.background,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: _SuggestColors.body,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    style: const TextStyle(color: _SuggestColors.body),
                    decoration: InputDecoration(
                      hintText: 'Search for a song to add...',
                      hintStyle: const TextStyle(color: _SuggestColors.muted),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _SuggestColors.tertiary,
                      ),
                      filled: true,
                      fillColor: _SuggestColors.card,
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

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _SuggestColors.tertiary),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: _SuggestColors.muted),
        ),
      );
    }
    final results = _results ?? const [];
    if (results.isEmpty) {
      return Center(
        child: Text(
          _isSearching ? 'No songs found.' : 'Nothing trending right now.',
          style: const TextStyle(color: _SuggestColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              _isSearching ? 'RESULTS' : 'POPULAR NOW',
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: _SuggestColors.tertiary,
              ),
            ),
          );
        }
        final track = results[index - 1];
        final key = track.externalId.isEmpty
            ? '${track.title}\u0000${track.artist}'
            : track.externalId;
        return _SongResultRow(
          track: track,
          isAdding: _adding.contains(key),
          isAdded: _added.contains(key),
          onAdd: () => _addSong(track),
        );
      },
    );
  }
}

class _SongResultRow extends StatelessWidget {
  const _SongResultRow({
    required this.track,
    required this.isAdding,
    required this.isAdded,
    required this.onAdd,
  });
  final TrackSearchResult track;
  final bool isAdding;
  final bool isAdded;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _SuggestColors.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _SuggestColors.border),
    ),
    child: Row(
      children: [
        _Art(track: track),
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
                  color: _SuggestColors.body,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: _SuggestColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              _PlaybackBadge(isFullTrack: track.hasFullPlayback),
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
              color: _SuggestColors.tertiary,
            ),
          )
        else if (isAdded)
          const Icon(Icons.check_circle_rounded, color: _SuggestColors.tertiary)
        else
          _AddButton(onTap: onAdd),
      ],
    ),
  );
}

/// Mirrors the same badge on the playlist add-song search screen
/// (`add_song_search_screen.dart`'s `_PlaybackBadge`) so a suggester sees
/// the same "FULL SONG" vs "30 SEC PREVIEW" signal there — it just can't
/// act on it here with an audio preview (see [SuggestTrackScreen] docs).
class _PlaybackBadge extends StatelessWidget {
  const _PlaybackBadge({required this.isFullTrack});

  final bool isFullTrack;

  @override
  Widget build(BuildContext context) {
    final color = isFullTrack ? _SuggestColors.tertiary : _SuggestColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        isFullTrack ? 'FULL SONG' : '30 SEC PREVIEW',
        style: TextStyle(
          color: color,
          fontFamily: 'Sora',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.track});
  final TrackSearchResult track;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: track.albumArtUrl.isEmpty
          ? Container(
              color: _SuggestColors.border,
              child: const Icon(
                Icons.music_note_rounded,
                color: _SuggestColors.tertiary,
              ),
            )
          : Image.network(
              track.albumArtUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: _SuggestColors.border,
                child: const Icon(
                  Icons.music_note_rounded,
                  color: _SuggestColors.tertiary,
                ),
              ),
            ),
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_SuggestColors.gradientStart, _SuggestColors.gradientEnd],
        ),
      ),
      child: const Text(
        'Add',
        style: TextStyle(
          fontFamily: 'Sora',
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    ),
  );
}
