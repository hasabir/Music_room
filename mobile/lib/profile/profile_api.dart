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
  Future<UserProfile> updateMyProfile({
    String? displayName,
    String? bio,
    String? location,
    String? favoriteArtist,
    String? phoneNumber,
    List<String>? favoriteGenres,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (location != null) 'location': location,
      if (favoriteArtist != null) 'favorite_artist': favoriteArtist,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (favoriteGenres != null) 'favorite_genres': favoriteGenres,
    };

    final response = await _authorizedPatch(ApiConfig.myProfileUri(), body: body);
    return UserProfile.fromJson(response);
  }

  /// Lists the signed-in user's accepted friends ("Crew").
  Future<List<Friend>> getFriends() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    final response = await _authorizedGetList(ApiConfig.friendsUri());
    return response.map((json) => Friend.fromJson(json)).toList();
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
