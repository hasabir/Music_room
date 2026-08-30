import '../auth/auth_api.dart';
import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import 'event_models.dart';

/// Thrown when the vote endpoint rejects the caller with a 403 — i.e. any
/// failure case in the backend's `can_user_vote` (not enough songs queued
/// yet, an invite-only license, or outside the allowed location/time
/// window; see `backend/events/permissions.py`). Kept distinct from a bare
/// [ApiException] so the UI can show the restricted-action pattern (lock
/// icon + [message]) instead of a generic error.
class VoteNotPermittedException implements Exception {
  VoteNotPermittedException(this.message);

  final String message;

  @override
  String toString() => 'VoteNotPermittedException($message)';
}

/// Talks to the backend's `events` endpoints (`/api/v1/events/...`).
///
/// Mirrors [PlaylistApi]'s access-token-with-refresh-and-retry handling, but
/// delegates the actual refresh call to an [AuthApi] instance rather than
/// re-implementing it.
class EventApi {
  EventApi({ApiClient? apiClient, TokenStorage? tokenStorage, AuthApi? authApi})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? TokenStorage(),
      _authApi = authApi ?? AuthApi(tokenStorage: tokenStorage);

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final AuthApi _authApi;

  /// Lists public events, plus private events the signed-in user hosts or
  /// is invited to.
  Future<List<Event>> listEvents() async {
    final response = await _authorizedGetList(ApiConfig.eventsUri());
    return response.map((json) => Event.fromJson(json)).toList();
  }

  /// Creates a new event. The signed-in user automatically becomes the
  /// host. [venueCenterLatitude]/[venueCenterLongitude]/
  /// [allowedDistanceMeters]/[votingOpensAt]/[votingClosesAt] are required
  /// by the backend only when [votePermission] is
  /// [eventVotePermissionLocationTimeRestricted].
  Future<Event> createEvent({
    required String title,
    String? description,
    String? coverPreset,
    String? visibility,
    String? votePermission,
    double? venueCenterLatitude,
    double? venueCenterLongitude,
    int? allowedDistanceMeters,
    DateTime? votingOpensAt,
    DateTime? votingClosesAt,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'description': ?description,
      'cover_preset': ?coverPreset,
      'visibility': ?visibility,
      'vote_permission': ?votePermission,
      'venue_center_latitude': ?venueCenterLatitude,
      'venue_center_longitude': ?venueCenterLongitude,
      'allowed_distance_meters': ?allowedDistanceMeters,
      if (votingOpensAt != null)
        'voting_opens_at': votingOpensAt.toUtc().toIso8601String(),
      if (votingClosesAt != null)
        'voting_closes_at': votingClosesAt.toUtc().toIso8601String(),
    };
    final response = await _authorizedPost(ApiConfig.eventsUri(), body: body);
    return Event.fromJson(response);
  }

  /// Fetches one event's details.
  Future<Event> getEvent(int eventId) async {
    final response = await _authorizedGet(ApiConfig.eventDetailUri(eventId));
    return Event.fromJson(response);
  }

  /// Partially updates an event. Only the host may do this. Only
  /// non-null parameters are sent, so callers can update a subset of
  /// fields.
  Future<Event> updateEvent(
    int eventId, {
    String? title,
    String? description,
    String? coverPreset,
    String? visibility,
    String? votePermission,
    double? venueCenterLatitude,
    double? venueCenterLongitude,
    int? allowedDistanceMeters,
    DateTime? votingOpensAt,
    DateTime? votingClosesAt,
  }) async {
    final body = <String, dynamic>{
      'title': ?title,
      'description': ?description,
      'cover_preset': ?coverPreset,
      'visibility': ?visibility,
      'vote_permission': ?votePermission,
      'venue_center_latitude': ?venueCenterLatitude,
      'venue_center_longitude': ?venueCenterLongitude,
      'allowed_distance_meters': ?allowedDistanceMeters,
      if (votingOpensAt != null)
        'voting_opens_at': votingOpensAt.toUtc().toIso8601String(),
      if (votingClosesAt != null)
        'voting_closes_at': votingClosesAt.toUtc().toIso8601String(),
    };
    final response = await _authorizedPatch(
      ApiConfig.eventDetailUri(eventId),
      body: body,
    );
    return Event.fromJson(response);
  }

