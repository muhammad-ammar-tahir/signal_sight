"""
SignalSight – Database Layer
Handles all SQLite persistence via raw sqlite3 connections.
Thread-safe via check_same_thread=False and serialised writes.
"""

import sqlite3
import json
import threading
from typing import Any, Dict, List, Optional
from datetime import datetime
from core.config import settings

DB_FILE = settings.DATABASE_URL.replace("sqlite:///", "")
_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Connection helpers
# ---------------------------------------------------------------------------

def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_FILE, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    return conn


# ---------------------------------------------------------------------------
# Schema initialisation
# ---------------------------------------------------------------------------

def init_db() -> None:
    """Create all tables if they do not exist."""
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()

        cur.executescript("""
            CREATE TABLE IF NOT EXISTS scan_history (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp      TEXT    NOT NULL,
                networks_json  TEXT    NOT NULL,
                network_count  INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_scan_ts ON scan_history(timestamp DESC);

            CREATE TABLE IF NOT EXISTS devices (
                mac         TEXT PRIMARY KEY,
                ip          TEXT,
                vendor      TEXT    DEFAULT 'Unknown',
                device_type TEXT    DEFAULT 'unknown',
                hostname    TEXT,
                first_seen  TEXT    NOT NULL,
                last_seen   TEXT    NOT NULL,
                is_new      INTEGER DEFAULT 1,
                is_flagged  INTEGER DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_dev_last ON devices(last_seen DESC);

            CREATE TABLE IF NOT EXISTS alerts (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp   TEXT    NOT NULL,
                alert_type  TEXT    NOT NULL,
                severity    TEXT    NOT NULL DEFAULT 'INFO',
                bssid       TEXT,
                message     TEXT    NOT NULL,
                is_read     INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS channel_analysis (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp    TEXT    NOT NULL,
                band         TEXT    NOT NULL,
                best_channel INTEGER NOT NULL,
                scores_json  TEXT    NOT NULL,
                reasoning    TEXT
            );

            CREATE TABLE IF NOT EXISTS predictions (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp     TEXT    NOT NULL,
                prediction_type TEXT  NOT NULL,
                input_json    TEXT    NOT NULL,
                output_json   TEXT    NOT NULL
            );

            CREATE TABLE IF NOT EXISTS ml_training_samples (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp    TEXT    NOT NULL,
                distance_m   REAL    NOT NULL,
                frequency    INTEGER NOT NULL,
                walls        INTEGER NOT NULL DEFAULT 0,
                time_of_day  REAL    NOT NULL DEFAULT 0.0,
                channel      INTEGER NOT NULL DEFAULT 6,
                rssi         REAL    NOT NULL
            );

            CREATE TABLE IF NOT EXISTS user_settings (
                key   TEXT PRIMARY KEY,
                value TEXT
            );
        """)

        conn.commit()
        conn.close()


# ---------------------------------------------------------------------------
# Scan history
# ---------------------------------------------------------------------------

def save_scan(timestamp: datetime, networks: List[Dict[str, Any]]) -> int:
    """Persist a WiFi scan snapshot.  Returns the new row id."""
    ts_str = timestamp.isoformat()
    networks_json = json.dumps(networks, default=str)
    count = len(networks)

    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO scan_history (timestamp, networks_json, network_count) VALUES (?,?,?)",
            (ts_str, networks_json, count),
        )
        new_id = cur.lastrowid
        # Keep only the 1 000 most-recent snapshots
        cur.execute("""
            DELETE FROM scan_history
            WHERE id NOT IN (
                SELECT id FROM scan_history ORDER BY timestamp DESC LIMIT 1000
            )
        """)
        conn.commit()
        conn.close()

    # Ingest training samples from the scan
    _ingest_training_samples(timestamp, networks)
    return new_id


def _ingest_training_samples(timestamp: datetime, networks: List[Dict[str, Any]]) -> None:
    """Derive ML training rows from a newly uploaded scan."""
    if not networks:
        return
    ts_str = timestamp.isoformat()
    hour_frac = timestamp.hour + timestamp.minute / 60.0
    rows = []
    for net in networks:
        rssi = net.get("rssi", -100)
        freq = net.get("frequency", 2412)
        ch = net.get("channel", 1)
        # Approximate distance via free-space path loss inversion (rough seed)
        import math
        try:
            pl = 20 * math.log10(max(freq, 1)) + 20 * math.log10(1.0) - 147.55
            estimated_dist = max(0.5, 10 ** ((pl - (rssi - 20)) / 20))
        except Exception:
            estimated_dist = 5.0
        rows.append((ts_str, round(estimated_dist, 2), freq, 1, hour_frac, ch, float(rssi)))

    with _lock:
        conn = _get_conn()
        conn.executemany(
            """INSERT INTO ml_training_samples
               (timestamp, distance_m, frequency, walls, time_of_day, channel, rssi)
               VALUES (?,?,?,?,?,?,?)""",
            rows,
        )
        conn.commit()
        conn.close()


def get_scan_history(limit: int = 100, bssid_filter: Optional[str] = None) -> List[Dict[str, Any]]:
    """Return recent scans, optionally filtered to those containing a specific BSSID."""
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, timestamp, networks_json, network_count FROM scan_history "
            "ORDER BY timestamp DESC LIMIT ?",
            (limit,),
        )
        rows = cur.fetchall()
        conn.close()

    result = []
    for row in rows:
        networks = json.loads(row["networks_json"])
        if bssid_filter:
            networks = [n for n in networks if n.get("bssid") == bssid_filter]
            if not networks:
                continue
        result.append(
            {
                "id": row["id"],
                "timestamp": row["timestamp"],
                "networks": networks,
                "network_count": row["network_count"],
            }
        )
    return result


