import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';

final _geocoding = Geocoding();
final _apiClient = ApiClient();
final _tokenStorage = TokenStorage();

/// Reverse-geocodes [latitude]/[longitude] into a short human-readable
/// label — neighborhood and/or city, plus country — for display instead of
/// raw coordinates. Returns `null` on any failure (no network, no
/// geocoder available on this device, nothing found) so callers can fall
/// back to the raw coordinates rather than showing a blank or crashing.
///
/// The `geocoding` plugin has no web implementation at all — every call
/// would throw and get caught below anyway, so `kIsWeb` just skips the
/// doomed round-trip instead of silently eating the exception every time.
Future<String?> reverseGeocodeLabel(double latitude, double longitude) async {
  if (kIsWeb) return null;
  try {
    final placemarks = await _geocoding.placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isEmpty) return null;
    final place = placemarks.first;

    final parts = <String>[
      if (place.subLocality != null && place.subLocality!.trim().isNotEmpty)
        place.subLocality!.trim(),
      if (place.locality != null && place.locality!.trim().isNotEmpty)
        place.locality!.trim(),
      if (place.country != null && place.country!.trim().isNotEmpty)
        place.country!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  } catch (_) {
    return null;
  }
}

/// Forward-geocodes a free-text place name (e.g. a profile's self-reported
/// "location" field, like "Paris, France") into coordinates. Returns
/// `null` if nothing could be resolved on the native path — no network, no
/// geocoder, or the text just doesn't match a real place. See
/// [reverseGeocodeLabel] for the opposite direction.
///
/// This one *can't* just degrade to "unavailable on web" like
/// [reverseGeocodeLabel] does: it's what resolves a voter's profile
/// location before every vote on a location-restricted event, so a
/// permanently-null result would make that entire license rule
/// unvotable from a browser — not "read-only", just broken. On web this
/// calls the backend's own `/geocode/` endpoint instead (see
/// docs/WEB_BONUS.md), which proxies the Google Geocoding API from the
/// server side using a key the `geocoding` plugin has no way to reach —
/// and, unlike the native path, lets a failure's [ApiException] propagate
/// rather than collapsing it to `null`, since the backend already reports
/// a specific, accurate reason ("no location found for X" vs. "the
/// geocoding service is unreachable") that's worth showing over the
/// generic message every caller here already falls back to on `null`.
/// Every existing caller already catches [ApiException] alongside the
/// plain `String` this file's callers throw for the `null` case, so this
/// doesn't add a new catch clause anywhere it's used.
Future<({double latitude, double longitude})?> forwardGeocodeCoordinates(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;
  return kIsWeb
      ? _forwardGeocodeViaBackend(trimmed)
      : _forwardGeocodeViaPlugin(trimmed);
}

Future<({double latitude, double longitude})?> _forwardGeocodeViaPlugin(String query) async {
  try {
    final locations = await _geocoding.locationFromAddress(query);
    if (locations.isEmpty) return null;
    final first = locations.first;
    return (latitude: first.latitude, longitude: first.longitude);
  } catch (_) {
    return null;
  }
}

Future<({double latitude, double longitude})?> _forwardGeocodeViaBackend(String query) async {
  final accessToken = await _tokenStorage.readAccessToken();
  if (accessToken == null) return null;
  final response = await _apiClient.get(
    ApiConfig.geocodeUri(query),
    accessToken: accessToken,
  );
  final latitude = (response['latitude'] as num?)?.toDouble();
  final longitude = (response['longitude'] as num?)?.toDouble();
  if (latitude == null || longitude == null) return null;
  return (latitude: latitude, longitude: longitude);
}

/// Straight-line distance between two points, in meters — the Haversine
/// formula, mirroring the backend's `_distance_in_meters` in
/// `events/permissions.py` exactly, so a client-side "too far" pre-check
/// agrees with what the server ultimately enforces.
double distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;

  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) * math.cos(phi2) * math.sin(dLambda / 2) * math.sin(dLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}
