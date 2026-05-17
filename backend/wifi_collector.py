"""
SignalSight – WiFi Collector
Standalone script that performs a real WiFi scan using system tools,
then uploads the results to the running FastAPI backend.

Supported platforms
-------------------
* Windows  – `netsh wlan show networks mode=bssid`
* Linux    – `iwlist <iface> scanning`

Run independently:
    python wifi_collector.py --url http://127.0.0.1:8000/api/scan/upload --interval 30

Or import and call `collect_and_upload()` programmatically.
"""

from __future__ import annotations

import argparse
import json
import logging
import platform
import re
import subprocess
import sys
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

import urllib.request
import urllib.error

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)


# ---------------------------------------------------------------------------
# Frequency ↔ Channel helpers
# ---------------------------------------------------------------------------

def freq_to_channel(freq_mhz: int) -> int:
    if 2412 <= freq_mhz <= 2484:
        if freq_mhz == 2484:
            return 14
        return (freq_mhz - 2412) // 5 + 1
    if 5170 <= freq_mhz <= 5825:
        return (freq_mhz - 5170) // 5 + 34
    return 0


def channel_to_freq(channel: int) -> int:
    if 1 <= channel <= 13:
        return 2412 + (channel - 1) * 5
    if channel == 14:
        return 2484
    if 34 <= channel <= 165:
        return 5170 + (channel - 34) * 5
    return 2437


# ---------------------------------------------------------------------------
# Security tag helper
# ---------------------------------------------------------------------------

def _security_tag(caps: str) -> str:
    c = caps.upper()
    if "WPA3" in c:
        return "WPA3"
    if "WPA2" in c or "RSN" in c:
        return "WPA2"
    if "WPA" in c:
        return "WPA"
    if "WEP" in c:
        return "WEP"
    return "Open"


def _security_label(caps: str) -> str:
    tag = _security_tag(caps)
    if tag == "WPA3":
        return "WPA3-SAE"
    if tag == "WPA2":
        return "WPA2-PSK"
    if tag == "WPA":
        return "WPA-TKIP"
    if tag == "WEP":
        return "WEP"
    return "Open"


# ---------------------------------------------------------------------------
# Windows scanner – netsh
# ---------------------------------------------------------------------------

