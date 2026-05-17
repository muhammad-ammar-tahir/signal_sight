"""
SignalSight – WiFi Engine
Real implementations of every analytical algorithm used by the backend.

Algorithms
----------
* channel_congestion_score  – weighted interference model (energy-overlap)
* security_classify         – full capability-string parser → risk label + advice
* itu_indoor_path_loss      – ITU-R P.1238 (2017) indoor propagation model
* wall_attenuation          – material-based dB loss for each wall crossed
* ray_cast_walls            – count walls between two points using line-segment
                              intersection (Liang–Barsky)
* compute_coverage_grid     – builds a 2-D RSSI map for a given router position
* find_optimal_router_position – brute-force grid search for max coverage area
"""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional, Tuple


# ===========================================================================
# 1. Channel congestion scoring
# ===========================================================================

# 2.4 GHz non-overlapping channels and all valid channels
_24_CHANNELS = list(range(1, 14))
_5_CHANNELS = [
    36, 40, 44, 48,
    52, 56, 60, 64,
    100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140,
    149, 153, 157, 161, 165,
]

# For 2.4 GHz each channel is 5 MHz wide; co-channel = full weight,
# adjacent channels share energy proportional to spectral overlap (22 MHz HT20).
_24GHZ_OVERLAP_RANGE = 5   # channels within this range have partial overlap


def _overlap_weight_24(target: int, other: int) -> float:
    """Return the fractional spectral overlap [0, 1] between two 2.4 GHz channels."""
    diff = abs(target - other)
    if diff == 0:
        return 1.0
    if diff >= _24GHZ_OVERLAP_RANGE:
        return 0.0
    return 1.0 - diff / _24GHZ_OVERLAP_RANGE


def _overlap_weight_5(target: int, other: int) -> float:
    """5 GHz channels are non-overlapping when separated by ≥4 channel units."""
    diff = abs(target - other)
    if diff == 0:
        return 1.0
    if diff < 4:
        return 0.5  # partial overlap (bonded / wide channel leakage)
    return 0.0


def channel_congestion_score(
    networks: List[Dict[str, Any]], is_5ghz: bool = False
) -> Tuple[int, Dict[int, float], List[Dict[str, Any]]]:
    """
    Compute per-channel congestion for either band.

    Score is based on aggregate received power (mW) weighted by spectral
    overlap, then normalised to [0, 100].  Lower score = less congested.

    Returns
    -------
    best_channel : int
    normalised_scores : {channel: score}
    channel_details  : [{channel, score, ap_count, max_rssi}]
    """
    channels = _5_CHANNELS if is_5ghz else _24_CHANNELS
    raw_scores: Dict[int, float] = {ch: 0.0 for ch in channels}
    ap_count:   Dict[int, int]   = {ch: 0 for ch in channels}
    max_rssi:   Dict[int, int]   = {ch: -120 for ch in channels}

    for net in networks:
        freq = net.get("frequency", 2412)
        net_is_5ghz = freq >= 5000
        if net_is_5ghz != is_5ghz:
            continue

        net_ch = net.get("channel", 1)
        rssi = int(net.get("rssi", -100))

        # Convert RSSI (dBm) → linear power (mW)  [reference: 0 dBm = 1 mW]
        power_mw = 10 ** (rssi / 10.0)

        for ch in channels:
            w = _overlap_weight_5(ch, net_ch) if is_5ghz else _overlap_weight_24(ch, net_ch)
            if w > 0:
                raw_scores[ch] += w * power_mw
                if w == 1.0:          # only count APs actually ON this channel
                    ap_count[ch] += 1
                    if rssi > max_rssi[ch]:
                        max_rssi[ch] = rssi

    # Normalise to [0, 100]
    max_val = max(raw_scores.values()) if raw_scores else 0.0
    normalised: Dict[int, float] = {}
    for ch, sc in raw_scores.items():
        normalised[ch] = round((sc / max_val * 100.0) if max_val > 0 else 0.0, 2)

    best_channel = min(normalised, key=lambda c: (normalised[c], c))

    details = [
        {
            "channel": ch,
            "score": normalised[ch],
            "ap_count": ap_count[ch],
            "max_rssi": max_rssi[ch] if ap_count[ch] > 0 else None,
        }
        for ch in channels
    ]

    return best_channel, normalised, details


