"""
SignalSight – FastAPI Backend
Full production server with REST + WebSocket endpoints.

Start:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

JWT auth is scaffolded and enforced on /admin/* routes.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Set

from fastapi import (
    Depends, FastAPI, HTTPException, Query,
    WebSocket, WebSocketDisconnect, status,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

# ---------- Internal modules ----------
import database as db
from core.config import settings
from core.logger import setup_logging
from models import (
    AlertItem,
    ChannelRecommendation,
    ChannelScore,
    CoverageRequest,
    CoverageResponse,
    DeviceInfo,
    DeviceListUpdate,
    MLStatus,
    OptimalPlacementRequest,
    OptimalPlacementResponse,
    PredictRSSIRequest,
    PredictRSSIResponse,
    ScanUploadRequest,
    SecurityAudit,
    SecurityAdvice,
    SuccessResponse,
    TimelineEntry,
    TimelineResponse,
)
from wifi_engine import (
    build_channel_reasoning,
    build_placement_reasoning,
    channel_congestion_score,
    compute_coverage_grid,
    find_optimal_router_position,
    security_classify,
)
from ml_engine import auto_train_if_needed, ml_engine

# ---------- JWT (optional) ----------
try:
    import jwt as pyjwt
    JWT_AVAILABLE = True
except ImportError:
    JWT_AVAILABLE = False

logger = logging.getLogger(__name__)
setup_logging()

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Real-time WiFi analysis, ML-based RSSI prediction, and network security auditing.",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# WebSocket connection manager
# ---------------------------------------------------------------------------

class ConnectionManager:
    def __init__(self) -> None:
        self._connections: Set[WebSocket] = set()

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self._connections.add(ws)
        logger.info("WS client connected  (total=%d)", len(self._connections))

    def disconnect(self, ws: WebSocket) -> None:
        self._connections.discard(ws)
        logger.info("WS client disconnected (total=%d)", len(self._connections))

    async def broadcast(self, payload: Dict[str, Any]) -> None:
        dead: List[WebSocket] = []
        text = json.dumps(payload, default=str)
        for ws in list(self._connections):
            try:
                await ws.send_text(text)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self._connections.discard(ws)


manager = ConnectionManager()


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await manager.connect(websocket)
    try:
        while True:
            # Keep connection alive; client can also send pings
            data = await websocket.receive_text()
            if data.strip() == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        manager.disconnect(websocket)


# ---------------------------------------------------------------------------
# JWT auth scaffold
# ---------------------------------------------------------------------------

JWT_SECRET  = settings.JWT_SECRET
JWT_ALG     = "HS256"
JWT_EXPIRE  = 60 * 24   # minutes

bearer = HTTPBearer(auto_error=False)


def _create_token(username: str) -> str:
    payload = {
        "sub": username,
        "exp": datetime.utcnow() + timedelta(minutes=JWT_EXPIRE),
    }
    if JWT_AVAILABLE:
        return pyjwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)
    return "jwt-disabled"


def _verify_token(credentials: Optional[HTTPAuthorizationCredentials]) -> str:
    if not JWT_AVAILABLE:
        return "admin"   # JWT lib not installed – allow all in dev
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    try:
        data = pyjwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALG])
        return data["sub"]
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

@app.on_event("startup")
async def startup() -> None:
    db.init_db()
    # Train ML model in background thread so startup is not blocked
    threading.Thread(target=auto_train_if_needed, daemon=True).start()
    logger.info("SignalSight backend started  (JWT=%s)", JWT_AVAILABLE)


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health", tags=["Health"])
async def health() -> Dict[str, str]:
    return {"status": "ok", "version": "2.0.0", "timestamp": datetime.utcnow().isoformat()}


# ---------------------------------------------------------------------------
# Auth  (POST /auth/token)
# ---------------------------------------------------------------------------

@app.post("/auth/token", tags=["Auth"])
async def get_token(username: str = Query("admin"), password: str = Query("changeme")) -> Dict[str, str]:
    """
    Demo token endpoint. In production replace with real credential validation.
    """
    # Simple check – replace with DB lookup + bcrypt in production
    if password != settings.ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="Bad credentials")
    return {"access_token": _create_token(username), "token_type": "bearer"}


# ---------------------------------------------------------------------------
# POST /api/scan/upload
# ---------------------------------------------------------------------------

@app.post("/api/scan/upload", response_model=SuccessResponse, tags=["Scan"])
async def upload_scan(data: ScanUploadRequest) -> SuccessResponse:
    """
    Receive a JSON list of scanned WiFi networks from Flutter,
    persist them, then broadcast via WebSocket to all subscribers.
    """
    networks_dict = [n.dict() for n in data.networks]
    scan_id = db.save_scan(data.timestamp, networks_dict)

    # Generate security alerts for new dangerous networks
    _check_and_alert(networks_dict)

    # Broadcast to all WS clients
    await manager.broadcast(
        {
            "event":         "NEW_SCAN",
            "scan_id":       scan_id,
            "timestamp":     data.timestamp.isoformat(),
            "network_count": len(data.networks),
        }
    )

    # Trigger background ML re-train if model isn't trained yet
    if not ml_engine.is_trained:
        threading.Thread(target=auto_train_if_needed, daemon=True).start()

    return SuccessResponse(detail=f"Saved scan_id={scan_id} with {len(data.networks)} networks")


def _check_and_alert(networks: List[Dict[str, Any]]) -> None:
    """Create DB alerts for open / WEP networks found in a scan."""
    for net in networks:
        caps = net.get("capabilities", "")
        proto, risk, advice, score, _ = security_classify(caps)
        if risk in ("CRITICAL", "HIGH"):
            db.create_alert(
                alert_type="SECURITY",
                message=f"{net.get('ssid', '?')} ({net.get('bssid', '?')}) – {proto}: {advice[:120]}",
                severity=risk,
                bssid=net.get("bssid"),
            )


# ---------------------------------------------------------------------------
# GET /api/scan/latest
# ---------------------------------------------------------------------------

@app.get("/api/scan/latest", tags=["Scan"])
async def latest_scan() -> Dict[str, Any]:
    """Return the most recent scan snapshot."""
    history = db.get_scan_history(1)
    if not history:
        raise HTTPException(status_code=404, detail="No scans available yet. Upload a scan first.")
    return history[0]


# ---------------------------------------------------------------------------
# GET /api/scan/history
# ---------------------------------------------------------------------------

@app.get("/api/scan/history", tags=["Scan"])
async def scan_history(
    limit: int = Query(100, ge=1, le=500),
    bssid: Optional[str] = Query(None, description="Filter by BSSID"),
) -> List[Dict[str, Any]]:
    """Return historical scans with optional BSSID filter."""
    return db.get_scan_history(limit=limit, bssid_filter=bssid)


# ---------------------------------------------------------------------------
# GET /api/scan/{scan_id}
# ---------------------------------------------------------------------------

@app.get("/api/scan/{scan_id}", tags=["Scan"])
async def get_scan(scan_id: int) -> Dict[str, Any]:
    entry = db.get_scan_by_id(scan_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Scan not found")
    return entry


# ---------------------------------------------------------------------------
# GET /api/channel/recommendation
# ---------------------------------------------------------------------------

@app.get("/api/channel/recommendation", response_model=ChannelRecommendation, tags=["Analysis"])
async def channel_recommendation(
    band: str = Query("2.4GHz", regex="^(2\\.4GHz|5GHz)$"),
) -> ChannelRecommendation:
    """
    Runs the channel congestion algorithm on stored data.
    Returns best channel for the requested band with scores and reasoning.
    """
    history = db.get_scan_history(5)  # use last 5 scans for robustness
    networks: List[Dict[str, Any]] = []
    for h in history:
        networks.extend(h["networks"])

    is_5ghz = band == "5GHz"
    best_ch, scores, details = channel_congestion_score(networks, is_5ghz)
    reasoning = build_channel_reasoning(best_ch, scores, is_5ghz)

    # Persist result
    db.save_channel_analysis(band, best_ch, scores, reasoning)

    ch_details = [
        ChannelScore(
            channel=d["channel"],
            score=d["score"],
            ap_count=d["ap_count"],
            max_rssi=d["max_rssi"] if d["max_rssi"] is not None else -120,
        )
        for d in details
    ]

    return ChannelRecommendation(
        band=band,
        best_channel=best_ch,
        congestion_scores={str(k): v for k, v in scores.items()},
        channel_details=ch_details,
        reasoning=reasoning,
    )


# ---------------------------------------------------------------------------
# GET /api/security/audit
# ---------------------------------------------------------------------------

@app.get("/api/security/audit", response_model=SecurityAudit, tags=["Security"])
async def security_audit() -> SecurityAudit:
    """
    Analyses the most-recent scan for weak security.
    Returns risk levels with plain-language remediation advice.
    """
    history = db.get_scan_history(1)
    networks = history[0]["networks"] if history else []

    vulnerable: List[SecurityAdvice] = []
    secure:     List[SecurityAdvice] = []

    for net in networks:
        proto, risk, advice, score, enc_detail = security_classify(
            net.get("capabilities", "")
        )
        entry = SecurityAdvice(
            bssid=net.get("bssid", ""),
            ssid=net.get("ssid", ""),
            security_protocol=proto,
            risk_level=risk,
            risk_score=score,
            remediation=advice,
            encryption_details=enc_detail,
        )
        if risk in ("CRITICAL", "HIGH"):
            vulnerable.append(entry)
        else:
            secure.append(entry)

    total = len(networks)
    v_count = len(vulnerable)
    if v_count == 0:
        risk_summary = f"All {total} scanned networks appear to use acceptable security."
    elif v_count <= total // 3:
        risk_summary = f"{v_count}/{total} networks have weak security – address the highlighted networks."
    else:
        risk_summary = f"WARNING: {v_count}/{total} networks are at HIGH or CRITICAL risk. Immediate action recommended."

    return SecurityAudit(
        total_networks=total,
        vulnerable_count=v_count,
        secure_count=len(secure),
        risk_summary=risk_summary,
        vulnerable_networks=vulnerable,
        secure_networks=secure,
    )


# ---------------------------------------------------------------------------
# GET /api/devices   (list)
# ---------------------------------------------------------------------------

@app.get("/api/devices", tags=["Devices"])
async def list_devices() -> List[Dict[str, Any]]:
    """Return all discovered network devices."""
    return db.get_devices()


# ---------------------------------------------------------------------------
# POST /api/devices/update
# ---------------------------------------------------------------------------

@app.post("/api/devices/update", response_model=SuccessResponse, tags=["Devices"])
async def update_devices(payload: DeviceListUpdate) -> SuccessResponse:
    """
    Receive the current device list from Flutter.
    New devices are marked is_new=True; known devices are updated.
    """
    for device in payload.devices:
        db.upsert_device(device.dict())
    await manager.broadcast({"event": "DEVICES_UPDATED", "count": len(payload.devices)})
    return SuccessResponse(detail=f"Processed {len(payload.devices)} devices")


# Legacy alias
@app.get("/api/devices/list", tags=["Devices"])
async def list_devices_legacy() -> List[Dict[str, Any]]:
    return db.get_devices()


@app.post("/api/devices/register", response_model=SuccessResponse, tags=["Devices"])
async def register_device_legacy(device: DeviceInfo) -> SuccessResponse:
    db.upsert_device(device.dict())
    return SuccessResponse()


# ---------------------------------------------------------------------------
# POST /api/predict/coverage
# ---------------------------------------------------------------------------

@app.post("/api/predict/coverage", response_model=CoverageResponse, tags=["Prediction"])
async def predict_coverage(req: CoverageRequest) -> CoverageResponse:
    """
    Accept room dimensions, wall list, and router position.
    Returns a 2-D grid of predicted RSSI using the ITU indoor propagation model.
    """
    walls_dicts = [w.dict() for w in req.walls]
    grid, coverage = compute_coverage_grid(
        router_x=req.router_x,
        router_y=req.router_y,
        width=req.width,
        height=req.height,
        frequency_mhz=float(req.frequency),
        tx_power_dbm=req.tx_power,
        walls=walls_dicts,
        resolution=req.resolution,
    )
    db.save_prediction(
        "coverage",
        req.dict(),
        {"coverage_score": coverage},
    )
    return CoverageResponse(grid=grid, coverage_score=coverage)


# ---------------------------------------------------------------------------
# POST /api/predict/optimal-placement
# ---------------------------------------------------------------------------

@app.post("/api/predict/optimal-placement", response_model=OptimalPlacementResponse, tags=["Prediction"])
async def predict_optimal_placement(req: OptimalPlacementRequest) -> OptimalPlacementResponse:
    """
    Accepts room geometry; runs grid search to find the router position
    that maximises coverage (% area > -70 dBm).
    """
    walls_dicts = [w.dict() for w in req.walls]

    # Run in thread pool to avoid blocking the event loop
    loop = asyncio.get_event_loop()
    best_x, best_y, score, grid = await loop.run_in_executor(
        None,
        lambda: find_optimal_router_position(
            width=req.width,
            height=req.height,
            frequency_mhz=float(req.frequency),
            tx_power_dbm=req.tx_power,
            walls=walls_dicts,
            target_rssi=req.target_rssi,
            resolution=req.resolution,
        ),
    )

    reasoning = build_placement_reasoning(best_x, best_y, score, req.width, req.height)
    db.save_prediction(
        "optimal_placement",
        req.dict(),
        {"best_x": best_x, "best_y": best_y, "coverage_score": score},
    )

    return OptimalPlacementResponse(
        best_x=best_x,
        best_y=best_y,
        coverage_score=score,
        grid=grid,
        reasoning=reasoning,
    )


# ---------------------------------------------------------------------------
# GET /api/ml/status
# ---------------------------------------------------------------------------

@app.get("/api/ml/status", response_model=MLStatus, tags=["ML"])
async def ml_status() -> MLStatus:
    """Returns whether the ML model is trained and its accuracy metrics."""
    s = ml_engine.status()
    return MLStatus(**s)


# ---------------------------------------------------------------------------
# POST /api/ml/train  (manual trigger)
# ---------------------------------------------------------------------------

@app.post("/api/ml/train", tags=["ML"])
async def trigger_training() -> Dict[str, Any]:
    """Manually trigger ML model retraining from accumulated scan data."""
    rows = db.get_training_samples()
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(None, lambda: ml_engine.train(rows))
    return result


# ---------------------------------------------------------------------------
# POST /api/ml/predict
# ---------------------------------------------------------------------------

@app.post("/api/ml/predict", response_model=PredictRSSIResponse, tags=["ML"])
async def predict_rssi_endpoint(req: PredictRSSIRequest) -> PredictRSSIResponse:
    """Predict RSSI given position features."""
    rssi, method, conf = ml_engine.predict(
        distance_m=req.distance_m,
        frequency=req.frequency,
        walls=req.walls,
        time_of_day=req.time_of_day,
        channel=req.channel,
    )
    return PredictRSSIResponse(predicted_rssi=rssi, method=method, confidence=conf)


# ---------------------------------------------------------------------------
# GET /api/history/timeline
# ---------------------------------------------------------------------------

@app.get("/api/history/timeline", response_model=TimelineResponse, tags=["History"])
async def history_timeline(
    limit: int = Query(200, ge=1, le=1000),
) -> TimelineResponse:
    """Return time-sorted scan summaries for the Time Machine screen."""
    entries_raw = db.get_timeline_summary(limit)
    entries = [TimelineEntry(**e) for e in entries_raw]
    return TimelineResponse(entries=entries, total=len(entries))


# ---------------------------------------------------------------------------
# GET /api/alerts
# ---------------------------------------------------------------------------

@app.get("/api/alerts", tags=["Alerts"])
async def get_alerts(
    unread_only: bool = Query(False),
    limit: int = Query(50, ge=1, le=200),
) -> List[AlertItem]:
    """Return security and system alerts."""
    raw = db.get_alerts(unread_only=unread_only, limit=limit)
    return [AlertItem(**r) for r in raw]


@app.patch("/api/alerts/{alert_id}/read", response_model=SuccessResponse, tags=["Alerts"])
async def mark_read(alert_id: int) -> SuccessResponse:
    db.mark_alert_read(alert_id)
    return SuccessResponse(detail=f"Alert {alert_id} marked as read")


# ---------------------------------------------------------------------------
# Admin endpoints (JWT-protected)
# ---------------------------------------------------------------------------

@app.get("/admin/stats", tags=["Admin"])
async def admin_stats(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer),
) -> Dict[str, Any]:
    user = _verify_token(creds)
    history = db.get_scan_history(1)
    devices = db.get_devices()
    alerts = db.get_alerts()
    ml = ml_engine.status()
    return {
        "authenticated_as": user,
        "total_scans":       len(db.get_timeline_summary(10000)),
        "total_devices":     len(devices),
        "unread_alerts":     sum(1 for a in alerts if not a["is_read"]),
        "ml_trained":        ml["is_trained"],
        "latest_scan_ts":    history[0]["timestamp"] if history else None,
    }
