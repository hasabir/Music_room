import '../auth/auth_api.dart';
import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import 'profile_models.dart';

/// Talks to the backend's `profiles` endpoints (`/api/v1/profile/...`).
///
/// Mirrors [AuthApi]'s access-token-with-refresh-and-retry handling, but
/// delegates the actual refresh call to an [AuthApi] instance rather than
/// re-implementing it.
class ProfileApi {
  ProfileApi({ApiClient? apiClient, TokenStorage? tokenStorage, AuthApi? authApi})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? TokenStorage(),
      _authApi = authApi ?? AuthApi(tokenStorage: tokenStorage);

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final AuthApi _authApi;

  /// Fetches the signed-in user's own profile (all fields visible).
  Future<UserProfile> getMyProfile() async {
    final response = await _authorizedGet(ApiConfig.myProfileUri());
    return UserProfile.fromJson(response);
  }

  /// Partially updates the signed-in user's profile. Only non-null
  /// parameters are sent, so callers can update a subset of fields.
  ///
  /// `birthday` is the one exception: since `null` already means "don't
  /// touch this field" for every other parameter, clearing an existing
  /// birthday needs [clearBirthday] instead of passing `birthday: null`.
  Future<UserProfile> updateMyProfile({
    String? displayName,
    String? bio,
    String? location,
    String? favoriteArtist,
    String? phoneNumber,
    DateTime? birthday,
    bool clearBirthday = false,
    List<String>? favoriteGenres,
    Map<String, String>? fieldVisibility,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (location != null) 'location': location,
      if (favoriteArtist != null) 'favorite_artist': favoriteArtist,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (birthday != null)
        'birthday': birthday.toIso8601String().split('T').first
      else if (clearBirthday)
        'birthday': null,
      if (favoriteGenres != null) 'favorite_genres': favoriteGenres,
      if (fieldVisibility != null) 'field_visibility': fieldVisibility,
    };

    final response = await _authorizedPatch(ApiConfig.myProfileUri(), body: body);
    return UserProfile.fromJson(response);
  }

  /// Uploads a new profile photo from the file at [filePath], replacing
  /// `Profile.profile_image`. Sent as `multipart/form-data` since the
  /// field is an image, not JSON-representable.
  Future<UserProfile> uploadProfileImage(String filePath) async {
    final response = await _authorizedPatchMultipartFile(
      ApiConfig.myProfileUri(),
      fieldName: 'profile_image',
      filePath: filePath,
    );
    return UserProfile.fromJson(response);
  }

  /// Lists the signed-in user's accepted friends ("friends").
  Future<List<Friend>> getFriends() async {
    final response = await _authorizedGetList(ApiConfig.friendsUri());
    return response.map((json) => Friend.fromJson(json)).toList();
  }

  /// Fetches another user's profile, filtered by visibility rules
  /// (public fields only, or public + friends-only if you're friends).
  Future<OtherUserProfile> getUserProfile(int userId) async {
    final response = await _authorizedGet(ApiConfig.userProfileUri(userId));
    return OtherUserProfile.fromJson(response);
  }

  /// Lists friend requests sent to the signed-in user that are still
  /// awaiting their response.
  Future<List<FriendRequest>> getReceivedRequests() async {
    final response = await _authorizedGetList(ApiConfig.friendRequestsReceivedUri());
    return response.map((json) => FriendRequest.fromReceivedJson(json)).toList();
  }

  /// Lists friend requests the signed-in user has sent that are still
  /// awaiting the other person's response.
  Future<List<FriendRequest>> getSentRequests() async {
    final response = await _authorizedGetList(ApiConfig.friendRequestsSentUri());
    return response.map((json) => FriendRequest.fromSentJson(json)).toList();
  }

  /// Accepts a pending friend request sent to the signed-in user.
  Future<void> acceptFriendRequest(int requestId) async {
    await _authorizedPost(ApiConfig.acceptFriendRequestUri(requestId));
  }

  /// Rejects a pending friend request sent to the signed-in user.
  Future<void> rejectFriendRequest(int requestId) async {
    await _authorizedPost(ApiConfig.rejectFriendRequestUri(requestId));
  }

  /// Sends a friend request to [userId].
  Future<void> sendFriendRequest(int userId) async {
    await _authorizedPost(ApiConfig.sendFriendRequestUri(userId));
  }

  /// Removes an existing (accepted) friendship with [userId].
  Future<void> removeFriend(int userId) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      await _apiClient.delete(ApiConfig.removeFriendUri(userId), accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      await _apiClient.delete(ApiConfig.removeFriendUri(userId), accessToken: refreshedToken);
    }
  }

  /// Searches users by name/email, annotated with the signed-in user's
  /// relationship to each result. Returns an empty list for a blank query.
  Future<List<SearchUser>> searchUsers(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _authorizedGetList(ApiConfig.userSearchUri(query));
    return response.map((json) => SearchUser.fromJson(json)).toList();
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

  Future<Map<String, dynamic>> _authorizedPost(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.post(uri, body: const {}, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.post(uri, body: const {}, accessToken: refreshedToken);
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

  /// The friends list endpoint returns a bare JSON array rather than an
  /// object, so it needs its own decode path instead of [ApiClient.get].
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