def _scan_windows() -> List[Dict[str, Any]]:
    """
    Parse `netsh wlan show networks mode=bssid` output.
    Returns a list of network dicts matching the API schema.
    """
    try:
        result = subprocess.run(
            ["netsh", "wlan", "show", "networks", "mode=bssid"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        output = result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logger.error("netsh failed: %s", e)
        return []

    networks: List[Dict[str, Any]] = []
    current: Dict[str, Any] = {}

    # netsh outputs a block per SSID, each BSSID is a sub-entry
    # We collect all BSSID sub-entries and link them to the last seen SSID
    current_ssid = ""
    current_caps  = ""

    for line in output.splitlines():
        line = line.strip()

        m_ssid = re.match(r"^SSID\s+\d+\s*:\s*(.*)$", line, re.IGNORECASE)
        if m_ssid:
            current_ssid = m_ssid.group(1).strip()
            current_caps  = ""
            continue

        m_auth = re.match(r"^Authentication\s*:\s*(.+)$", line, re.IGNORECASE)
        if m_auth:
            auth = m_auth.group(1).strip().upper()
            if "WPA3" in auth:
                current_caps = "[WPA3][ESS]"
            elif "WPA2" in auth:
                current_caps = "[WPA2][RSN][CCMP][ESS]"
            elif "WPA" in auth:
                current_caps = "[WPA][TKIP][ESS]"
            elif "WEP" in auth:
                current_caps = "[WEP][ESS]"
            else:
                current_caps = "[ESS]"
            continue

        m_bssid = re.match(r"^BSSID\s+\d+\s*:\s*([\da-fA-F:]{17})$", line, re.IGNORECASE)
        if m_bssid:
            if current:
                networks.append(current)
            current = {
                "ssid":         current_ssid,
                "bssid":        m_bssid.group(1).lower(),
                "rssi":         -80,
                "frequency":    2437,
                "capabilities": current_caps,
                "channel":      6,
                "security":     _security_label(current_caps),
                "security_tag": _security_tag(current_caps),
                "vendor":       "Unknown",
                "is_own":       False,
            }
            continue

        m_signal = re.match(r"^Signal\s*:\s*(\d+)%$", line, re.IGNORECASE)
        if m_signal and current:
            pct = int(m_signal.group(1))
            # Convert percentage (0-100) → approximate dBm (-100 to -50)
            current["rssi"] = int(-100 + pct / 2)
            continue

        m_channel = re.match(r"^Channel\s*:\s*(\d+)$", line, re.IGNORECASE)
        if m_channel and current:
            ch = int(m_channel.group(1))
            current["channel"]   = ch
            current["frequency"] = channel_to_freq(ch)
            continue

    if current:
        networks.append(current)

    logger.info("[Windows] Found %d networks", len(networks))
    return networks


# ---------------------------------------------------------------------------
# Linux scanner – iwlist
# ---------------------------------------------------------------------------

def _find_wifi_interface_linux() -> Optional[str]:
    """Return the first wireless interface name."""
    try:
        out = subprocess.check_output(["iwconfig"], stderr=subprocess.STDOUT,
                                      text=True, timeout=5)
        for line in out.splitlines():
            m = re.match(r"^(\w+)\s+IEEE 802\.11", line)
            if m:
                return m.group(1)
    except Exception:
        pass
    # Try /proc/net/wireless
    try:
        with open("/proc/net/wireless") as f:
            for line in f.readlines()[2:]:
                iface = line.split(":")[0].strip()
                if iface:
                    return iface
    except Exception:
        pass
    return None


def _scan_linux() -> List[Dict[str, Any]]:
    """Parse `iwlist <iface> scanning` output."""
    iface = _find_wifi_interface_linux()
    if not iface:
        logger.error("No wireless interface found on Linux.")
        return []

    try:
        result = subprocess.run(
            ["iwlist", iface, "scanning"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = result.stdout + result.stderr
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logger.error("iwlist failed: %s", e)
        return []

    networks: List[Dict[str, Any]] = []
    current: Dict[str, Any] = {}

    for line in output.splitlines():
        line = line.strip()

        if line.startswith("Cell "):
            if current:
                networks.append(current)
            m = re.search(r"Address:\s*([\da-fA-F:]{17})", line, re.IGNORECASE)
            bssid = m.group(1).lower() if m else "00:00:00:00:00:00"
            current = {
                "ssid":         "",
                "bssid":        bssid,
                "rssi":         -80,
                "frequency":    2437,
                "capabilities": "",
                "channel":      6,
                "security":     "Unknown",
                "security_tag": "Unknown",
                "vendor":       "Unknown",
                "is_own":       False,
            }
            continue

        m_essid = re.search(r'ESSID:"(.*?)"', line)
        if m_essid and current:
            current["ssid"] = m_essid.group(1)

        m_freq = re.search(r"Frequency:([\d.]+)\s*GHz", line, re.IGNORECASE)
        if m_freq and current:
            freq_ghz = float(m_freq.group(1))
            freq_mhz = int(freq_ghz * 1000)
            current["frequency"] = freq_mhz
            current["channel"]   = freq_to_channel(freq_mhz)

        m_ch = re.search(r"Channel[:\s]+(\d+)", line, re.IGNORECASE)
        if m_ch and current and current["channel"] == 0:
            ch = int(m_ch.group(1))
            current["channel"]   = ch
            current["frequency"] = channel_to_freq(ch)

        m_signal = re.search(r"Signal level[=:](-?\d+)\s*dBm", line, re.IGNORECASE)
        if m_signal and current:
            current["rssi"] = int(m_signal.group(1))

        m_enc = re.search(r"Encryption key:(on|off)", line, re.IGNORECASE)
        if m_enc and current:
            current["capabilities"] += "[ESS]" if m_enc.group(1) == "off" else ""

        m_ie = re.search(r"IE:\s*(.+)$", line, re.IGNORECASE)
        if m_ie and current:
            ie = m_ie.group(1).upper()
            if "WPA VERSION 2" in ie or "WPA2" in ie or "RSN" in ie:
                current["capabilities"] = "[WPA2][RSN][CCMP][ESS]"
            elif "WPA VERSION 1" in ie or ("WPA" in ie and "WPA2" not in ie):
                current["capabilities"] = "[WPA][TKIP][ESS]"
            elif "WEP" in ie:
                current["capabilities"] = "[WEP][ESS]"

    if current:
        networks.append(current)

    # Back-fill security labels
    for net in networks:
        caps = net["capabilities"]
        net["security"]     = _security_label(caps)
        net["security_tag"] = _security_tag(caps)

    logger.info("[Linux] Found %d networks via %s", len(networks), iface)
    return networks


# ---------------------------------------------------------------------------
# macOS scanner – airport (optional)
# ---------------------------------------------------------------------------

def _scan_macos() -> List[Dict[str, Any]]:
    airport = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    try:
        result = subprocess.run([airport, "-s"], capture_output=True, text=True, timeout=30)
        output = result.stdout
    except Exception as e:
        logger.error("airport failed: %s", e)
        return []

    networks: List[Dict[str, Any]] = []
    for line in output.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 5:
            continue
        try:
            ssid    = parts[0]
            bssid   = parts[1].lower()
            rssi    = int(parts[2])
            channel = int(parts[3].split(",")[0])
            caps    = " ".join(parts[6:]).upper() if len(parts) > 6 else ""
            freq    = channel_to_freq(channel)
            networks.append({
                "ssid":         ssid,
                "bssid":        bssid,
                "rssi":         rssi,
                "frequency":    freq,
                "capabilities": caps,
                "channel":      channel,
                "security":     _security_label(caps),
                "security_tag": _security_tag(caps),
                "vendor":       "Unknown",
                "is_own":       False,
            })
        except (ValueError, IndexError):
            continue

    logger.info("[macOS] Found %d networks", len(networks))
    return networks


# ---------------------------------------------------------------------------
# Platform dispatcher
# ---------------------------------------------------------------------------

def scan_wifi() -> List[Dict[str, Any]]:
    """Perform a real WiFi scan for the current platform."""
    system = platform.system().lower()
    if system == "windows":
        return _scan_windows()
    if system == "linux":
        return _scan_linux()
    if system == "darwin":
        return _scan_macos()
    logger.warning("Unsupported platform: %s", system)
    return []


# ---------------------------------------------------------------------------
# Upload to FastAPI
# ---------------------------------------------------------------------------

def upload_to_backend(networks: List[Dict[str, Any]], url: str) -> bool:
    """POST scan results to the FastAPI /api/scan/upload endpoint."""
    payload = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "networks":  networks,
    }
    data = json.dumps(payload).encode("utf-8")
    req  = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
            logger.info("Upload success – HTTP %d", status)
            return True
    except urllib.error.HTTPError as e:
        logger.error("Upload HTTP error %d: %s", e.code, e.read().decode())
    except urllib.error.URLError as e:
        logger.error("Upload connection error: %s", e.reason)
    return False


# ---------------------------------------------------------------------------
# Collect-and-upload loop
# ---------------------------------------------------------------------------

def collect_and_upload(url: str = "http://127.0.0.1:8000/api/scan/upload") -> None:
    """Single scan cycle: scan → upload."""
    networks = scan_wifi()
    if not networks:
        logger.warning("No networks found; skipping upload.")
        return
    upload_to_backend(networks, url)


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="SignalSight WiFi Collector")
    parser.add_argument(
        "--url",
        default="http://127.0.0.1:8000/api/scan/upload",
        help="FastAPI upload endpoint",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=0,
        help="Repeat interval in seconds (0 = run once)",
    )
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print scanned networks without uploading",
    )
    args = parser.parse_args()

    if args.print_only:
        nets = scan_wifi()
        print(json.dumps(nets, indent=2))
        return

    if args.interval > 0:
        logger.info("Collecting every %d s – press Ctrl+C to stop", args.interval)
        while True:
            collect_and_upload(args.url)
            time.sleep(args.interval)
    else:
        collect_and_upload(args.url)


if __name__ == "__main__":
    main()
