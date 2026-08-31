import 'package:flutter/material.dart';

import '../../playlists/playlist_detail_screen.dart';
import '../navigation/app_navigator.dart';
import 'playback_controller.dart';

/// Persistent compact player displayed above the app's navigation.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackController.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: playback.isNowPlayingScreenVisible,
      builder: (context, isNowPlayingScreenVisible, _) {
        if (isNowPlayingScreenVisible) return const SizedBox.shrink();
        return _buildForState(playback);
      },
    );
  }

  Widget _buildForState(PlaybackController playback) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: playback.state,
      builder: (context, state, _) {
        // Event playback has no controls of its own (voting is the only
        // control, see `PlaybackState.isEventTrack`) and is already shown
        // front-and-center by the event's own "Now Playing" card, so the
        // floating mini player would just be a redundant duplicate.
        if (!state.hasTrack || state.isEventTrack) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 76),
            child: Material(
              color: const Color(0xFF25242F),
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openSource(context, state),
                child: SizedBox(
                  height: 66,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            _Artwork(url: state.artworkUrl, size: 52),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFEDEBFA),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    state.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFAAA7B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _navigator.push(
                                MaterialPageRoute(
                                  builder: (_) => const NowPlayingScreen(),
                                ),
                              ),
                              icon: const Icon(
                                Icons.equalizer_rounded,
                                color: Color(0xFFEDEBFA),
                              ),
                            ),
                            IconButton(
                              onPressed: playback.toggle,
                              icon: Icon(
                                state.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: const Color(0xFFEDEBFA),
                              ),
                            ),
                            IconButton(
                              onPressed: playback.stop,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFAAA7B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      LinearProgressIndicator(
                        value: _progress(state),
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF9B9DFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Never called for an event track — the mini player doesn't render for
  // one in the first place (see the isEventTrack check in build()), so
  // this only ever needs to handle a playlist preview.
  void _openSource(BuildContext context, PlaybackState state) {
    final trackKey = state.trackKey ?? '';

    final playlistMatch = RegExp(r'^playlist:(\d+):').firstMatch(trackKey);
    final playlistId = playlistMatch == null
        ? null
        : int.tryParse(playlistMatch.group(1)!);
    if (playlistId != null) {
      if (PlaybackController.instance.visiblePlaylistId == playlistId) return;
      _navigator.push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
        ),
      );
      return;
    }

    _navigator.push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  NavigatorState get _navigator {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      throw StateError('The app navigator is not ready.');
    }
    return navigator;
  }
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final _playback = PlaybackController.instance;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: setting this during initState (still mid-build for
    // the route being pushed) trips ValueNotifier's "setState() called
    // during build" guard, which the framework silently swallows — so the
    // mini player's listener never fires and it never actually hides.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playback.isNowPlayingScreenVisible.value = true;
    });
  }

  @override
  void dispose() {
    // Same reasoning as initState: element unmounting runs while the tree
    // is locked, so this has to land on the next frame rather than firing
    // ValueNotifier's listeners synchronously here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playback.isNowPlayingScreenVisible.value = false;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = _playback;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E15),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFFEDEBFA),
        title: const Text('Now Playing'),
      ),
      body: ValueListenableBuilder<PlaybackState>(
        valueListenable: playback.state,
        builder: (context, state, _) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(child: _Artwork(url: state.artworkUrl, size: 250)),
                const SizedBox(height: 36),
                Text(
                  state.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEDEBFA),
                    fontFamily: 'Sora',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  state.artist,
                  style: const TextStyle(color: Color(0xFFAAA7B8)),
                ),
                const SizedBox(height: 20),
                Slider(
                  value: _progress(state),
                  // Events auto-play the vote leader with no seeking —
                  // voting is the only control (see `PlaybackState.isEventTrack`).
                  onChanged: state.isEventTrack || state.duration == Duration.zero
                      ? null
                      : (value) => playback.seek(
                          Duration(
                            milliseconds:
                                (state.duration.inMilliseconds * value).round(),
                          ),
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(state.position),
                      style: const TextStyle(color: Color(0xFFAAA7B8)),
                    ),
                    Text(
                      _formatTime(state.duration),
                      style: const TextStyle(color: Color(0xFFAAA7B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (state.isEventTrack)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Playing live for everyone at this event — vote to change what plays next.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFAAA7B8)),
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 34,
                        onPressed: () =>
                            playback.skipBy(const Duration(seconds: -10)),
                        icon: const Icon(Icons.replay_10_rounded),
                      ),
                      FilledButton(
                        onPressed: playback.toggle,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(18),
                        ),
                        child: Icon(
                          state.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 34,
                        ),
                      ),
                      IconButton(
                        iconSize: 34,
                        onPressed: () =>
                            playback.skipBy(const Duration(seconds: 10)),
                        icon: const Icon(Icons.forward_10_rounded),
                      ),
                    ],
                  ),
                const Spacer(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size > 100 ? 22 : 14),
    child: SizedBox(
      width: size,
      height: size,
      child: url.isEmpty
          ? const ColoredBox(
              color: Color(0xFF383747),
              child: Icon(Icons.music_note_rounded, color: Color(0xFFC0C1FF)),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFF383747),
                child: Icon(Icons.music_note_rounded, color: Color(0xFFC0C1FF)),
              ),
            ),
    ),
  );
}

double _progress(PlaybackState state) {
  if (state.duration == Duration.zero) return 0;
  return (state.position.inMilliseconds / state.duration.inMilliseconds)
      .clamp(0, 1)
      .toDouble();
}

String _formatTime(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
