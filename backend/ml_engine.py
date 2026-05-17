"""
SignalSight – ML Engine
Trains a RandomForestRegressor on accumulated scan data to predict indoor RSSI.
Falls back to the ITU P.1238 analytical model when insufficient data exists.

Training features
-----------------
[0] distance_m    – approximate distance router→measurement point (m)
[1] frequency     – WiFi frequency (MHz)
[2] walls         – estimated number of walls crossed
[3] time_of_day   – hour + fractional minutes (0–24)
[4] channel       – WiFi channel number

Target
------
rssi              – measured signal strength (dBm)
"""

from __future__ import annotations

import logging
import math
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import joblib
import numpy as np

try:
    from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
    from sklearn.model_selection import cross_val_score, train_test_split
    from sklearn.metrics import mean_absolute_error, mean_squared_error
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import Pipeline
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    logging.warning("scikit-learn not installed – ML engine will use ITU fallback only.")

from wifi_engine import predict_rssi_itu

logger = logging.getLogger(__name__)

MODEL_PATH = "rf_model.joblib"
SCALER_PATH = "rf_scaler.joblib"
META_PATH   = "ml_meta.json"
MIN_SAMPLES = 30   # minimum rows before we attempt training


# ---------------------------------------------------------------------------
# Synthetic seed data (used for initial warm-up when real data is sparse)
# ---------------------------------------------------------------------------

def _generate_synthetic_samples(n: int = 200) -> Tuple[np.ndarray, np.ndarray]:
    """
    Generate synthetic training samples based on the ITU model with
    Gaussian noise to simulate real measurement variance.
    """
    rng = np.random.default_rng(42)
    distances  = rng.uniform(0.5, 30, n)
    frequencies = rng.choice([2412, 2437, 2462, 5180, 5200, 5240, 5745, 5785], n)
    walls      = rng.integers(0, 5, n)
    times      = rng.uniform(0, 24, n)
    channels   = rng.choice(list(range(1, 14)) + [36, 40, 44, 48, 149, 153, 157, 161], n)

    targets = []
    for i in range(n):
        material_list = ["drywall"] * int(walls[i])
        rssi = predict_rssi_itu(
            tx_power_dbm=20.0,
            frequency_mhz=float(frequencies[i]),
            distance_m=float(distances[i]),
            walls=material_list,
            environment="residential",
        )
        # Add realistic noise (±8 dBm std-dev)
        rssi += rng.normal(0, 8)
        targets.append(float(np.clip(rssi, -110, -20)))

    X = np.column_stack([distances, frequencies, walls, times, channels])
    y = np.array(targets)
    return X, y


# ---------------------------------------------------------------------------
# ML Engine class
# ---------------------------------------------------------------------------

