import math
from typing import List, Dict, Any, Tuple

def overlap_weight(target_ch: int, other_ch: int, is_5ghz: bool) -> float:
    if is_5ghz:
        return 1.0 if abs(target_ch - other_ch) < 2 else 0.0
    diff = abs(target_ch - other_ch)
    if diff == 0:
        return 1.0
    if diff >= 5:
        return 0.0
    return 1.0 - (diff / 5.0)

def score_channels(networks: List[Dict[str, Any]], is_5ghz: bool) -> Tuple[int, Dict[int, float]]:
    channels = (
        [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165]
        if is_5ghz else list(range(1, 14))
    )
    
    scores = {ch: 0.0 for ch in channels}
    
    for ch in channels:
        score = 0.0
        for net in networks:
            net_freq = net.get('frequency', 2412)
            net_is_5ghz = net_freq >= 5000
            
            if net_is_5ghz != is_5ghz:
                continue
                
            net_ch = net.get('channel', 1)
            w = overlap_weight(ch, net_ch, is_5ghz)
            if w > 0:
                rssi = net.get('rssi', -100)
                power = 10 ** ((rssi + 30) / 10.0)
                score += w * power
        scores[ch] = score

    # Normalize 0-100 (0 means perfectly clear)
    max_score = max(scores.values()) if scores else 0
    normalized = {}
    for ch, sc in scores.items():
        normalized[ch] = (sc / max_score * 100.0) if max_score > 0 else 0.0
        
    best_channel = min(normalized, key=normalized.get) if normalized else channels[0]
    return best_channel, normalized

def classify_security(capabilities: str) -> Tuple[str, str]:
    cap = capabilities.upper()
    if not cap or ('[ESS]' in cap and 'WPA' not in cap and 'WEP' not in cap):
        return "Open", "This network has NO encryption. Anyone nearby can intercept all your traffic."
    if 'WPA3' in cap:
        return "Strong", "This network uses strong encryption (WPA3). No immediate action required."
    if 'WPA2-EAP' in cap or 'ENTERPRISE' in cap:
        return "Strong", "This network uses strong Enterprise encryption. Highly secure."
    if 'WPA2' in cap or 'RSN' in cap:
        return "Caution", "WPA2-PSK is generally safe, but vulnerable to offline dictionary attacks if you use a weak password."
    if 'WPA' in cap:
        return "Weak", "WPA-TKIP is outdated. Upgrade to WPA2-AES or WPA3."
    if 'WEP' in cap:
        return "Weak", "WEP is broken. It can be cracked in minutes. Upgrade immediately."
    return "Open", "Unable to determine security level."

def itu_path_loss(freq_mhz: float, distance_m: float, n: float = 28.0) -> float:
    if distance_m <= 0:
        distance_m = 0.1
    return 20 * math.log10(freq_mhz) + n * math.log10(distance_m) - 28

def estimate_rssi(tx_power: float, freq_mhz: float, distance_m: float, n: float = 28.0) -> float:
    return tx_power - itu_path_loss(freq_mhz, distance_m, n)

def optimize_placement(
    width: float, height: float, freq: int, tx_power: float, target_rssi: float, res: float
) -> Tuple[float, float, float, List[List[float]]]:
    
    cols = math.ceil(width / res)
    rows = math.ceil(height / res)
    
    best_x, best_y, max_coverage = 0.0, 0.0, -1.0
    best_grid = [[-100.0 for _ in range(cols)] for _ in range(rows)]
    
    for rx in range(cols):
        for ry in range(rows):
            router_x = rx * res
            router_y = ry * res
            
            total = 0
            covered = 0
            
            for cx in range(cols):
                for cy in range(rows):
                    cell_x = cx * res
                    cell_y = cy * res
                    dist = math.sqrt((router_x - cell_x)**2 + (router_y - cell_y)**2)
                    dist = max(dist, 0.1)
                    
                    pred_rssi = estimate_rssi(tx_power, freq, dist)
                    total += 1
                    if pred_rssi >= target_rssi:
                        covered += 1
                        
            coverage = (covered / total) * 100.0 if total > 0 else 0
            if coverage > max_coverage:
                max_coverage = coverage
                best_x = router_x
                best_y = router_y
                
    # Generate grid for best position
    for cx in range(cols):
        for cy in range(rows):
            cell_x = cx * res
            cell_y = cy * res
            dist = math.sqrt((best_x - cell_x)**2 + (best_y - cell_y)**2)
            best_grid[cy][cx] = estimate_rssi(tx_power, freq, max(dist, 0.1))

    return best_x, best_y, max_coverage, best_grid
