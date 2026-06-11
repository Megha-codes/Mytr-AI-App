from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from datetime import datetime

app = FastAPI(title="Mock CGM Server")

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