  /// Deletes an event and its entire queue/votes. Only the host may do
  /// this.
  Future<void> deleteEvent(int eventId) async {
    await _authorizedDelete(ApiConfig.eventDetailUri(eventId));
  }

  /// Joins a public event as a plain member. This is explicitly separate
  /// from [inviteGuest] — it does not grant `invited_only` voting rights,
  /// only membership.
  Future<void> joinEvent(int eventId) async {
    await _authorizedPost(ApiConfig.eventJoinUri(eventId), body: const {});
  }

  /// Lists the event's song queue, sorted by vote count descending.
  Future<List<EventSong>> listQueue(int eventId) async {
    final response = await _authorizedGetList(ApiConfig.eventQueueUri(eventId));
    return response.map((json) => EventSong.fromJson(json)).toList();
  }

  /// Adds a new song to the end of the event's queue, at zero votes.
  /// Reuses an existing catalog song if the same title/artist already
  /// exists.
  Future<EventSong> addToQueue(
    int eventId, {
    required String title,
    required String artist,
    int? durationSeconds,
    String? externalId,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'artist': artist,
      'duration_seconds': ?durationSeconds,
      'external_id': ?externalId,
    };
    final response = await _authorizedPost(
      ApiConfig.eventQueueUri(eventId),
      body: body,
    );
    return EventSong.fromJson(response);
  }

  /// Casts the signed-in user's vote for [eventSongId]. [latitude]/
  /// [longitude] are only required when the event's `votePermission` is
  /// [eventVotePermissionLocationTimeRestricted].
  ///
  /// Throws [VoteNotPermittedException] (rather than a bare
  /// [ApiException]) on a 403 — see that class for why.
  Future<VoteResult> vote(
    int eventId,
    int eventSongId, {
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      'latitude': ?latitude,
      'longitude': ?longitude,
    };
    try {
      final response = await _authorizedPost(
        ApiConfig.eventVoteUri(eventId, eventSongId),
        body: body,
      );
      return VoteResult.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 403) {
        throw VoteNotPermittedException(error.message);
      }
      rethrow;
    }
  }

  /// Retracts the signed-in user's own vote on [eventSongId], if any.
  Future<VoteResult> retractVote(int eventId, int eventSongId) async {
    final response = await _authorizedDeleteWithResponse(
      ApiConfig.eventVoteUri(eventId, eventSongId),
    );
    return VoteResult.fromJson(response);
  }

  /// Lists everyone invited to the event.
  Future<List<EventGuest>> listGuests(int eventId) async {
    final response = await _authorizedGetList(
      ApiConfig.eventGuestsUri(eventId),
    );
    return response.map((json) => EventGuest.fromJson(json)).toList();
  }

  /// Invites [userId] to the event. Host only.
  Future<EventGuest> inviteGuest(int eventId, int userId) async {
    final response = await _authorizedPost(
      ApiConfig.eventGuestsUri(eventId),
      body: {'user_id': userId},
    );
    return EventGuest.fromJson(response);
  }

  /// Removes a guest from the event. Host only.
  Future<void> removeGuest(int eventId, int userId) async {
    await _authorizedDelete(ApiConfig.eventGuestDetailUri(eventId, userId));
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

  Future<Map<String, dynamic>> _authorizedDeleteWithResponse(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.deleteWithResponse(uri, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.deleteWithResponse(
        uri,
        accessToken: refreshedToken,
      );
    }
  }

  /// Event list endpoints return Django REST Framework's paginated
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
