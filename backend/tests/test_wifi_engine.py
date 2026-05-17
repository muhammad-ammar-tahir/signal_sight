import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from wifi_engine import channel_congestion_score, security_classify, compute_coverage_grid

def test_channel_congestion_score_24ghz():
    networks = [
        {"channel": 1, "rssi": -50, "bssid": "aa", "ssid": "Net1"},
        {"channel": 1, "rssi": -60, "bssid": "bb", "ssid": "Net2"},
        {"channel": 6, "rssi": -70, "bssid": "cc", "ssid": "Net3"},
        {"channel": 11, "rssi": -80, "bssid": "dd", "ssid": "Net4"},
    ]
    best_ch, scores, details = channel_congestion_score(networks, is_5ghz=False)
    assert best_ch == 13 # 13 is furthest from 1, 6, 11
    assert scores[1] > scores[11]

def test_security_classify_wpa3():
    capabilities = "[WPA3-PSK-CCMP][ESS]"
    proto, risk, advice, score, enc = security_classify(capabilities)
    assert proto == "WPA3-SAE"
    assert risk == "LOW"
    assert score == 8

def test_security_classify_open():
    capabilities = "[ESS]"
    proto, risk, advice, score, enc = security_classify(capabilities)
    assert proto == "Open"
    assert risk == "CRITICAL"
    assert score == 100

def test_compute_coverage_grid():
    grid, score = compute_coverage_grid(
        router_x=5.0, router_y=5.0,
        width=10.0, height=10.0,
        frequency_mhz=2412,
        tx_power_dbm=20,
        walls=[],
        resolution=1.0
    )
    assert len(grid) == 10
    assert len(grid[0]) == 10
    assert score > 0
