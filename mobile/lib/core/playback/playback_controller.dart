import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The app-wide preview player. It deliberately lives beyond any individual
/// route so audio keeps playing while the listener browses the app.
class PlaybackController {
  PlaybackController._() {
    _player.onPositionChanged.listen((position) {
      _setState(_state.copyWith(position: position));
    });
    _player.onDurationChanged.listen((duration) {
      _setState(_state.copyWith(duration: duration));
    });
    _player.onPlayerStateChanged.listen((state) {
      _setState(_state.copyWith(isPlaying: state == PlayerState.playing));
    });
    _player.onPlayerComplete.listen((_) {
      final trackKey = _state.trackKey;
      _setState(_state.copyWith(isPlaying: false, position: _state.duration));
      if (trackKey != null) _completedController.add(trackKey);
    });
  }

  static final instance = PlaybackController._();

  final _player = AudioPlayer();
  final _completedController = StreamController<String>.broadcast();
  final state = ValueNotifier(const PlaybackState());

  /// The playlist detail route currently visible to the listener, if any.
  /// This prevents the mini player from pushing a duplicate copy of it.
  int? visiblePlaylistId;

  PlaybackState get _state => state.value;
  Stream<String> get onCompleted => _completedController.stream;

  Future<void> play({
    required String url,
    required String trackKey,
    required String title,
    required String artist,
    required String artworkUrl,
  }) async {
    await _player.stop();
    _setState(
      PlaybackState(
        trackKey: trackKey,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
      ),
    );
    await _player.play(UrlSource(url));
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.resume();

  Future<void> toggle() => _state.isPlaying ? pause() : resume();

  Future<void> stop() async {
    await _player.stop();
    _setState(const PlaybackState());
  }

  Future<void> seek(Duration position) async {
    final duration = _state.duration;
    if (duration == Duration.zero) return;
    final clamped = position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    await _player.seek(clamped);
    _setState(_state.copyWith(position: clamped));
  }

  Future<void> skipBy(Duration offset) => seek(_state.position + offset);

  void _setState(PlaybackState next) {
    if (state.value != next) state.value = next;
  }
}

@immutable
class PlaybackState {
  const PlaybackState({
    this.trackKey,
    this.title = '',
    this.artist = '',
    this.artworkUrl = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
  });

  final String? trackKey;
  final String title;
  final String artist;
  final String artworkUrl;
  final Duration position;
  final Duration duration;
  final bool isPlaying;

  bool get hasTrack => trackKey != null;

  PlaybackState copyWith({
    String? trackKey,
    String? title,
    String? artist,
    String? artworkUrl,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
  }) => PlaybackState(
    trackKey: trackKey ?? this.trackKey,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    isPlaying: isPlaying ?? this.isPlaying,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.trackKey == trackKey &&
      other.title == title &&
      other.artist == artist &&
      other.artworkUrl == artworkUrl &&
      other.position == position &&
      other.duration == duration &&
      other.isPlaying == isPlaying;

  @override
  int get hashCode => Object.hash(
    trackKey,
    title,
    artist,
    artworkUrl,
    position,
    duration,
    isPlaying,
  );
}
