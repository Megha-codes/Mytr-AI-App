from datetime import datetime, timedelta
from sqlalchemy import select
from ..core.celery_app import celery_app
from ..database import SessionLocal
from ..models.user import CGMDevice, User
from ..api.websockets.status_websocket import status_manager

@celery_app.task(name="tasks.sensor_expiry.check_sensor_expiry")
def check_sensor_expiry():
    """
    Checks all active CGM sensors for expiry.
    Sends push notifications and updates UI via WebSocket.
    """
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        # Find all active CGM devices that haven't expired yet
        result = db.execute(
            select(CGMDevice).where(
                CGMDevice.is_active == True,
                CGMDevice.deleted_at == None,
                CGMDevice.sensor_expiry_date != None,
                CGMDevice.sensor_status != "EXPIRED"
            )
        )
        devices = result.scalars().all()

        for device in devices:
            time_to_expiry = device.sensor_expiry_date - now
            
            if time_to_expiry <= timedelta(hours=0):
                # Expired
                device.sensor_status = "EXPIRED"
                _send_push_notification(device.user_id, "Sensor Expired", f"Your {device.device_type} sensor has expired. Please replace it.")
                _push_ws_update(device.user_id, "EXPIRED")
            
            elif time_to_expiry <= timedelta(hours=2):
                # Critical warning
                _send_push_notification(device.user_id, "Sensor Expiring Soon", f"Your {device.device_type} sensor expires in less than 2 hours!")
                _push_ws_update(device.user_id, "WARNING_CRITICAL")
                
            elif time_to_expiry <= timedelta(hours=24):
                # 24h warning
                _send_push_notification(device.user_id, "Sensor Expiring", f"Your {device.device_type} sensor expires in {int(time_to_expiry.total_seconds() // 3600)} hours.")
                _push_ws_update(device.user_id, "WARNING_LOW")

        db.commit()
    finally:
        db.close()

def _send_push_notification(user_id, title, body):
    # Mock implementation
    print(f"PUSH to {user_id}: {title} - {body}")

async def _push_ws_update(user_id, status):
    # Status manager handles the broadcast
    try:
        import asyncio
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.ensure_future(status_manager.broadcast_status(str(user_id), status))
        else:
            loop.run_until_complete(status_manager.broadcast_status(str(user_id), status))
    except Exception:
        pass
