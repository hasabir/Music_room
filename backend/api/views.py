import re

import requests
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import generics, serializers, status
from rest_framework.permissions import IsAuthenticated
from drf_spectacular.utils import extend_schema, OpenApiParameter, OpenApiResponse

from .throttles import TrackPreviewRateThrottle, TrackSearchRateThrottle

class HomeView(APIView):
    def get(self, request):
        return Response({'Details': 'Api is Alive!'})


DEEZER_SEARCH_URL = "https://api.deezer.com/search"
DEEZER_ARTIST_SEARCH_URL = "https://api.deezer.com/search/artist"
DEEZER_ARTIST_TOP_URL = "https://api.deezer.com/artist/{artist_id}/top"
DEEZER_CHART_TRACKS_URL = "https://api.deezer.com/chart/0/tracks"
DEEZER_TRACK_URL = "https://api.deezer.com/track/{external_id}"
AUDIOUS_API_URL = "https://api.audius.co/v1"
AUDIOUS_EXTERNAL_ID_PREFIX = "audius:"


def _format_deezer_track(track):
    """Maps one raw Deezer API track object to this API's common track
    shape — shared by search results and the trending chart, and matching
    what `_search_audius` produces so a client can treat every result the
    same way regardless of source."""
    return {
        "external_id": str(track["id"]),
        "title": track.get("title", ""),
        "artist": (track.get("artist") or {}).get("name", ""),
        "album_art_url": (track.get("album") or {}).get("cover_medium", ""),
        "preview_url": track.get("preview", ""),
        "duration_seconds": track.get("duration"),
        "playback_type": "preview",
    }


def _audius_stream_url(track_id):
    return f"{AUDIOUS_API_URL}/tracks/{track_id}/stream"


def _is_audius_streamable(track):
    value = track.get("is_streamable", track.get("isStreamable", True))
    return value not in (False, "false", "False", 0, "0")


def _format_audius_track(track):
    """Maps one raw Audius API track object to this API's common track
    shape — shared by search and trending. Mirrors `_format_deezer_track`
    so a client can treat every result the same way regardless of source."""
    track_id = str(track.get("id", ""))
    artwork = track.get("artwork") or {}
    artist = track.get("user") or {}
    return {
        "external_id": f"{AUDIOUS_EXTERNAL_ID_PREFIX}{track_id}",
        "title": track.get("title", ""),
        "artist": artist.get("name", artist.get("handle", "")),
        "album_art_url": artwork.get("480x480", artwork.get("_480x480", "")),
        # Stored in the existing field for backward compatibility. It is
        # a full, legal Audius stream — not a Deezer preview.
        "preview_url": _audius_stream_url(track_id),
        "duration_seconds": track.get("duration"),
        "playback_type": "full",
    }


def _fetch_audius_tracks(url, params):
    """Shared fetch/filter logic for any Audius tracks-list endpoint
    (search, trending, ...) — full-length, streamable tracks only, in this
    API's common shape, without failing the caller if Audius is
    unreachable."""
    try:
        response = requests.get(url, params=params, timeout=5)
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError):
        return []

    if not isinstance(payload, dict):
        return []

    tracks = []
    for track in payload.get("data", []):
        track_id = str(track.get("id", ""))
        if not track_id or not _is_audius_streamable(track):
            continue
        tracks.append(_format_audius_track(track))
    return tracks


def _search_audius(query):
    """Returns full-length, streamable Audius tracks matching `query` by
    title/artist/etc (Audius's default full-text track search), without
    failing search if Audius is unreachable."""
    return _fetch_audius_tracks(
        f"{AUDIOUS_API_URL}/tracks/search", {"query": query, "limit": 10}
    )


def _search_audius_by_artist(query):
    """Returns full-length, streamable tracks by the Audius artist whose
    name best matches `query` — a two-step find-the-artist-then-list-their-
    tracks lookup, as opposed to `_search_audius`'s single keyword search
    that happens to also match the artist field. Empty (never raising) if
    no artist matches or either Audius call fails, same as `_search_audius`."""
    try:
        response = requests.get(
            f"{AUDIOUS_API_URL}/users/search", params={"query": query, "limit": 1}, timeout=5
        )
        response.raise_for_status()
        users = response.json().get("data", [])
    except (requests.RequestException, ValueError):
        return []

    user_id = users[0].get("id") if users else None
    if not user_id:
        return []

    return _fetch_audius_tracks(f"{AUDIOUS_API_URL}/users/{user_id}/tracks", {"limit": 10})


def _trending_audius():
    """Returns Audius's current trending full-length, streamable tracks,
    without failing trending if Audius is unreachable."""
    return _fetch_audius_tracks(f"{AUDIOUS_API_URL}/tracks/trending", {"limit": 10})


def _search_deezer_by_artist(query):
    """Returns 30-second-preview Deezer tracks — the current top tracks of
    the artist whose name best matches `query` — mirroring
    `_search_audius_by_artist`'s two-step lookup. Returns `(tracks, ok)`
    where `ok` is `False` only when Deezer could not be reached at all
    (empty-but-`ok` means Deezer was reachable but no artist matched),
    same contract `TrackSearchView.get` already expects from the plain
    Deezer search request it makes inline."""
    try:
        search_response = requests.get(
            DEEZER_ARTIST_SEARCH_URL, params={"q": query, "limit": 1}, timeout=5
        )
        search_response.raise_for_status()
        artists = search_response.json().get("data", [])
        if not artists:
            return [], True

        top_response = requests.get(
            DEEZER_ARTIST_TOP_URL.format(artist_id=artists[0]["id"]),
            params={"limit": 10},
            timeout=5,
        )
        top_response.raise_for_status()
        top_payload = top_response.json()
    except (requests.RequestException, ValueError, KeyError):
        return [], False

    return [_format_deezer_track(track) for track in top_payload.get("data", [])], True


