import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
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

/// Deezer-backed song search for an event's queue. It uses the same search
/// and preview flow as playlist add-song, but sends the selected song through
/// `POST /events/<id>/queue/` instead.
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
  final _previewPlayer = AudioPlayer();
  Timer? _debounce;
  StreamSubscription<void>? _previewComplete;
  List<TrackSearchResult>? _results;
  final Set<String> _adding = <String>{};
  final Set<String> _added = <String>{};
  String? _playingExternalId;
  var _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _previewComplete = _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingExternalId = null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _previewComplete?.cancel();
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
      final results = await _trackApi.searchTracks(query);
      if (!mounted || query != _controller.text) return;
      setState(() {
        _results = results;
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

  Future<void> _togglePreview(TrackSearchResult track) async {
    if (track.previewUrl.isEmpty) {
      return _showSnack('No preview is available for this song.');
    }
    if (_playingExternalId == track.externalId) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingExternalId = null);
      return;
    }
    try {
      final url = track.externalId.isEmpty
          ? track.previewUrl
          : await _trackApi.resolvePreviewUrl(track.externalId);
      if (url.isEmpty) throw StateError('No preview URL available.');
      await _previewPlayer.stop();
      await _previewPlayer.play(UrlSource(url));
      if (mounted) setState(() => _playingExternalId = track.externalId);
    } catch (_) {
      _showSnack('Could not play this preview.');
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
    final results = _results;
    if (results == null) {
      return const Center(
        child: Text(
          'Search by title or artist to add a song.',
          style: TextStyle(color: _SuggestColors.muted),
        ),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No songs found.',
          style: TextStyle(color: _SuggestColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final track = results[index];
        final key = track.externalId.isEmpty
            ? '${track.title}\u0000${track.artist}'
            : track.externalId;
        return _SongResultRow(
          track: track,
          isPlaying: _playingExternalId == track.externalId,
          isAdding: _adding.contains(key),
          isAdded: _added.contains(key),
          onPreview: () => _togglePreview(track),
          onAdd: () => _addSong(track),
        );
      },
    );
  }
}

class _SongResultRow extends StatelessWidget {
  const _SongResultRow({
    required this.track,
    required this.isPlaying,
    required this.isAdding,
    required this.isAdded,
    required this.onPreview,
    required this.onAdd,
  });
  final TrackSearchResult track;
  final bool isPlaying;
  final bool isAdding;
  final bool isAdded;
  final VoidCallback onPreview;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _SuggestColors.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isPlaying ? _SuggestColors.tertiary : _SuggestColors.border,
      ),
    ),
    child: Row(
      children: [
        InkWell(
          onTap: onPreview,
          borderRadius: BorderRadius.circular(12),
          child: _Art(track: track, isPlaying: isPlaying),
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

class _Art extends StatelessWidget {
  const _Art({required this.track, required this.isPlaying});
  final TrackSearchResult track;
  final bool isPlaying;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
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
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
          ),
        ),
      ],
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
