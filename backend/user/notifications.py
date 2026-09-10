from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .models import Notification


def notify_user(user_id, *, kind, title, body, data=None):
    """Persists a Notification row (backs the in-app notifications list —
    full history, read/unread) and delivers it as a transient real-time
    message to every active device (backs the toast)."""
    notification = Notification.objects.create(
        user_id=user_id, kind=kind, title=title, body=body, data=data or {},
    )
    async_to_sync(get_channel_layer().group_send)(
        f"user_notifications_{user_id}",
        {
            "type": "notification.message",
            "data": {
                "id": notification.id,
                "kind": kind,
                "title": title,
                "body": body,
                "data": data or {},
                "is_read": False,
                "created_at": notification.created_at.isoformat(),
            },
        },
    )
