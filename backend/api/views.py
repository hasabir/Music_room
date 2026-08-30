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
DEEZER_TRACK_URL = "https://api.deezer.com/track/{external_id}"


@extend_schema(
    summary="Search for tracks",
    description=(
        "Proxies Deezer's track search so the mobile app never needs its "
        "own API key. Each result includes a 30-second `preview_url` the "
        "client can play directly, plus `external_id`/`title`/`artist`/"
        "`duration_seconds` — the exact shape needed to add the track to "
        "a playlist or an event's queue."
    ),
    parameters=[
        OpenApiParameter(name="q", type=str, required=True, description="Search query (title, artist, ...)"),
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

        try:
            response = requests.get(DEEZER_SEARCH_URL, params={"q": query}, timeout=5)
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError):
            return Response(
                {"detail": "Unable to reach the music search service. Please try again."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        tracks = [
            {
                "external_id": str(track["id"]),
                "title": track.get("title", ""),
                "artist": (track.get("artist") or {}).get("name", ""),
                "album_art_url": (track.get("album") or {}).get("cover_medium", ""),
                "preview_url": track.get("preview", ""),
                "duration_seconds": track.get("duration"),
            }
            for track in payload.get("data", [])
        ]
        return Response(tracks)


@extend_schema(
    summary="Resolve a fresh track preview URL",
    description=(
        "Fetches the current Deezer preview URL for a stable Deezer track ID. "
        "Preview CDN URLs are signed and expire, so clients must resolve one "
        "immediately before playback instead of persisting it."
    ),
    responses={
        200: OpenApiResponse(description="A current preview URL."),
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