def get_timeline_summary(limit: int = 200) -> List[Dict[str, Any]]:
    """Return lightweight timeline entries for the Time Machine view."""
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, timestamp, network_count FROM scan_history "
            "ORDER BY timestamp DESC LIMIT ?",
            (limit,),
        )
        rows = cur.fetchall()
        conn.close()

    return [{"id": r["id"], "timestamp": r["timestamp"], "network_count": r["network_count"]} for r in rows]


def get_scan_by_id(scan_id: int) -> Optional[Dict[str, Any]]:
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute("SELECT id, timestamp, networks_json FROM scan_history WHERE id=?", (scan_id,))
        row = cur.fetchone()
        conn.close()
    if row is None:
        return None
    return {"id": row["id"], "timestamp": row["timestamp"], "networks": json.loads(row["networks_json"])}


# ---------------------------------------------------------------------------
# Devices
# ---------------------------------------------------------------------------

def upsert_device(device: Dict[str, Any]) -> None:
    mac = device["mac"]
    now = datetime.utcnow().isoformat()
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute("SELECT mac FROM devices WHERE mac=?", (mac,))
        existing = cur.fetchone()
        if existing:
            cur.execute(
                "UPDATE devices SET ip=?, last_seen=?, is_new=0, hostname=? WHERE mac=?",
                (device.get("ip"), device.get("last_seen", now), device.get("hostname"), mac),
            )
        else:
            cur.execute(
                """INSERT INTO devices (mac, ip, vendor, device_type, hostname, first_seen, last_seen, is_new)
                   VALUES (?,?,?,?,?,?,?,1)""",
                (
                    mac,
                    device.get("ip"),
                    device.get("vendor", "Unknown"),
                    device.get("device_type", "unknown"),
                    device.get("hostname"),
                    device.get("first_seen", now),
                    device.get("last_seen", now),
                ),
            )
        conn.commit()
        conn.close()


def get_devices() -> List[Dict[str, Any]]:
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT mac, ip, vendor, device_type, hostname, first_seen, last_seen, is_new, is_flagged "
            "FROM devices ORDER BY last_seen DESC"
        )
        rows = cur.fetchall()
        conn.close()
    return [dict(r) for r in rows]


def flag_device(mac: str, flagged: bool) -> None:
    with _lock:
        conn = _get_conn()
        conn.execute("UPDATE devices SET is_flagged=? WHERE mac=?", (1 if flagged else 0, mac))
        conn.commit()
        conn.close()


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------

def create_alert(alert_type: str, message: str, severity: str = "INFO", bssid: Optional[str] = None) -> None:
    now = datetime.utcnow().isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute(
            "INSERT INTO alerts (timestamp, alert_type, severity, bssid, message) VALUES (?,?,?,?,?)",
            (now, alert_type, severity, bssid, message),
        )
        conn.commit()
        conn.close()


def get_alerts(unread_only: bool = False, limit: int = 50) -> List[Dict[str, Any]]:
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        if unread_only:
            cur.execute(
                "SELECT * FROM alerts WHERE is_read=0 ORDER BY timestamp DESC LIMIT ?", (limit,)
            )
        else:
            cur.execute("SELECT * FROM alerts ORDER BY timestamp DESC LIMIT ?", (limit,))
        rows = cur.fetchall()
        conn.close()
    return [dict(r) for r in rows]


def mark_alert_read(alert_id: int) -> None:
    with _lock:
        conn = _get_conn()
        conn.execute("UPDATE alerts SET is_read=1 WHERE id=?", (alert_id,))
        conn.commit()
        conn.close()


# ---------------------------------------------------------------------------
# Channel analysis
# ---------------------------------------------------------------------------

def save_channel_analysis(band: str, best_channel: int, scores: Dict[int, float], reasoning: str) -> None:
    now = datetime.utcnow().isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute(
            "INSERT INTO channel_analysis (timestamp, band, best_channel, scores_json, reasoning) VALUES (?,?,?,?,?)",
            (now, band, best_channel, json.dumps(scores), reasoning),
        )
        conn.commit()
        conn.close()


# ---------------------------------------------------------------------------
# Predictions
# ---------------------------------------------------------------------------

def save_prediction(prediction_type: str, input_data: Dict, output_data: Dict) -> None:
    now = datetime.utcnow().isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute(
            "INSERT INTO predictions (timestamp, prediction_type, input_json, output_json) VALUES (?,?,?,?)",
            (now, prediction_type, json.dumps(input_data), json.dumps(output_data)),
        )
        conn.commit()
        conn.close()


# ---------------------------------------------------------------------------
# ML training data access
# ---------------------------------------------------------------------------

def get_training_samples() -> List[Dict[str, Any]]:
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT distance_m, frequency, walls, time_of_day, channel, rssi "
            "FROM ml_training_samples ORDER BY id DESC LIMIT 10000"
        )
        rows = cur.fetchall()
        conn.close()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

def get_setting(key: str, default: str = "") -> str:
    with _lock:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute("SELECT value FROM user_settings WHERE key=?", (key,))
        row = cur.fetchone()
        conn.close()
    return row["value"] if row else default


def set_setting(key: str, value: str) -> None:
    with _lock:
        conn = _get_conn()
        conn.execute(
            "INSERT OR REPLACE INTO user_settings (key, value) VALUES (?,?)", (key, value)
        )
        conn.commit()
        conn.close()


# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

init_db()
