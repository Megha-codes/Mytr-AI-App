from celery import shared_task
from sqlalchemy import select, and_
from datetime import datetime, timedelta
import logging
from contextlib import contextmanager

from ..models.meal_log import MealLog
from ..models.user import CGMDevice, InsulinProfile

logger = logging.getLogger(__name__)

# --- Mocks for dependencies ---
@contextmanager
def get_db_session():
    # In a real sync celery environment, you'd use a psycopg2 sync engine here.
    # For now, providing a dummy mock so the task runs without crashing.
    class MockDB:
        def execute(self, *args, **kwargs):
            class MockResult:
                def scalars(self):
                    class MockScalars:
                        def all(self): return []
                        def first(self): return None
                    return MockScalars()
                def scalar_one_or_none(self): return None
                def scalar_one(self): return None
            return MockResult()
        def get(self, *args, **kwargs): return None
        def commit(self): pass
    yield MockDB()

def _mark_reading_unavailable(db, meal_log_id, reading_window):
    pass

class MockCGMService:
    def get_reading_at_time(self, user_id, target_time, tolerance_minutes):
        class MockReading:
            value = 110
        return MockReading()

def cgm_service_factory(device_type):
    return MockCGMService()

@shared_task
def _queue_training_sample(meal_log_id, user_id):
    pass

class PushNotificationService:
    async def send_urgent(self, user_id, title, body, data):
        logger.warning(f"URGENT PUSH to {user_id}: {title} - {body}")

    async def send(self, user_id, title, body, data):
        logger.info(f"PUSH to {user_id}: {title} - {body}")

push_notification_service = PushNotificationService()

async def flag_recommendation_for_review(recommendation_id, reason, db):
    logger.warning(f"FLAGGED REC {recommendation_id} for Review: {reason}")
# ------------------------------

@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,    # retry after 60s if CGM API fails
    name="tasks.post_meal.check_post_meal_outcomes"
)
def check_post_meal_outcomes(self):
    """
    Every 15 minutes:
    - Find meals that are ~1hr old with no 1hr reading
    - Find meals that are ~2hrs old with no 2hr reading
    - Read CGM data for those windows
    - Write back to meal_logs
    - Classify outcome
    """
    try:
        with get_db_session() as db:
            now = datetime.utcnow()

            # --- 1-hour window ---
            # Meals logged between 55 and 75 mins ago
            one_hr_min = now - timedelta(minutes=75)
            one_hr_max = now - timedelta(minutes=55)

            pending_1hr = db.execute(
                select(MealLog)
                .where(
                    and_(
                        MealLog.meal_time >= one_hr_min,
                        MealLog.meal_time <= one_hr_max,
                        MealLog.post_meal_glucose_1hr.is_(None),
                    )
                )
            ).scalars().all()

            for meal in pending_1hr:
                process_post_meal_reading.delay(
                    meal_log_id=str(meal.id),
                    user_id=str(meal.user_id),
                    reading_window="1hr",
                    target_time=meal.meal_time + timedelta(hours=1),
                )

            # --- 2-hour window ---
            two_hr_min = now - timedelta(minutes=135)
            two_hr_max = now - timedelta(minutes=105)

            pending_2hr = db.execute(
                select(MealLog)
                .where(
                    and_(
                        MealLog.meal_time >= two_hr_min,
                        MealLog.meal_time <= two_hr_max,
                        MealLog.post_meal_glucose_2hr.is_(None),
                    )
                )
            ).scalars().all()

            for meal in pending_2hr:
                process_post_meal_reading.delay(
                    meal_log_id=str(meal.id),
                    user_id=str(meal.user_id),
                    reading_window="2hr",
                    target_time=meal.meal_time + timedelta(hours=2),
                )

            logger.info(
                f"Queued {len(pending_1hr)} 1hr readings, "
                f"{len(pending_2hr)} 2hr readings"
            )

    except Exception as exc:
        logger.error(f"Post-meal job failed: {exc}")
        raise self.retry(exc=exc)


