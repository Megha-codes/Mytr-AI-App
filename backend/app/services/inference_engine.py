from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from ..schemas.inference import BolusRequest, UserContextSchema
from ..models.inference import RecommendationAuditLog

def encode_activity(level: str | None) -> int:
    mapping = {'SEDENTARY': 0, 'LIGHT': 1, 'MODERATE': 2, 'ACTIVE': 3}
    return mapping.get(level, 0) if level else 0

def build_feature_vector(request: BolusRequest, context: UserContextSchema) -> dict:
    # --- Safe defaults for incomplete profiles ---
    icr = context.icr if context.icr and context.icr > 0 else 10.0
    isf = context.isf if context.isf and context.isf > 0 else 40.0
    target_max = context.target_glucose_max if context.target_glucose_max else 120

    # --- Base dose calculation (clinical formula) ---
    base_bolus = request.carbs_g / icr
    
    correction_dose = 0.0
    if request.current_glucose_mgdl > target_max:
        correction_dose = (request.current_glucose_mgdl - target_max) / isf

    # --- Sleep deficit signal ---
    # Clinical baseline: 7.5 hrs optimal
    sleep_deficit_hrs = max(0, 7.5 - request.last_sleep_hrs)
    # Maps to insulin resistance increase: ~3.5% per hour of deficit
    sleep_multiplier = 1 + (sleep_deficit_hrs * 0.035)

    # --- Activity signal ---
    # Exercise within 2 hrs = insulin sensitivity increase
    activity_multiplier = 1.0
    if request.last_activity_minutes_ago <= 30:
        if request.last_activity_intensity == 'INTENSE':
            activity_multiplier = 0.70   # 30% dose reduction
        elif request.last_activity_intensity == 'MODERATE':
            activity_multiplier = 0.80
        elif request.last_activity_intensity == 'LIGHT':
            activity_multiplier = 0.90
    elif request.last_activity_minutes_ago <= 120:
        activity_multiplier = 0.90       # Residual sensitivity effect

    # --- Stress signal ---
    stress_map = {'LOW': 1.0, 'MODERATE': 1.08, 'HIGH': 1.15}
    stress_multiplier = stress_map.get(request.current_stress_level, 1.0)

    # --- Glycaemic load modifier ---
    # High GL meals spike faster — correction needed sooner
    gl_modifier = 1.0
    if request.meal_glycaemic_load > 20:
        gl_modifier = 1.05
    elif request.meal_glycaemic_load < 10:
        gl_modifier = 0.95

    # --- Time of day signal ---
    # Dawn phenomenon: early morning requires ~10-20% more insulin
    hour = request.meal_time.hour
    time_of_day_multiplier = 1.0
    if 5 <= hour <= 9:
        time_of_day_multiplier = 1.10   # Dawn phenomenon window

    # --- Diabetes type modifier ---
    # T2 lifestyle signals carry more weight; T1 ICR is more precise
    diabetes_weight = 1.0 if context.diabetes_type == 'T1' else 0.85

    return {
        # Core dose components
        "base_bolus": base_bolus,
        "correction_dose": correction_dose,

        # Lifestyle multipliers (these are the ML features)
        "sleep_deficit_hrs": sleep_deficit_hrs,
        "sleep_multiplier": sleep_multiplier,
        "activity_multiplier": activity_multiplier,
        "stress_multiplier": stress_multiplier,
        "gl_modifier": gl_modifier,
        "time_of_day_multiplier": time_of_day_multiplier,

        # User profile features
        "diabetes_type_encoded": 0 if context.diabetes_type == 'T1' else 1,
        "weight_kg": context.weight_kg if context.weight_kg else 70.0,
        "icr": icr,
        "isf": isf,
        "baseline_activity_encoded": encode_activity(context.baseline_activity_level),
        "baseline_sleep_hrs": context.baseline_sleep_hrs if context.baseline_sleep_hrs else 7.5,

        # Glucose context
        "current_glucose_mgdl": request.current_glucose_mgdl,
        "glucose_vs_target": request.current_glucose_mgdl - target_max,
        "time_since_last_bolus_hrs": request.time_since_last_bolus_hrs,
    }