def build_channel_reasoning(
    best_channel: int, scores: Dict[int, float], is_5ghz: bool
) -> str:
    """Generate a human-readable explanation for the recommendation."""
    band = "5 GHz" if is_5ghz else "2.4 GHz"
    score = scores.get(best_channel, 0.0)
    competing = sorted(scores.items(), key=lambda x: x[1])[:3]
    top_str = ", ".join(f"Ch {c} ({s:.0f}%)" for c, s in competing)
    return (
        f"Channel {best_channel} is recommended for the {band} band with a congestion "
        f"score of {score:.0f}/100 (lower is better). "
        f"Least-congested candidates: {top_str}. "
        f"{'Avoid channels 1, 6, 11 if neighbours are already on them.' if not is_5ghz else 'Prefer UNII-1 (36-48) for best regulatory support.'}"
    )


# ===========================================================================
# 2. Security classification
# ===========================================================================

_RISK_MATRIX = {
    "WPA3":           ("WPA3-SAE",          "LOW",      8,   "No immediate action required. WPA3 provides strong protection."),
    "WPA2-EAP":       ("WPA2-Enterprise",   "LOW",      12,  "Enterprise 802.1X authentication. Highly secure."),
    "WPA2":           ("WPA2-PSK",          "MEDIUM",   40,  "Generally secure but vulnerable to offline dictionary attacks if a weak passphrase is used. Use a 16+ character random passphrase."),
    "RSN":            ("WPA2-PSK (RSN)",    "MEDIUM",   40,  "RSN detected (WPA2). Use a strong passphrase of 16+ characters."),
    "WPA-EAP":        ("WPA-Enterprise",    "MEDIUM",   45,  "WPA Enterprise is acceptable but WPA2-Enterprise is strongly preferred."),
    "WPA":            ("WPA-TKIP",          "HIGH",     70,  "WPA-TKIP is deprecated. TKIP is vulnerable to practical attacks. Upgrade to WPA2-AES or WPA3 immediately."),
    "WEP":            ("WEP",               "CRITICAL", 95,  "WEP is completely broken and can be cracked in minutes. Replace router firmware or hardware and enable WPA3/WPA2 now."),
}


def security_classify(capabilities: str) -> Tuple[str, str, str, int, str]:
    """
    Parse an Android WifiScanResult capabilities string.

    Returns
    -------
    protocol        : str  – e.g. "WPA2-PSK"
    risk_level      : str  – CRITICAL / HIGH / MEDIUM / LOW
    remediation     : str  – plain-language advice
    risk_score      : int  – 0-100
    encryption_detail: str – extra info about cipher suite
    """
    cap = capabilities.upper() if capabilities else ""

    # Open network: has ESS flag but no encryption markers
    if not cap or (("ESS" in cap or cap == "") and
                   "WPA" not in cap and "WEP" not in cap and "RSN" not in cap):
        return (
            "Open",
            "CRITICAL",
            "This network has NO encryption. All traffic is transmitted in plaintext. "
            "Anyone within range can intercept passwords, sessions, and private data. "
            "Enable WPA3 or WPA2-AES on the router immediately.",
            100,
            "No cipher suite detected",
        )

    # Walk priority order
    for key, (proto, risk, score, advice) in _RISK_MATRIX.items():
        if key in cap:
            # Refine cipher details
            cipher = "CCMP" if "CCMP" in cap else ("TKIP" if "TKIP" in cap else "Unknown")
            detail = f"Cipher: {cipher}"
            if key == "WPA2" and "CCMP" in cap:
                risk = "LOW"
                score = 15
                advice = "WPA2-AES (CCMP) is secure. Consider upgrading to WPA3 when hardware allows."
            return proto, risk, advice, score, detail

    return (
        "Unknown",
        "MEDIUM",
        "Security capabilities could not be fully determined. Treat as untrusted.",
        50,
        cap[:80],
    )


# ===========================================================================
# 3. ITU-R P.1238 indoor path-loss model
# ===========================================================================

# Distance Power Loss Coefficient n per ITU P.1238 (Table 2)
_ITU_N: Dict[str, float] = {
    "office":       30.0,
    "commercial":   22.0,
    "residential":  28.0,
}