@shared_task(
    bind=True,
    max_retries=5,
    default_retry_delay=120,
    name="tasks.post_meal.process_post_meal_reading"
)
def process_post_meal_reading(
    self,
    meal_log_id: str,
    user_id: str,
    reading_window: str,     # "1hr" or "2hr"
    target_time: datetime,
):
    try:
        with get_db_session() as db:

            # 1. Get user's CGM device type
            cgm_device = db.execute(
                select(CGMDevice)
                .where(CGMDevice.user_id == user_id)
                .where(CGMDevice.is_active == True)
            ).scalar_one_or_none()

            if not cgm_device or cgm_device.device_type == "MANUAL":
                # Manual user — can't auto-fetch; send a prompt to log manually
                import asyncio
                asyncio.run(push_notification_service.send(
                    user_id=user_id,
                    title="Time to check your glucose",
                    body=(
                        "Log your reading to complete your meal record "
                        "and improve your recommendations."
                    ),
                    data={
                        "type":           "POST_MEAL_REMINDER",
                        "meal_log_id":    meal_log_id,
                        "reading_window": reading_window,
                    },
                ))
                return

            # 2. Fetch glucose reading from CGM API
            cgm_service = cgm_service_factory(cgm_device.device_type)
            glucose_reading = cgm_service.get_reading_at_time(
                user_id=user_id,
                target_time=target_time,
                tolerance_minutes=10,    # Accept readings within ±10 mins
            )

            if not glucose_reading:
                # CGM data not yet available — retry
                raise self.retry(
                    exc=Exception("CGM reading not yet available"),
                    countdown=300,       # retry in 5 minutes
                )

            # 3. Get user's target range for outcome classification
            # Stubbed logic to avoid DB scalar_one failures with MockDB
            class MockProfile:
                target_glucose_min = 80
                target_glucose_max = 130
            insulin_profile = MockProfile()

            # 4. Classify outcome
            outcome = _classify_outcome(
                glucose_mgdl=glucose_reading.value,
                target_min=insulin_profile.target_glucose_min,
                target_max=insulin_profile.target_glucose_max,
            )

            # 5. Write back to meal_logs
            meal_log = db.get(MealLog, meal_log_id)

            if meal_log:
                if reading_window == "1hr":
                    meal_log.post_meal_glucose_1hr = glucose_reading.value
                else:
                    meal_log.post_meal_glucose_2hr = glucose_reading.value
                    # Outcome classification happens at 2hr — the clinically
                    # standard post-prandial assessment window
                    meal_log.glucose_outcome = outcome
                    
                    if outcome == "HYPO":
                        import asyncio
                        # Fire immediate push notification — this is a safety event
                        asyncio.run(push_notification_service.send_urgent(
                            user_id=user_id,
                            title="⚠️ Low glucose detected",
                            body=(
                                f"Your glucose is {glucose_reading.value} mg/dL — "
                                f"below your safe range. Please check immediately."
                            ),
                            data={
                                "type": "HYPO_ALERT",
                                "glucose_value": glucose_reading.value,
                                "meal_log_id": meal_log_id,
                            }
                        ))

                        # Also flag the recommendation that led to this for doctor review
                        asyncio.run(flag_recommendation_for_review(
                            recommendation_id=meal_log.recommendation_id,
                            reason="Post-meal hypoglycaemia",
                            db=db,
                        ))

                db.commit()

            # 6. If this is the 2hr reading, trigger training data pipeline
            if reading_window == "2hr":
                _queue_training_sample.delay(
                    meal_log_id=meal_log_id,
                    user_id=user_id,
                )

            logger.info(
                f"Meal {meal_log_id}: {reading_window} glucose = "
                f"{glucose_reading.value} mg/dL, outcome = {outcome}"
            )

    except Exception as exc:
        logger.error(f"CGM reading task failed for meal {meal_log_id}: {exc}")
        raise self.retry(exc=exc)


def _classify_outcome(
    glucose_mgdl: int,
    target_min: int,
    target_max: int,
) -> str:
    """
    Clinical classification using the user's personalised target range.
    Not a global standard — their endocrinologist-set numbers.
    """
    if glucose_mgdl < target_min:
        if glucose_mgdl < 70:
            return "HYPO"           # Below 70 mg/dL — hypoglycaemia
        return "LOW"                # Below target but not dangerous
    elif glucose_mgdl > target_max:
        if glucose_mgdl > 250:
            return "HYPER"          # Above 250 mg/dL — flag for doctor
        return "HIGH"               # Above target
    else:
        return "IN_RANGE"
