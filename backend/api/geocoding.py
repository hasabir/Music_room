import requests
from django.conf import settings

GOOGLE_GEOCODING_URL = "https://maps.googleapis.com/maps/api/geocode/json"


class GeocodingUnavailable(Exception):
    """Google's geocoding service is unreachable, unconfigured, or errored —
    distinct from a query simply matching no real place (see `geocode`)."""


def geocode(query):
    """Forward-geocodes free text (e.g. "Paris, France") into (latitude,
    longitude) via the Google Geocoding API, using this server's own key.

    Returns `None` if the query doesn't match any real place. Raises
    `GeocodingUnavailable` if the service itself can't be used right now —
    no key configured, unreachable, or any status besides OK/ZERO_RESULTS.
    """
    query = (query or "").strip()
    if not query:
        return None
    if not settings.GOOGLE_API_KEY:
        raise GeocodingUnavailable("Geocoding is not configured on the server.")

    try:
        response = requests.get(
            GOOGLE_GEOCODING_URL,
            params={"address": query, "key": settings.GOOGLE_API_KEY},
            timeout=5,
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError):
        raise GeocodingUnavailable("Unable to reach the geocoding service. Please try again.")

    api_status = payload.get("status")
    if api_status == "ZERO_RESULTS":
        return None
    if api_status != "OK":
        raise GeocodingUnavailable("Unable to reach the geocoding service. Please try again.")

    results = payload.get("results") or []
    location = results[0].get("geometry", {}).get("location", {}) if results else {}
    latitude, longitude = location.get("lat"), location.get("lng")
    if latitude is None or longitude is None:
        return None
    return latitude, longitude
