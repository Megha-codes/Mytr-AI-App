from typing import Dict, List
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from uuid import UUID

router = APIRouter()

class StatusWebSocketManager:
    def __init__(self):
        # Maps user_id (str) to a list of active WebSocket connections
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, user_id: str):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)

    def disconnect(self, websocket: WebSocket, user_id: str):
        if user_id in self.active_connections:
            self.active_connections[user_id].remove(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def broadcast_status(self, user_id: str, status: str):
        """Sends a status update to all active connections for a user."""
        if user_id in self.active_connections:
            message = {"type": "SENSOR_STATUS", "status": status}
            for connection in self.active_connections[user_id]:
                try:
                    await connection.send_json(message)
                except Exception:
                    # Connection might be dead, handled by disconnect
                    continue

status_manager = StatusWebSocketManager()

@router.websocket("/ws/sensor-status/{user_id}")
async def sensor_status_endpoint(websocket: WebSocket, user_id: str):
    await status_manager.connect(websocket, user_id)
    try:
        while True:
            # Keep connection alive
            await websocket.receive_text()
    except WebSocketDisconnect:
        status_manager.disconnect(websocket, user_id)
