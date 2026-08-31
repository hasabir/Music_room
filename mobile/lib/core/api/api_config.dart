import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place to configure how the app talks to the Music Room backend.
///
/// Points at the dev machine's LAN IP so a physical device on the same
/// Wi-Fi network can reach the backend running via `docker compose` on
/// port 8000. This IP is assigned by DHCP and can change — if requests
/// start failing, re-check it with `hostname -I` (or `ip addr`) on the
/// machine running the backend and update `API_BASE_URL` in `.env`.
class ApiConfig {
  const ApiConfig._();

  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://110.238.233.13:8000';

  static String get googleWebClientId => dotenv.env['GOOGLE_CLIENT_ID'] ?? '';

  /// Resolves a server-relative media path (e.g. `/media/playlists/covers/x.jpg`,
  /// as returned in `cover_image_url`/`profile_image`) against [baseUrl] so
  /// it can be passed to `Image.network`. Already-absolute URLs pass through
  /// unchanged; `null`/empty stays `null`.
  static String? resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl$path';
  }

  static const String registerEndpoint = '/api/v1/auth/register/';
  static const String loginEndpoint = '/api/v1/auth/login/';
  static const String meEndpoint = '/api/v1/user/me/';
  static const String verifyEmailEndpoint = '/api/v1/auth/verify-email/';
  static const String resendVerificationEndpoint =
      '/api/v1/auth/resend-verification/';
  static const String logoutEndpoint = '/api/v1/auth/logout/';
  static const String changePasswordEndpoint = '/api/v1/auth/change-password/';
  static const String googleLoginEndpoint = '/api/v1/auth/google/';
  static const String googleLinkEndpoint = '/api/v1/auth/google/link/';
  static const String tokenRefreshEndpoint = '/api/v1/auth/token/refresh/';
  static const String passwordResetRequestEndpoint =
      '/api/v1/auth/password-reset/';
  static const String passwordResetVerifyCodeEndpoint =
      '/api/v1/auth/password-reset/verify-code/';
  static const String passwordResetConfirmEndpoint =
      '/api/v1/auth/password-reset/set-new-password/';
  static const String myProfileEndpoint = '/api/v1/profile/me/';
  static const String friendsEndpoint = '/api/v1/profile/friends/';
  static const String friendRequestsReceivedEndpoint =
      '/api/v1/profile/friends/requests/';
  static const String friendRequestsSentEndpoint =
      '/api/v1/profile/friends/requests/sent/';
  static const String userSearchEndpoint = '/api/v1/profile/search/';
  static const String playlistsEndpoint = '/api/v1/playlists/';
  static const String trackSearchEndpoint = '/api/v1/tracks/search/';
  static const String trackTrendingEndpoint = '/api/v1/tracks/trending/';
  static const String eventsEndpoint = '/api/v1/events/';

  static Uri registerUri() => Uri.parse('$baseUrl$registerEndpoint');
  static Uri loginUri() => Uri.parse('$baseUrl$loginEndpoint');
  static Uri meUri() => Uri.parse('$baseUrl$meEndpoint');
  static Uri verifyEmailUri() => Uri.parse('$baseUrl$verifyEmailEndpoint');
  static Uri resendVerificationUri() =>
      Uri.parse('$baseUrl$resendVerificationEndpoint');
  static Uri tokenRefreshUri() => Uri.parse('$baseUrl$tokenRefreshEndpoint');
  static Uri logoutUri() => Uri.parse('$baseUrl$logoutEndpoint');
  static Uri changePasswordUri() =>
      Uri.parse('$baseUrl$changePasswordEndpoint');
  static Uri googleLoginUri() => Uri.parse('$baseUrl$googleLoginEndpoint');
  static Uri googleLinkUri() => Uri.parse('$baseUrl$googleLinkEndpoint');
  static Uri passwordResetRequestUri() =>
      Uri.parse('$baseUrl$passwordResetRequestEndpoint');
  static Uri passwordResetVerifyCodeUri() =>
      Uri.parse('$baseUrl$passwordResetVerifyCodeEndpoint');
  static Uri passwordResetConfirmUri() =>
      Uri.parse('$baseUrl$passwordResetConfirmEndpoint');
  static Uri myProfileUri() => Uri.parse('$baseUrl$myProfileEndpoint');
  static Uri friendsUri() => Uri.parse('$baseUrl$friendsEndpoint');
  static Uri friendRequestsReceivedUri() =>
      Uri.parse('$baseUrl$friendRequestsReceivedEndpoint');
  static Uri friendRequestsSentUri() =>
      Uri.parse('$baseUrl$friendRequestsSentEndpoint');
  static Uri acceptFriendRequestUri(int requestId) =>
      Uri.parse('$baseUrl/api/v1/profile/friends/requests/$requestId/accept/');
  static Uri rejectFriendRequestUri(int requestId) =>
      Uri.parse('$baseUrl/api/v1/profile/friends/requests/$requestId/reject/');
  static Uri sendFriendRequestUri(int userId) =>
      Uri.parse('$baseUrl/api/v1/profile/friends/$userId/add/');
  static Uri removeFriendUri(int userId) =>
      Uri.parse('$baseUrl/api/v1/profile/friends/$userId/remove/');
  static Uri cancelFriendRequestUri(int userId) =>
      Uri.parse('$baseUrl/api/v1/profile/friends/$userId/cancel/');
  static Uri userProfileUri(int userId) =>
      Uri.parse('$baseUrl/api/v1/profile/profile/$userId/');
  static Uri userSearchUri(String query) =>
      Uri.parse('$baseUrl$userSearchEndpoint')
          .replace(queryParameters: {'q': query});
  static Uri playlistsUri() => Uri.parse('$baseUrl$playlistsEndpoint');
  static Uri playlistDetailUri(int playlistId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/');
  static Uri playlistSongsUri(int playlistId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/songs/');
  static Uri playlistSongDetailUri(int playlistId, int playlistSongId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/songs/$playlistSongId/');
  static Uri playlistSongMoveUri(int playlistId, int playlistSongId) =>
      Uri.parse(
        '$baseUrl$playlistsEndpoint$playlistId/songs/$playlistSongId/move/',
      );
  static Uri playlistCollaboratorsUri(int playlistId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/collaborators/');
  static Uri playlistCollaboratorDetailUri(int playlistId, int userId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/collaborators/$userId/');
  /// [byArtist] switches from the default title/artist/etc keyword match
  /// to an artist-name lookup — see `TrackSearchView` (`backend/api/views.py`).
  static Uri trackSearchUri(String query, {bool byArtist = false}) =>
      Uri.parse('$baseUrl$trackSearchEndpoint').replace(
        queryParameters: {'q': query, if (byArtist) 'by': 'artist'},
      );
  static Uri trackTrendingUri() => Uri.parse('$baseUrl$trackTrendingEndpoint');
  static Uri trackPreviewUri(String externalId) => Uri.parse(
    '$baseUrl/api/v1/tracks/${Uri.encodeComponent(externalId)}/preview/',
  );
  static Uri playlistAccessRequestsUri(int playlistId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/access-requests/');
  static Uri playlistAccessRequestMineUri(int playlistId) =>
      Uri.parse('$baseUrl$playlistsEndpoint$playlistId/access-requests/mine/');
  static Uri playlistAccessRequestDecideUri(
    int playlistId,
    int requestId,
  ) => Uri.parse(
    '$baseUrl$playlistsEndpoint$playlistId/access-requests/$requestId/decide/',
  );

  static Uri eventsUri() => Uri.parse('$baseUrl$eventsEndpoint');
  static Uri eventDetailUri(int eventId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/');
  static Uri eventQueueUri(int eventId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/queue/');
  static Uri eventVoteUri(int eventId, int eventSongId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/queue/$eventSongId/vote/');
  static Uri eventGuestsUri(int eventId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/guests/');
  static Uri eventGuestDetailUri(int eventId, int userId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/guests/$userId/');
  static Uri eventJoinUri(int eventId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/join/');
  static Uri eventAttendeesUri(int eventId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/attendees/');
  static Uri eventAttendeeDetailUri(int eventId, int userId) =>
      Uri.parse('$baseUrl$eventsEndpoint$eventId/attendees/$userId/');
}
