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
  PlaylistApi({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
    AuthApi? authApi,
  }) : _apiClient = apiClient ?? ApiClient(),
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
    String? description,
    String? visibility,
    String? editPermission,
    String? coverPreset,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      if (visibility != null) 'visibility': visibility,
      if (editPermission != null) 'edit_permission': editPermission,
      if (coverPreset != null) 'cover_preset': coverPreset,
    };
    final response = await _authorizedPost(
      ApiConfig.playlistsUri(),
      body: body,
    );
    return Playlist.fromJson(response);
  }

  /// Fetches one playlist's details.
  Future<Playlist> getPlaylist(int playlistId) async {
    final response = await _authorizedGet(
      ApiConfig.playlistDetailUri(playlistId),
    );
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
    String? coverPreset,
  }) async {
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (visibility != null) 'visibility': visibility,
      if (editPermission != null) 'edit_permission': editPermission,
      if (coverPreset != null) 'cover_preset': coverPreset,
    };
    final response = await _authorizedPatch(
      ApiConfig.playlistDetailUri(playlistId),
      body: body,
    );
    return Playlist.fromJson(response);
  }

  /// Uploads a custom cover photo from the file at [filePath], replacing
  /// `Playlist.cover_image` (and clearing any preset — the backend only
  /// keeps one). Sent as `multipart/form-data` since the field is an
  /// image, not JSON-representable. Owner only.
  Future<Playlist> uploadPlaylistCoverImage(
    int playlistId,
    String filePath,
  ) async {
    final response = await _authorizedPatchMultipartFile(
      ApiConfig.playlistDetailUri(playlistId),
      fieldName: 'cover_image',
      filePath: filePath,
    );
    return Playlist.fromJson(response);
  }

  /// Deletes a playlist and all of its songs. Only the owner may do this.
  Future<void> deletePlaylist(int playlistId) async {
    await _authorizedDelete(ApiConfig.playlistDetailUri(playlistId));
  }

  /// Lists all songs in a playlist, in order.
  Future<List<PlaylistSong>> listSongs(int playlistId) async {
    final response = await _authorizedGetList(
      ApiConfig.playlistSongsUri(playlistId),
    );
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
    String? albumArtUrl,
    String? previewUrl,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'artist': artist,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (externalId != null) 'external_id': externalId,
      if (albumArtUrl != null) 'album_art_url': albumArtUrl,
      if (previewUrl != null) 'preview_url': previewUrl,
    };
    final response = await _authorizedPost(
      ApiConfig.playlistSongsUri(playlistId),
      body: body,
    );
    return PlaylistSong.fromJson(response);
  }

  /// Searches Deezer (via the backend's proxy) for tracks matching [query].
  /// Each result carries a 30-second `previewUrl` for in-app preview and
  /// the exact fields [addSong] needs to add it to a playlist.
  Future<List<TrackSearchResult>> searchTracks(String query) async {
    final response = await _authorizedGetList(ApiConfig.trackSearchUri(query));
    return response.map((json) => TrackSearchResult.fromJson(json)).toList();
  }

  /// Gets a newly signed Deezer preview URL just before playback. Deezer's
  /// CDN URLs expire, so playlist records must not be played directly.
  Future<String> resolvePreviewUrl(String externalId) async {
    final response = await _authorizedGet(
      ApiConfig.trackPreviewUri(externalId),
    );
    return response['preview_url'] as String? ?? '';
  }

  /// Removes a song from the playlist. Positions of all songs after it
  /// automatically shift down to close the gap.
  Future<void> removeSong(int playlistId, int playlistSongId) async {
    await _authorizedDelete(
      ApiConfig.playlistSongDetailUri(playlistId, playlistSongId),
    );
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
  Future<PlaylistCollaborator> inviteCollaborator(
    int playlistId,
    int userId,
  ) async {
    final response = await _authorizedPost(
      ApiConfig.playlistCollaboratorsUri(playlistId),
      body: {'user_id': userId},
    );
    return PlaylistCollaborator.fromJson(response);
  }

  /// Revokes an invitation / removes a collaborator from the playlist.
  /// Owner only.
  Future<void> removeCollaborator(int playlistId, int userId) async {
    await _authorizedDelete(
      ApiConfig.playlistCollaboratorDetailUri(playlistId, userId),
    );
  }

  /// Requests collaborator access to a playlist you can't currently see
  /// (private) or can't edit (invited_only). Returns the existing pending
  /// request if you already have one.
  Future<PlaylistAccessRequest> requestAccess(int playlistId) async {
    final response = await _authorizedPost(
      ApiConfig.playlistAccessRequestsUri(playlistId),
      body: const {},
    );
    return PlaylistAccessRequest.fromJson(response);
  }

  /// The signed-in user's most recent access request for [playlistId], or
  /// `null` if they've never requested access. Works even without access
  /// to the playlist — that's the point.
  Future<PlaylistAccessRequest?> getMyAccessRequest(int playlistId) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    Future<Map<String, dynamic>> attempt(String token) => _apiClient.get(
      ApiConfig.playlistAccessRequestMineUri(playlistId),
      accessToken: token,
    );

    try {
      final response = await attempt(accessToken);
      return PlaylistAccessRequest.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      try {
        final response = await attempt(refreshedToken);
        return PlaylistAccessRequest.fromJson(response);
      } on ApiException catch (retryError) {
        if (retryError.statusCode == 404) return null;
        rethrow;
      }
    }
  }

  /// Lists every access request ever made for this playlist. Owner only.
  Future<List<PlaylistAccessRequest>> listAccessRequests(int playlistId) async {
    final response = await _authorizedGetList(
      ApiConfig.playlistAccessRequestsUri(playlistId),
    );
    return response
        .map((json) => PlaylistAccessRequest.fromJson(json))
        .toList();
  }

  /// Approves or denies an access request. Approving adds the requester as
  /// a collaborator. Owner only.
  Future<PlaylistAccessRequest> decideAccessRequest(
    int playlistId,
    int requestId, {
    required bool approve,
  }) async {
    final response = await _authorizedPost(
      ApiConfig.playlistAccessRequestDecideUri(playlistId, requestId),
      body: {'approve': approve},
    );
    return PlaylistAccessRequest.fromJson(response);
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
      return await _apiClient.post(
        uri,
        body: body,
        accessToken: refreshedToken,
      );
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
      return await _apiClient.patch(
        uri,
        body: body,
        accessToken: refreshedToken,
      );
    }
  }

  Future<Map<String, dynamic>> _authorizedPatchMultipartFile(
    Uri uri, {
    required String fieldName,
    required String filePath,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.patchMultipartFile(
        uri,
        fieldName: fieldName,
        filePath: filePath,
        accessToken: accessToken,
      );
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.patchMultipartFile(
        uri,
        fieldName: fieldName,
        filePath: filePath,
        accessToken: refreshedToken,
      );
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