class InferenceEngine:
    def predict(self, features: dict, context: UserContextSchema) -> dict:
        # Phase 1: Rule-based dose (before ML has enough data)
        rule_based_dose = self._rule_based_dose(features)

        # Phase 2: ML adjustment (once 14+ correction events logged)
        if self._has_enough_history(context.user_id):
            # Placeholder for ML inference: ml_adjustment = self.model.predict(...)
            ml_adjustment = 1.0  # Simulated model adjustment
            final_dose = rule_based_dose * ml_adjustment
        else:
            final_dose = rule_based_dose
            ml_adjustment = None  # Flag: model not yet personalised

        # Phase 3: Safety guardrails — hard limits regardless of model output
        final_dose = self._apply_safety_limits(final_dose, context)

        # Phase 4: Confidence scoring
        confidence = self._compute_confidence(features, ml_adjustment)

        return {
            "recommended_dose_units": round(final_dose, 2),
            "base_bolus": round(features["base_bolus"], 2),
            "correction_dose": round(features["correction_dose"], 2),
            "lifestyle_adjustment_pct": round(
                ((final_dose / (features["base_bolus"] or 1)) - 1) * 100, 1
            ),
            "confidence_score": confidence,          # 0.0 – 1.0
            "model_personalised": ml_adjustment is not None,
            "recommendation_drivers": self._explain(features),
            "show_doctor_flag": confidence < 0.65    # Flutter shows warning if True
        }

    def _rule_based_dose(self, features: dict) -> float:
        # Simplified rule-based logic multiplying clinical factors
        raw_dose = features["base_bolus"] + features["correction_dose"]
        
        # Apply lifestyle modifiers (simple product for the fallback engine)
        multiplier = (
            features["sleep_multiplier"] * 
            features["activity_multiplier"] * 
            features["stress_multiplier"] * 
            features["gl_modifier"] * 
            features["time_of_day_multiplier"]
        )
        
        return raw_dose * multiplier

    def _has_enough_history(self, user_id: UUID) -> bool:
        # Stub: Return false until real historical logs exist
        return False

    def _compute_confidence(self, features: dict, ml_adjustment: float | None) -> float:
        # Stub: Lower confidence if massive adjustments are taking place or no ML yet
        if ml_adjustment is None:
            return 0.80
        return 0.95

    def _apply_safety_limits(self, dose: float, context: UserContextSchema) -> float:
        icr = context.icr if context.icr and context.icr > 0 else 10.0
        
        # Never recommend more than 2x the base ICR-derived dose
        max_dose = (icr * 2)
        # Never recommend below 50% of base dose
        min_dose = (icr * 0.5)
        return max(min_dose, min(dose, max_dose))

    def _explain(self, features: dict) -> list[str]:
        # Human-readable explanation for the Flutter UI
        drivers = []
        if features["sleep_deficit_hrs"] > 1.5:
            drivers.append("Sleep deficit increasing insulin resistance")
        if features["activity_multiplier"] < 0.85:
            drivers.append("Recent exercise improving sensitivity — dose reduced")
        if features["stress_multiplier"] > 1.08:
            drivers.append("Elevated stress raising cortisol — dose increased")
        if features["time_of_day_multiplier"] > 1.0:
            drivers.append("Dawn phenomenon window — dose adjusted")
        
        if not drivers:
            drivers.append("Standard clinical formula applied")
            
        return drivers

inference_engine = InferenceEngine()

async def log_recommendation(db: AsyncSession, user_id: UUID, features: dict, recommendation: dict):
    """
    Persists the exact inputs, features, and model output for clinical auditing.
    """
    audit_log = RecommendationAuditLog(
        user_id=user_id,
        recommended_dose_units=recommendation["recommended_dose_units"],
        base_bolus=recommendation["base_bolus"],
        correction_dose=recommendation["correction_dose"],
        lifestyle_adjustment_pct=recommendation["lifestyle_adjustment_pct"],
        confidence_score=recommendation["confidence_score"],
        feature_vector=features,
        model_version="rule_based_v1" if not recommendation["model_personalised"] else "xgboost_v1",
        recommendation_drivers=recommendation["recommendation_drivers"],
        show_doctor_flag=recommendation["show_doctor_flag"]
    )
    
    db.add(audit_log)
    await db.commit()
