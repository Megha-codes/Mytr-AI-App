from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from datetime import datetime, timedelta
import uuid

app = FastAPI(title="Mock CGM Server")

# ── Dexcom Mock ──────────────────────────────────────────────────────────────

@app.post("/v2/oauth2/token")
async def dexcom_token(grant_type: str, code: str, client_id: str, client_secret: str):
    if code == "valid_code":
        return {
            "access_token": "mock_access_token",
            "refresh_token": "mock_refresh_token",
            "expires_in": 3600
        }
    raise HTTPException(status_code=400, detail="Invalid code")

@app.get("/v3/users/self/egvs")
async def dexcom_egvs():
    return {
        "recordId": str(uuid.uuid4()),
        "systemTime": datetime.utcnow().isoformat(),
        "displayTime": datetime.utcnow().isoformat(),
        "value": 125,
        "status": "OK",
        "trend": "flat",
        "trendRate": 0.0
    }

# ── Libre Mock ───────────────────────────────────────────────────────────────

@app.post("/llu/auth/login")
async def libre_login(data: dict):
    if data.get("email") == "test@example.com" and data.get("password") == "password123":
        return {
            "data": {
                "authTicket": {"token": "mock_libre_token"}
            }
        }
    raise HTTPException(status_code=401, detail="Invalid credentials")

@app.get("/llu/connections")
async def libre_connections():
    return {
        "data": [
            {
                "patientId": "mock_patient_id",
                "device": {"dtid": 40075}, # Libre 3
                "sensor": {"a": int(datetime.utcnow().timestamp())}
            }
        ]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