# Floor attenuation factor Lf (dB) – single floor
_FLOOR_ATT: Dict[str, float] = {
    "office":       16.0,
    "commercial":   17.0,
    "residential":  18.0,
}

# Material-specific wall attenuation (dB) per IEEE 802.11 channel model
WALL_ATT_DB: Dict[str, float] = {
    "drywall":  3.0,
    "glass":    2.0,
    "wood":     4.0,
    "brick":    8.0,
    "concrete": 12.0,
    "metal":    20.0,
}


def itu_indoor_path_loss(
    frequency_mhz: float,
    distance_m: float,
    walls: List[str] | None = None,
    environment: str = "residential",
    floors: int = 0,
) -> float:
    """
    Calculate indoor path loss in dB using ITU-R P.1238.

    Formula:
        L = 20·log10(f) + N·log10(d) + Lf·n_floors - 28  [dB]
    where:
        f  = frequency (MHz)
        d  = distance (m), clamped to ≥0.1 m
        N  = distance power loss coefficient
        Lf = floor attenuation factor
        n  = number of floors penetrated

    Wall losses are added on top of the free-space ITU formula.

    Returns path loss in dB (positive number).
    """
    d = max(0.1, distance_m)
    N = _ITU_N.get(environment, 28.0)
    Lf = _FLOOR_ATT.get(environment, 18.0)

    # Core ITU formula
    pl = 20 * math.log10(frequency_mhz) + N * math.log10(d) - 28.0

    # Floor penetration loss
    if floors > 0:
        pl += Lf * floors

    # Per-wall attenuation
    if walls:
        for material in walls:
            pl += WALL_ATT_DB.get(material.lower(), 3.0)

    return pl


def predict_rssi_itu(
    tx_power_dbm: float,
    frequency_mhz: float,
    distance_m: float,
    walls: List[str] | None = None,
    environment: str = "residential",
    floors: int = 0,
) -> float:
    """Return predicted RSSI at the receiver (dBm)."""
    pl = itu_indoor_path_loss(frequency_mhz, distance_m, walls, environment, floors)
    return tx_power_dbm - pl


# ===========================================================================
# 4. Wall ray-casting (Liang–Barsky line-segment intersection)
# ===========================================================================

def _liang_barsky(
    x0: float, y0: float, x1: float, y1: float,
    wx0: float, wy0: float, wx1: float, wy1: float,
) -> bool:
    """Return True if segment (x0,y0)→(x1,y1) intersects wall segment (wx0,wy0)→(wx1,wy1)."""
    dx, dy = x1 - x0, y1 - y0
    wx_dx, wy_dy = wx1 - wx0, wy1 - wy0
    denom = dx * wy_dy - dy * wx_dx
    if abs(denom) < 1e-9:
        return False  # parallel
    t = ((wx0 - x0) * wy_dy - (wy0 - y0) * wx_dx) / denom
    u = ((wx0 - x0) * dy - (wy0 - y0) * dx) / denom
    return 0.0 < t < 1.0 and 0.0 < u < 1.0


def count_walls_crossed(
    rx: float, ry: float, cx: float, cy: float,
    walls: List[Dict[str, Any]],
) -> Tuple[int, List[str]]:
    """
    Count how many wall segments lie between router (rx,ry) and cell (cx,cy).

    Returns (count, list_of_materials).
    """
    crossed_materials: List[str] = []
    for wall in walls:
        if _liang_barsky(
            rx, ry, cx, cy,
            wall["x1"], wall["y1"], wall["x2"], wall["y2"],
        ):
            crossed_materials.append(wall.get("material", "drywall"))
    return len(crossed_materials), crossed_materials


# ===========================================================================
# 5. Coverage grid computation
# ===========================================================================

