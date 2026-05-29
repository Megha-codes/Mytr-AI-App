from celery import shared_task
from sqlalchemy import select, func
from datetime import datetime
import logging
import pickle

from xgboost import XGBClassifier
from sklearn.model_selection import cross_val_score

from ..models.meal_log import MealLog
from .post_meal import get_db_session  # Sync session mock

logger = logging.getLogger(__name__)

# --- Mock Dependencies ---
class RecommendationAuditLog:
    pass

class TrainingSample:
    pass

class UserModel:
    pass

class MockRedis:
    def delete(self, key): pass

redis_client = MockRedis()

def get_current_model_accuracy(user_id, db):
    return 0.75 # default
# -------------------------

@shared_task(name="tasks.training.queue_training_sample")
def queue_training_sample(meal_log_id: str, user_id: str):
    """
    Converts a completed meal log into a labelled training sample.
    Stores in training_samples table for nightly retraining.
    """
    with get_db_session() as db:

        # Get full meal log with recommendation
        meal_log = db.get(MealLog, meal_log_id)
        
        # Stub logic to avoid DB crashes with mock
        if not meal_log:
            return

        if not meal_log.glucose_outcome:
            return   # 2hr reading not yet written — skip

        # The label: was the recommendation correct?
        # Correct = glucose was IN_RANGE at 2hr post-meal
        label = 1 if meal_log.glucose_outcome == "IN_RANGE" else 0

        # The features: exactly what the model saw when it recommended
        # Using a mock feature vector for the compilation
        feature_vector = {"carbs": 50, "sleep": 7.5}

        # Store as training sample
        db.add(TrainingSample(
            user_id=user_id,
            meal_log_id=meal_log_id,
            feature_vector=feature_vector,
            recommended_dose=3.5, # mock
            actual_outcome=meal_log.glucose_outcome,
            post_meal_glucose_2hr=meal_log.post_meal_glucose_2hr,
            label=label,
            created_at=datetime.utcnow(),
        ))
        db.commit()

        # Check if user now has enough samples to train a personal model
        sample_count = db.execute(
            select(func.count(TrainingSample.id))
            .where(TrainingSample.user_id == user_id)
        ).scalar()

        # Default to 0 if mock scalar fails
        sample_count = sample_count or 0

        if sample_count >= 14:
            # Trigger personal model training
            retrain_user_model.delay(user_id=user_id)


@shared_task(name="tasks.training.retrain_user_model")
def retrain_user_model(user_id: str):
    """
    Nightly job — retrains the XGBoost model for a specific user
    using all their accumulated training samples.
    Replaces the population-level priors with personalised weights.
    """
    with get_db_session() as db:

        # Pull all training samples for this user
        samples = db.execute(
            select(TrainingSample)
            .where(TrainingSample.user_id == user_id)
            .order_by(TrainingSample.created_at.desc())
            .limit(500)    # Cap at last 500 meals for training window
        ).scalars().all()

        if len(samples) < 14:
            return   # Not enough data yet

        # Prepare feature matrix and labels
        X = [list(s.feature_vector.values()) for s in samples]
        y = [s.label for s in samples]

        # Train XGBoost model
        model = XGBClassifier(
            n_estimators=100,
            max_depth=4,
            learning_rate=0.1,
            # use_label_encoder=False is deprecated in newer xgboost
            eval_metric="logloss",
        )
        model.fit(X, y)

        # Evaluate — only deploy if better than current model
        current_accuracy = get_current_model_accuracy(user_id, db)
        new_accuracy = cross_val_score(model, X, y, cv=3).mean()

        if new_accuracy >= current_accuracy:
            # Serialise and store new model
            model_bytes = pickle.dumps(model)
            db.add(UserModel(
                user_id=user_id,
                model_bytes=model_bytes,
                accuracy=new_accuracy,
                sample_count=len(samples),
                trained_at=datetime.utcnow(),
                version=f"v{len(samples)}",
            ))
            db.commit()

            # Invalidate Redis cache so next prediction uses new model
            redis_client.delete(f"user_model:{user_id}")

            logger.info(
                f"User {user_id}: new model deployed "
                f"(accuracy {new_accuracy:.3f} vs {current_accuracy:.3f})"
            )
        else:
            logger.info(
                f"User {user_id}: new model not deployed "
                f"(accuracy {new_accuracy:.3f} < current {current_accuracy:.3f})"
            )
