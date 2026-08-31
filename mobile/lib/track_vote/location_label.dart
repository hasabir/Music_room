import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';

final _geocoding = Geocoding();

/// Reverse-geocodes [latitude]/[longitude] into a short human-readable
/// label — neighborhood and/or city, plus country — for display instead of
/// raw coordinates. Returns `null` on any failure (no network, no
/// geocoder available on this device, nothing found) so callers can fall
/// back to the raw coordinates rather than showing a blank or crashing.
Future<String?> reverseGeocodeLabel(double latitude, double longitude) async {
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
/// `null` if nothing could be resolved — no network, no geocoder, or the
/// text just doesn't match a real place. See [reverseGeocodeLabel] for the
/// opposite direction.
Future<({double latitude, double longitude})?> forwardGeocodeCoordinates(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;
  try {
    final locations = await _geocoding.locationFromAddress(trimmed);
    if (locations.isEmpty) return null;
    final first = locations.first;
    return (latitude: first.latitude, longitude: first.longitude);
  } catch (_) {
    return null;
  }
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
