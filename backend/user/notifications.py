from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def notify_user(user_id, *, kind, title, body, data=None):
    """Deliver a transient real-time notification to every active device."""
    async_to_sync(get_channel_layer().group_send)(
        f"user_notifications_{user_id}",
        {
            "type": "notification.message",
            "data": {
                "kind": kind,
                "title": title,
                "body": body,
                "data": data or {},
            },
        },
    )