@extend_schema(
    summary="Search for tracks",
    description=(
        "Returns legal, full-length Audius streams first when available, then "
        "falls back to Deezer's 30-second previews. Each result includes a "
        "`playback_type` of `full` or `preview` plus the fields needed to add "
        "the track to a playlist or an event's queue.\n\n"
        "By default `q` is matched against title/artist/etc using each "
        "source's normal full-text track search. Passing `by=artist` "
        "switches to an artist lookup instead: `q` is matched against artist "
        "names only, and the results are that best-matching artist's "
        "tracks (their current Deezer top tracks, plus their Audius "
        "tracks) rather than a keyword match against every field."
    ),
    parameters=[
        OpenApiParameter(name="q", type=str, required=True, description="Search query (title, artist, ...)"),
        OpenApiParameter(
            name="by", type=str, required=False,
            description="`track` (default) matches title/artist/etc; `artist` looks up an artist by name "
                         "and returns their tracks.",
        ),
    ],
    responses={
        200: OpenApiResponse(description="List of matching tracks."),
        400: OpenApiResponse(description="Missing or blank `q` parameter."),
        502: OpenApiResponse(description="Deezer is unreachable or returned an error."),
    },
    tags=["tracks"],
)
class TrackSearchView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [TrackSearchRateThrottle]

    def get(self, request):
        query = request.query_params.get("q", "").strip()
        if not query:
            return Response({"detail": "Query parameter 'q' is required."}, status=status.HTTP_400_BAD_REQUEST)

        by_artist = request.query_params.get("by", "").strip().lower() == "artist"

        if by_artist:
            full_tracks = _search_audius_by_artist(query)
            preview_tracks, deezer_ok = _search_deezer_by_artist(query)
        else:
            full_tracks = _search_audius(query)
            try:
                response = requests.get(DEEZER_SEARCH_URL, params={"q": query}, timeout=5)
                response.raise_for_status()
                preview_tracks = [
                    _format_deezer_track(track) for track in response.json().get("data", [])
                ]
                deezer_ok = True
            except (requests.RequestException, ValueError):
                preview_tracks, deezer_ok = [], False

        if not deezer_ok:
            if full_tracks:
                return Response(full_tracks)
            return Response(
                {"detail": "Unable to reach the music search service. Please try again."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        return Response([*full_tracks, *preview_tracks])


@extend_schema(
    summary="List trending tracks",
    description=(
        "Returns Audius's current trending full-length tracks first when "
        "available, then Deezer's top chart as 30-second previews — same "
        "combined shape and same source priority as search. Meant as the "
        "default 'popular now' list before a user has typed a search query."
    ),
    responses={
        200: OpenApiResponse(description="List of trending tracks."),
        502: OpenApiResponse(description="Deezer is unreachable or returned an error."),
    },
    tags=["tracks"],
)
class TrackTrendingView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [TrackSearchRateThrottle]

    def get(self, request):
        full_tracks = _trending_audius()

        try:
            response = requests.get(DEEZER_CHART_TRACKS_URL, timeout=5)
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError):
            if full_tracks:
                return Response(full_tracks)
            return Response(
                {"detail": "Unable to reach the music search service. Please try again."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        preview_tracks = [_format_deezer_track(track) for track in payload.get("data", [])]
        return Response([*full_tracks, *preview_tracks])


@extend_schema(
    summary="Resolve a playable track URL",
    description=(
        "Returns an Audius full-stream URL or fetches a fresh Deezer preview "
        "URL for a stable external track ID. Deezer preview CDN URLs are "
        "signed and expire, so clients resolve them immediately before playback."
    ),
    responses={
        200: OpenApiResponse(description="A current playable URL."),
        400: OpenApiResponse(description="The external ID is invalid."),
        404: OpenApiResponse(description="The track has no playable preview."),
        502: OpenApiResponse(description="Deezer is unreachable or returned an error."),
    },
    tags=["tracks"],
)
class TrackPreviewView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [TrackPreviewRateThrottle]

    def get(self, request, external_id):
        if external_id.startswith(AUDIOUS_EXTERNAL_ID_PREFIX):
            audius_track_id = external_id.removeprefix(AUDIOUS_EXTERNAL_ID_PREFIX)
            if not re.fullmatch(r"[A-Za-z0-9]+", audius_track_id):
                return Response(
                    {"detail": "An Audius track ID is required."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response({"preview_url": _audius_stream_url(audius_track_id)})

        if not external_id.isdecimal():
            return Response(
                {"detail": "A Deezer numeric track ID is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            response = requests.get(
                DEEZER_TRACK_URL.format(external_id=external_id), timeout=5
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError):
            return Response(
                {"detail": "Unable to reach the music service. Please try again."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        preview_url = payload.get("preview", "")
        if not isinstance(preview_url, str) or not preview_url:
            return Response(
                {"detail": "No preview is available for this track."},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response({"preview_url": preview_url})
