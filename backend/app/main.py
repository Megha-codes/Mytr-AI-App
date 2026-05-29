from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .api.onboarding import router as onboarding_router
from .api.auth import router as auth_router
from .api.inference import router as inference_router
from .api.nutrition import router as nutrition_router
from .api.cgm_connect import router as cgm_connect_router
from .api.user import router as user_router
from .api.glucose import router as glucose_router
from .api.dashboard import router as dashboard_router
from .api.achievements import router as achievements_router
from .api.coach import router as coach_router
from .api.websockets import glucose_stream, status_websocket
from .timescale_database import init_timescale_schema

app = FastAPI(
    title="Mytr.AI",
    description="Backend API for Mytr.AI Metabolic Health Platform",
    version="1.0.0",
)


@app.on_event("startup")
async def startup() -> None:
    await init_timescale_schema()

# CORS middleware for Flutter frontend communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth_router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(onboarding_router, prefix="/api/v1/users", tags=["users"])
app.include_router(user_router, prefix="/api/v1/user", tags=["user"])
app.include_router(inference_router, prefix="/api/v1", tags=["inference"])
app.include_router(nutrition_router, prefix="/api/v1/nutrition", tags=["nutrition"])
app.include_router(cgm_connect_router, prefix="/api/v1", tags=["cgm"])
app.include_router(glucose_router, prefix="/api/v1", tags=["glucose"])
app.include_router(dashboard_router, prefix="/api/v1/dashboard", tags=["dashboard"])
app.include_router(achievements_router, prefix="/api/v1/achievements", tags=["achievements"])
app.include_router(coach_router, prefix="/api/v1/coach", tags=["coach"])
app.include_router(glucose_stream.router, tags=["websockets"])
app.include_router(status_websocket.router, tags=["websockets"])

@app.get("/")
def read_root():
    return {"message": "Welcome to Mytr.AI API"}
