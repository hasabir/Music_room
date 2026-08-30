import '../auth/auth_api.dart';
import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import 'playlist_models.dart';

/// Talks to the backend's `playlists` endpoints (`/api/v1/playlists/...`).
///
/// Mirrors [ProfileApi]'s access-token-with-refresh-and-retry handling, but
/// delegates the actual refresh call to an [AuthApi] instance rather than
/// re-implementing it.
class PlaylistApi {
  PlaylistApi({ApiClient? apiClient, TokenStorage? tokenStorage, AuthApi? authApi})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? TokenStorage(),
      _authApi = authApi ?? AuthApi(tokenStorage: tokenStorage);

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final AuthApi _authApi;

  /// Lists public playlists, plus private playlists the signed-in user
  /// owns or collaborates on.
  Future<List<Playlist>> listPlaylists() async {
    final response = await _authorizedGetList(ApiConfig.playlistsUri());
    return response.map((json) => Playlist.fromJson(json)).toList();
  }

  /// Creates a new playlist. The signed-in user automatically becomes the
  /// owner.
  Future<Playlist> createPlaylist({
    required String title,
    String? visibility,
    String? editPermission,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (visibility != null) 'visibility': visibility,
      if (editPermission != null) 'edit_permission': editPermission,
    };
    final response = await _authorizedPost(ApiConfig.playlistsUri(), body: body);
    return Playlist.fromJson(response);
  }

  /// Fetches one playlist's details.
  Future<Playlist> getPlaylist(int playlistId) async {
    final response = await _authorizedGet(ApiConfig.playlistDetailUri(playlistId));
    return Playlist.fromJson(response);
  }

  /// Partially updates a playlist. Only the owner may do this. Only
  /// non-null parameters are sent, so callers can update a subset of
  /// fields.
  Future<Playlist> updatePlaylist(
    int playlistId, {
    String? title,
    String? visibility,
    String? editPermission,
  }) async {
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (visibility != null) 'visibility': visibility,
      if (editPermission != null) 'edit_permission': editPermission,
    };
    final response = await _authorizedPatch(
      ApiConfig.playlistDetailUri(playlistId),
      body: body,
    );
    return Playlist.fromJson(response);
  }

  /// Deletes a playlist and all of its songs. Only the owner may do this.
  Future<void> deletePlaylist(int playlistId) async {
    await _authorizedDelete(ApiConfig.playlistDetailUri(playlistId));
  }

  /// Lists all songs in a playlist, in order.
  Future<List<PlaylistSong>> listSongs(int playlistId) async {
    final response = await _authorizedGetList(ApiConfig.playlistSongsUri(playlistId));
    return response.map((json) => PlaylistSong.fromJson(json)).toList();
  }

  /// Adds a new song to the end of the playlist. Reuses an existing
  /// catalog song if the same title/artist already exists.
  Future<PlaylistSong> addSong(
    int playlistId, {
    required String title,
    required String artist,
    int? durationSeconds,
    String? externalId,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'artist': artist,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (externalId != null) 'external_id': externalId,
    };
    final response = await _authorizedPost(
      ApiConfig.playlistSongsUri(playlistId),
      body: body,
    );
    return PlaylistSong.fromJson(response);
  }

  /// Removes a song from the playlist. Positions of all songs after it
  /// automatically shift down to close the gap.
  Future<void> removeSong(int playlistId, int playlistSongId) async {
    await _authorizedDelete(ApiConfig.playlistSongDetailUri(playlistId, playlistSongId));
  }

  /// Moves a song to [newPosition] (zero-based). Every song in between
  /// shifts to make room; out-of-range values are clamped server-side.
  Future<PlaylistSong> moveSong(
    int playlistId,
    int playlistSongId, {
    required int newPosition,
  }) async {
    final response = await _authorizedPost(
      ApiConfig.playlistSongMoveUri(playlistId, playlistSongId),
      body: {'new_position': newPosition},
    );
    return PlaylistSong.fromJson(response);
  }

  /// Lists everyone invited to a playlist.
  Future<List<PlaylistCollaborator>> listCollaborators(int playlistId) async {
    final response = await _authorizedGetList(
      ApiConfig.playlistCollaboratorsUri(playlistId),
    );
    return response.map((json) => PlaylistCollaborator.fromJson(json)).toList();
  }

  /// Invites [userId] to a private playlist, or grants them edit rights
  /// on an invited_only-edit playlist. Owner only.
  Future<PlaylistCollaborator> inviteCollaborator(int playlistId, int userId) async {
    final response = await _authorizedPost(
      ApiConfig.playlistCollaboratorsUri(playlistId),
      body: {'user_id': userId},
    );
    return PlaylistCollaborator.fromJson(response);
  }

  /// Revokes an invitation / removes a collaborator from the playlist.
  /// Owner only.
  Future<void> removeCollaborator(int playlistId, int userId) async {
    await _authorizedDelete(ApiConfig.playlistCollaboratorDetailUri(playlistId, userId));
  }

  Future<Map<String, dynamic>> _authorizedGet(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.get(uri, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.get(uri, accessToken: refreshedToken);
    }
  }

  Future<Map<String, dynamic>> _authorizedPost(
    Uri uri, {
    required Map<String, dynamic> body,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.post(uri, body: body, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.post(uri, body: body, accessToken: refreshedToken);
    }
  }

  Future<Map<String, dynamic>> _authorizedPatch(
    Uri uri, {
    required Map<String, dynamic> body,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.patch(uri, body: body, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.patch(uri, body: body, accessToken: refreshedToken);
    }
  }

  Future<void> _authorizedDelete(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      await _apiClient.delete(uri, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      await _apiClient.delete(uri, accessToken: refreshedToken);
    }
  }

  /// Playlist list endpoints return Django REST Framework's paginated
  /// `{"count", "next", "results"}` shape rather than a bare JSON array, so
  /// they need [ApiClient.getList] instead of [ApiClient.get].
  Future<List<Map<String, dynamic>>> _authorizedGetList(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.getList(uri, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.getList(uri, accessToken: refreshedToken);
    }
  }

  Future<String> _refreshOrThrow() async {
    try {
      return await _authApi.refreshAccessToken();
    } on ApiException {
      await _tokenStorage.clear();
      throw SessionExpiredException();
    }
  }
}