class MLEngine:
    def __init__(self) -> None:
        self.model: Optional[Any] = None
        self.is_trained: bool = False
        self.sample_count: int = 0
        self.mae: Optional[float] = None
        self.rmse: Optional[float] = None
        self.last_trained: Optional[str] = None
        self._load_model()

    # -----------------------------------------------------------------------
    # Persistence helpers
    # -----------------------------------------------------------------------

    def _load_model(self) -> None:
        if not SKLEARN_AVAILABLE:
            return
        if os.path.exists(MODEL_PATH):
            try:
                self.model = joblib.load(MODEL_PATH)
                import json
                if os.path.exists(META_PATH):
                    with open(META_PATH) as f:
                        meta = json.load(f)
                    self.is_trained   = meta.get("is_trained", True)
                    self.sample_count = meta.get("sample_count", 0)
                    self.mae          = meta.get("mae")
                    self.rmse         = meta.get("rmse")
                    self.last_trained = meta.get("last_trained")
                else:
                    self.is_trained = True
                logger.info("ML model loaded from %s", MODEL_PATH)
            except Exception as e:
                logger.warning("Failed to load model: %s", e)
                self.model = None

    def _save_model(self) -> None:
        if self.model is None:
            return
        import json
        joblib.dump(self.model, MODEL_PATH)
        with open(META_PATH, "w") as f:
            json.dump(
                {
                    "is_trained":   self.is_trained,
                    "sample_count": self.sample_count,
                    "mae":          self.mae,
                    "rmse":         self.rmse,
                    "last_trained": self.last_trained,
                },
                f,
                indent=2,
            )

    # -----------------------------------------------------------------------
    # Training
    # -----------------------------------------------------------------------

    def train(
        self,
        rows: Optional[List[Dict[str, Any]]] = None,
        force_synthetic: bool = False,
    ) -> Dict[str, Any]:
        """
        Train (or retrain) the RandomForest model.

        Parameters
        ----------
        rows            : list of dicts from database.get_training_samples()
        force_synthetic : if True, always blend in synthetic data
        """
        if not SKLEARN_AVAILABLE:
            return {"status": "error", "detail": "scikit-learn not installed"}

        X_real, y_real = np.empty((0, 5)), np.empty(0)

        if rows:
            try:
                X_real = np.array([
                    [
                        r["distance_m"],
                        r["frequency"],
                        r["walls"],
                        r["time_of_day"],
                        r["channel"],
                    ]
                    for r in rows
                ], dtype=float)
                y_real = np.array([r["rssi"] for r in rows], dtype=float)
            except (KeyError, ValueError) as e:
                logger.warning("Malformed training data: %s", e)

        # Blend synthetic when real data is sparse
        n_real = len(y_real)
        if n_real < MIN_SAMPLES or force_synthetic:
            n_synth = max(MIN_SAMPLES * 4, 200)
            X_s, y_s = _generate_synthetic_samples(n_synth)
            if n_real > 0:
                # Weight real data 3× by repeating rows
                X_all = np.vstack([X_real] * 3 + [X_s])
                y_all = np.concatenate([y_real] * 3 + [y_s])
            else:
                X_all, y_all = X_s, y_s
        else:
            X_all, y_all = X_real, y_real

        self.sample_count = len(y_all)

        # Train / validation split
        X_tr, X_val, y_tr, y_val = train_test_split(
            X_all, y_all, test_size=0.15, random_state=42
        )

        model = RandomForestRegressor(
            n_estimators=200,
            max_depth=12,
            min_samples_leaf=3,
            n_jobs=-1,
            random_state=42,
        )
        model.fit(X_tr, y_tr)

        # Evaluate
        y_pred = model.predict(X_val)
        self.mae  = round(float(mean_absolute_error(y_val, y_pred)), 3)
        self.rmse = round(float(math.sqrt(mean_squared_error(y_val, y_pred))), 3)

        self.model       = model
        self.is_trained  = True
        self.last_trained = datetime.utcnow().isoformat()

        self._save_model()

        return {
            "status":        "trained",
            "sample_count":  self.sample_count,
            "real_samples":  n_real,
            "mae_dbm":       self.mae,
            "rmse_dbm":      self.rmse,
            "last_trained":  self.last_trained,
        }

    # -----------------------------------------------------------------------
    # Prediction
    # -----------------------------------------------------------------------

    def predict(
        self,
        distance_m: float,
        frequency: int,
        walls: int,
        time_of_day: float,
        channel: int,
    ) -> Tuple[float, str, Optional[float]]:
        """
        Predict RSSI.

        Returns
        -------
        predicted_rssi : float  (dBm)
        method         : str    ("RandomForest" | "ITU-P.1238")
        confidence     : float | None  (R² proxy, 0-1)
        """
        if self.is_trained and self.model is not None and SKLEARN_AVAILABLE:
            X = np.array([[distance_m, frequency, walls, time_of_day, channel]])
            rssi = float(self.model.predict(X)[0])
            rssi = float(np.clip(rssi, -120, 0))
            # Rough confidence: higher when MAE is lower
            conf = max(0.0, min(1.0, 1.0 - (self.mae or 10) / 40.0)) if self.mae else None
            return round(rssi, 1), "RandomForest", round(conf, 3) if conf else None

        # --- ITU fallback ---
        material_list = ["drywall"] * max(0, walls)
        rssi = predict_rssi_itu(
            tx_power_dbm=20.0,
            frequency_mhz=float(frequency),
            distance_m=distance_m,
            walls=material_list,
        )
        return round(float(np.clip(rssi, -120, 0)), 1), "ITU-P.1238", None

    # -----------------------------------------------------------------------
    # Status
    # -----------------------------------------------------------------------

    def status(self) -> Dict[str, Any]:
        return {
            "is_trained":   self.is_trained,
            "sample_count": self.sample_count,
            "mae":          self.mae,
            "rmse":         self.rmse,
            "last_trained": self.last_trained,
            "model_type":   "RandomForestRegressor",
            "fallback":     "ITU P.1238 indoor model",
            "sklearn_available": SKLEARN_AVAILABLE,
        }


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------

ml_engine = MLEngine()


def auto_train_if_needed() -> None:
    """
    Called at startup or after a scan upload.
    Trains with available database samples if not yet trained.
    """
    if ml_engine.is_trained:
        return
    try:
        from database import get_training_samples
        rows = get_training_samples()
        result = ml_engine.train(rows)
        logger.info("Auto-train result: %s", result)
    except Exception as e:
        logger.warning("Auto-train failed: %s", e)
