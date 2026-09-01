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
  /// host. [votePermission] (who's allowed to vote at all) and the two
  /// restriction toggles are independent — any combination is valid.
  /// [votingOpensAt]/[votingClosesAt] are required by the backend when
  /// [timeRestrictionEnabled] is `true`; [venueCenterLatitude]/
  /// [venueCenterLongitude]/[allowedDistanceMeters] are required when
  /// [locationRestrictionEnabled] is `true`.
  Future<Event> createEvent({
    required String title,
    String? description,
    String? coverPreset,
    String? visibility,
    String? votePermission,
    bool? timeRestrictionEnabled,
    bool? locationRestrictionEnabled,
    double? venueCenterLatitude,
    double? venueCenterLongitude,
    int? allowedDistanceMeters,
    DateTime? votingOpensAt,
    DateTime? votingClosesAt,
    int? maxParticipants,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'description': ?description,
      'cover_preset': ?coverPreset,
      'visibility': ?visibility,
      'vote_permission': ?votePermission,
      'time_restriction_enabled': ?timeRestrictionEnabled,
      'location_restriction_enabled': ?locationRestrictionEnabled,
      'venue_center_latitude': ?venueCenterLatitude,
      'venue_center_longitude': ?venueCenterLongitude,
      'allowed_distance_meters': ?allowedDistanceMeters,
      if (votingOpensAt != null)
        'voting_opens_at': votingOpensAt.toUtc().toIso8601String(),
      if (votingClosesAt != null)
        'voting_closes_at': votingClosesAt.toUtc().toIso8601String(),
      'max_participants': ?maxParticipants,
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
  /// fields — e.g. [EventSettingsScreen] only ever sends [status].
  Future<Event> updateEvent(
    int eventId, {
    String? title,
    String? description,
    String? coverPreset,
    String? visibility,
    String? status,
    String? votePermission,
    bool? timeRestrictionEnabled,
    bool? locationRestrictionEnabled,
    double? venueCenterLatitude,
    double? venueCenterLongitude,
    int? allowedDistanceMeters,
    DateTime? votingOpensAt,
    DateTime? votingClosesAt,
    int? maxParticipants,
  }) async {
    final body = <String, dynamic>{
      'title': ?title,
      'description': ?description,
      'cover_preset': ?coverPreset,
      'visibility': ?visibility,
      'status': ?status,
      'vote_permission': ?votePermission,
      'time_restriction_enabled': ?timeRestrictionEnabled,
      'location_restriction_enabled': ?locationRestrictionEnabled,
      'venue_center_latitude': ?venueCenterLatitude,
      'venue_center_longitude': ?venueCenterLongitude,
      'allowed_distance_meters': ?allowedDistanceMeters,
      if (votingOpensAt != null)
        'voting_opens_at': votingOpensAt.toUtc().toIso8601String(),
      if (votingClosesAt != null)
        'voting_closes_at': votingClosesAt.toUtc().toIso8601String(),
      'max_participants': ?maxParticipants,
    };
    final response = await _authorizedPatch(
      ApiConfig.eventDetailUri(eventId),
      body: body,
    );
    return Event.fromJson(response);
  }

  /// Soft-deletes an event (its queue/votes/guests/members are kept, not
  /// removed — see `Event.STATUS_DELETED` on the backend). Only the host
  /// may do this. Every guest/member still gets `eventStatusDeleted` back
  /// from `getEvent`, so their event screen picks it up on its next poll
  /// and shows a "this event has been deleted" message rather than
  /// erroring out.
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
    String? albumArtUrl,
    String? previewUrl,
    String? playbackType,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'artist': artist,
      'duration_seconds': ?durationSeconds,
      'external_id': ?externalId,
      'album_art_url': ?albumArtUrl,
      'preview_url': ?previewUrl,
      'playback_type': ?playbackType,
    };
    final response = await _authorizedPost(
      ApiConfig.eventQueueUri(eventId),
      body: body,
    );
    return EventSong.fromJson(response);
  }

  /// Casts the signed-in user's vote for [eventSongId]. [latitude]/
  /// [longitude] are only required when the event's
  /// `locationRestrictionEnabled` is `true`.
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

  /// Likes the event. Anyone who can see it can like it, independent of
  /// hosting/joining.
  Future<LikeResult> likeEvent(int eventId) async {
    final response = await _authorizedPost(
      ApiConfig.eventLikeUri(eventId),
      body: const {},
    );
    return LikeResult.fromJson(response);
  }

  /// Removes the signed-in user's own like from the event, if any.
  Future<LikeResult> unlikeEvent(int eventId) async {
    final response = await _authorizedDeleteWithResponse(
      ApiConfig.eventLikeUri(eventId),
    );
    return LikeResult.fromJson(response);
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

  /// Sets the signed-in user's own RSVP status on their invitation to
  /// [eventId] — accept or decline. Only valid on an event the caller has
  /// actually been invited to (an `EventGuest` row already exists for
  /// them); see [eventGuestRsvpAccepted]/[eventGuestRsvpDeclined].
  Future<EventGuest> respondToInvite(int eventId, {required bool accept}) async {
    final response = await _authorizedPost(
      ApiConfig.eventGuestRespondUri(eventId),
      body: {
        'response': accept ? eventGuestRsvpAccepted : eventGuestRsvpDeclined,
      },
    );
    return EventGuest.fromJson(response);
  }

  /// Lists everyone who has self-joined the event (as opposed to
  /// [listGuests], which is who's been invited).
  Future<List<EventMembership>> listAttendees(int eventId) async {
    final response = await _authorizedGetList(
      ApiConfig.eventAttendeesUri(eventId),
    );
    return response.map((json) => EventMembership.fromJson(json)).toList();
  }

  /// Removes an attendee's membership from the event. Host only.
  Future<void> removeAttendee(int eventId, int userId) async {
    await _authorizedDelete(ApiConfig.eventAttendeeDetailUri(eventId, userId));
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
