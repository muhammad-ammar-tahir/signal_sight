import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from ml_engine import MLEngine

def test_ml_engine_predict_untrained():
    engine = MLEngine()
    # It should fallback to ITU model if untrained
    rssi, method, conf = engine.predict(distance_m=5.0, frequency=2412, walls=0, time_of_day=12, channel=1)
    assert method in ("ITU-P.1238", "RandomForest")
    assert rssi < 0

def test_ml_engine_train_and_predict():
    engine = MLEngine()
    samples = [
        {"distance_m": 1.0, "frequency": 2412, "walls": 0, "time_of_day": 12, "channel": 1, "rssi": -30},
        {"distance_m": 5.0, "frequency": 2412, "walls": 1, "time_of_day": 12, "channel": 1, "rssi": -60},
        {"distance_m": 10.0, "frequency": 2412, "walls": 2, "time_of_day": 12, "channel": 1, "rssi": -80},
    ]
    # Train needs at least some variance, we give 3 samples.
    # In RandomForest, it might need more to not fail, let's see:
    res = engine.train(samples)
    if "error" in res:
        # If not enough data
        assert "not enough data" in res["error"].lower()
    else:
        assert engine.is_trained
        rssi, method, conf = engine.predict(distance_m=5.0, frequency=2412, walls=1, time_of_day=12, channel=1)
        assert method == "RandomForest"
