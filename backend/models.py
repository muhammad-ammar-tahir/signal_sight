"""
SignalSight – Pydantic request / response schemas.
All models are fully typed with validation defaults.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime

from pydantic import BaseModel, Field, validator


# ---------------------------------------------------------------------------
# Core WiFi data
# ---------------------------------------------------------------------------

class WifiNetwork(BaseModel):
    ssid: str = ""
    bssid: str
    rssi: int = Field(..., ge=-120, le=0)
    frequency: int = 2412
    capabilities: str = ""
    channel: int = 1
    security: str = "Unknown"
    security_tag: str = "Unknown"
    vendor: str = "Unknown"
    is_own: bool = False

    @validator("bssid")
    def bssid_lower(cls, v: str) -> str:
        return v.lower()


class ScanUploadRequest(BaseModel):
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    networks: List[WifiNetwork]


class ScanHistoryEntry(BaseModel):
    id: int
    timestamp: str
    networks: List[WifiNetwork]
    network_count: int


# ---------------------------------------------------------------------------
# Channel analysis
# ---------------------------------------------------------------------------

class ChannelScore(BaseModel):
    channel: int
    score: float          # 0 = clear, 100 = fully congested
    ap_count: int
    max_rssi: int


class ChannelRecommendation(BaseModel):
    band: str
    best_channel: int
    congestion_scores: Dict[int, float]
    channel_details: List[ChannelScore] = []
    reasoning: str = ""
    generated_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Security audit
# ---------------------------------------------------------------------------

class SecurityAdvice(BaseModel):
    bssid: str
    ssid: str
    security_protocol: str
    risk_level: str          # CRITICAL / HIGH / MEDIUM / LOW
    risk_score: int          # 0-100
    remediation: str
    encryption_details: str = ""


class SecurityAudit(BaseModel):
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    total_networks: int
    vulnerable_count: int
    secure_count: int
    risk_summary: str
    vulnerable_networks: List[SecurityAdvice]
    secure_networks: List[SecurityAdvice]


# ---------------------------------------------------------------------------
# Device discovery
# ---------------------------------------------------------------------------

class DeviceInfo(BaseModel):
    ip: str
    mac: str
    vendor: str = "Unknown"
    device_type: str = "unknown"
    hostname: Optional[str] = None
    first_seen: Optional[str] = None
    last_seen: Optional[str] = None
    is_new: bool = True
    is_flagged: bool = False


class DeviceListUpdate(BaseModel):
    devices: List[DeviceInfo]


# ---------------------------------------------------------------------------
# Coverage / placement prediction
# ---------------------------------------------------------------------------

class WallConfig(BaseModel):
    x1: float
    y1: float
    x2: float
    y2: float
    material: str = "drywall"  # drywall | concrete | glass | brick | metal


class CoverageRequest(BaseModel):
    router_x: float
    router_y: float
    frequency: int = 2437
    tx_power: float = 20.0          # dBm
    walls: List[WallConfig] = []
    width: float = 10.0             # metres
    height: float = 10.0
    resolution: float = 0.5         # metres per grid cell


class CoverageCell(BaseModel):
    x: float
    y: float
    rssi: float


class CoverageResponse(BaseModel):
    grid: List[List[float]]         # rows × cols of predicted RSSI
    coverage_score: float           # % cells ≥ target_rssi
    target_rssi: float = -70.0


class OptimalPlacementRequest(BaseModel):
    width: float
    height: float
    frequency: int = 2437
    tx_power: float = 20.0
    walls: List[WallConfig] = []
    target_rssi: float = -70.0
    resolution: float = 0.5


class OptimalPlacementResponse(BaseModel):
    best_x: float
    best_y: float
    coverage_score: float
    grid: List[List[float]]
    reasoning: str = ""


# ---------------------------------------------------------------------------
# ML / model status
# ---------------------------------------------------------------------------

class MLStatus(BaseModel):
    is_trained: bool
    sample_count: int
    mae: Optional[float] = None      # Mean Absolute Error dBm
    rmse: Optional[float] = None
    last_trained: Optional[str] = None
    model_type: str = "RandomForestRegressor"
    fallback: str = "ITU P.1238 indoor model"


class PredictRSSIRequest(BaseModel):
    distance_m: float = Field(..., gt=0)
    frequency: int = 2437
    walls: int = Field(0, ge=0)
    time_of_day: float = Field(12.0, ge=0, le=24)
    channel: int = 6


class PredictRSSIResponse(BaseModel):
    predicted_rssi: float
    method: str
    confidence: Optional[float] = None


# ---------------------------------------------------------------------------
# History / Time Machine
# ---------------------------------------------------------------------------

class TimelineEntry(BaseModel):
    id: int
    timestamp: str
    network_count: int


class TimelineResponse(BaseModel):
    entries: List[TimelineEntry]
    total: int


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------

class AlertItem(BaseModel):
    id: int
    timestamp: str
    alert_type: str
    severity: str
    bssid: Optional[str]
    message: str
    is_read: bool


# ---------------------------------------------------------------------------
# Generic success
# ---------------------------------------------------------------------------

class SuccessResponse(BaseModel):
    status: str = "success"
    detail: str = ""