def compute_coverage_grid(
    router_x: float,
    router_y: float,
    width: float,
    height: float,
    frequency_mhz: float,
    tx_power_dbm: float,
    walls: List[Dict[str, Any]],
    resolution: float = 0.5,
    environment: str = "residential",
    target_rssi: float = -70.0,
) -> Tuple[List[List[float]], float]:
    """
    Compute a 2-D grid of predicted RSSI values.

    Returns
    -------
    grid           : rows × cols of RSSI dBm values
    coverage_score : percentage of cells with RSSI ≥ target_rssi
    """
    cols = max(1, math.ceil(width / resolution))
    rows = max(1, math.ceil(height / resolution))

    grid: List[List[float]] = []
    covered = 0
    total = 0

    for ry_idx in range(rows):
        row_vals: List[float] = []
        cy = ry_idx * resolution + resolution / 2
        for cx_idx in range(cols):
            cx = cx_idx * resolution + resolution / 2
            dist = math.sqrt((router_x - cx) ** 2 + (router_y - cy) ** 2)
            dist = max(dist, 0.1)

            # Wall loss
            _, materials = count_walls_crossed(router_x, router_y, cx, cy, walls)

            rssi = predict_rssi_itu(tx_power_dbm, frequency_mhz, dist, materials, environment)
            rssi = round(max(-120.0, min(0.0, rssi)), 1)
            row_vals.append(rssi)
            total += 1
            if rssi >= target_rssi:
                covered += 1

        grid.append(row_vals)

    coverage_score = (covered / total * 100.0) if total > 0 else 0.0
    return grid, round(coverage_score, 2)


# ===========================================================================
# 6. Optimal router placement (brute-force grid search)
# ===========================================================================

def find_optimal_router_position(
    width: float,
    height: float,
    frequency_mhz: float,
    tx_power_dbm: float,
    walls: List[Dict[str, Any]],
    target_rssi: float = -70.0,
    resolution: float = 0.5,
    environment: str = "residential",
) -> Tuple[float, float, float, List[List[float]]]:
    """
    Grid-search router placement that maximises coverage (% area ≥ target_rssi).

    Returns
    -------
    best_x, best_y   : optimal router position (metres)
    best_coverage    : coverage score [0-100]
    best_grid        : RSSI grid for the optimal position
    """
    cols = max(1, math.ceil(width / resolution))
    rows = max(1, math.ceil(height / resolution))

    best_x, best_y = width / 2, height / 2
    best_coverage = -1.0
    best_grid: List[List[float]] = []

    # Candidate router positions (every other cell to keep runtime reasonable)
    step = max(1, int(1.0 / resolution))  # ~1 m steps
    for rx_idx in range(0, cols, step):
        for ry_idx in range(0, rows, step):
            rx = rx_idx * resolution + resolution / 2
            ry = ry_idx * resolution + resolution / 2

            grid, coverage = compute_coverage_grid(
                rx, ry, width, height, frequency_mhz, tx_power_dbm,
                walls, resolution, environment, target_rssi,
            )
            if coverage > best_coverage:
                best_coverage = coverage
                best_x, best_y = rx, ry
                best_grid = grid

    # If step skipping may have missed, do a final fine-search around the winner
    fine_step = 1
    for rx_idx in range(
        max(0, int(best_x / resolution) - step),
        min(cols, int(best_x / resolution) + step + 1),
        fine_step,
    ):
        for ry_idx in range(
            max(0, int(best_y / resolution) - step),
            min(rows, int(best_y / resolution) + step + 1),
            fine_step,
        ):
            rx = rx_idx * resolution + resolution / 2
            ry = ry_idx * resolution + resolution / 2
            grid, coverage = compute_coverage_grid(
                rx, ry, width, height, frequency_mhz, tx_power_dbm,
                walls, resolution, environment, target_rssi,
            )
            if coverage > best_coverage:
                best_coverage = coverage
                best_x, best_y = rx, ry
                best_grid = grid

    return best_x, best_y, round(best_coverage, 2), best_grid


def build_placement_reasoning(
    best_x: float, best_y: float, coverage: float, width: float, height: float
) -> str:
    pct_x = best_x / width * 100
    pct_y = best_y / height * 100
    return (
        f"Optimal router position: ({best_x:.1f} m, {best_y:.1f} m) — "
        f"{pct_x:.0f}% across the room width, {pct_y:.0f}% along the room depth. "
        f"This position achieves {coverage:.1f}% area coverage above the –70 dBm threshold. "
        "Place the router at this location, elevated (≥1.5 m off the floor) and away from "
        "metal appliances or concrete walls for best real-world performance."
    )
