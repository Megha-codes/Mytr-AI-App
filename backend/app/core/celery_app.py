from celery import Celery
from celery.schedules import crontab

celery_app = Celery(
    "mytr_ai",
    broker="redis://localhost:6379/0",
    backend="redis://localhost:6379/1",
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    timezone="Asia/Kolkata",        # IST — your primary user base
    enable_utc=True,

    beat_schedule={
        # Runs every 15 minutes
        "check-post-meal-glucose": {
            "task": "tasks.post_meal.check_post_meal_outcomes",
            "schedule": crontab(minute="*/15"),
        },
        # Runs every night at 2 AM IST — retraining pipeline
        "retrain-inference-models": {
            "task": "tasks.training.retrain_user_models",
            "schedule": crontab(hour=2, minute=0),
        },
        # Runs every 6 hours — sensor expiry monitoring
        "check-sensor-expiry": {
            "task": "tasks.sensor_expiry.check_sensor_expiry",
            "schedule": crontab(hour="*/6"),
        },
    },
)
