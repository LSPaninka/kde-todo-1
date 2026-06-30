"""util.py - date / formatting / JSON / color helpers.

Timestamps are kept as Unix epoch milliseconds (int). Display always uses the
machine's local timezone, mirroring the original KDE plasmoid.
"""
from __future__ import annotations
import time
from datetime import datetime, timedelta, timezone

from gi.repository import Gdk

DAY_MS = 86400000


def now_ms() -> int:
    return int(time.time() * 1000)


def _local(ms: int) -> datetime:
    return datetime.fromtimestamp(ms / 1000)


def start_of_day_ms(ms: int) -> int:
    d = _local(ms).replace(hour=0, minute=0, second=0, microsecond=0)
    return int(d.timestamp() * 1000)


def sunday_of(ms: int) -> int:
    """Local midnight of the Sunday opening the week containing ms."""
    midnight = start_of_day_ms(ms)
    d = _local(midnight)
    # Python weekday(): Mon=0 .. Sun=6 -> we want Sun=0 offset.
    dow = (d.weekday() + 1) % 7
    return midnight - dow * DAY_MS


def add_days_ms(ms: int, days: int) -> int:
    d = _local(ms) + timedelta(days=days)
    return int(d.timestamp() * 1000)


def same_day(a: int, b: int) -> bool:
    da, db = _local(a), _local(b)
    return da.year == db.year and da.timetuple().tm_yday == db.timetuple().tm_yday


def fmt_hm(sec: int) -> str:
    if sec <= 0:
        return "0"
    h, m = sec // 3600, (sec % 3600) // 60
    if h and m:
        return f"{h}h {m}m"
    if h:
        return f"{h}h"
    return f"{m}m"


def fmt_clock(ms: int) -> str:
    d = _local(ms)
    return f"{d.hour:02d}:{d.minute:02d}"


_MONTHS_SHORT = ["Ene", "Feb", "Mar", "Abr", "May", "Jun",
                 "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
_MONTHS_LONG = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]


def short_month(m0: int) -> str:
    return _MONTHS_SHORT[m0] if 0 <= m0 <= 11 else ""


def month_name(m0: int) -> str:
    return _MONTHS_LONG[m0] if 0 <= m0 <= 11 else ""


def fmt_jira_started(ms: int) -> str:
    """Jira wants 2026-05-12T15:00:00.000+0000 (local offset)."""
    d = _local(ms).astimezone()
    off = d.utcoffset() or timedelta(0)
    total = int(off.total_seconds())
    sign = "+" if total >= 0 else "-"
    total = abs(total)
    return (f"{d.year:04d}-{d.month:02d}-{d.day:02d}T"
            f"{d.hour:02d}:{d.minute:02d}:{d.second:02d}.000"
            f"{sign}{total // 3600:02d}{(total % 3600) // 60:02d}")


def fmt_jql_date(ms: int) -> str:
    d = _local(ms)
    return f"{d.year:04d}-{d.month:02d}-{d.day:02d}"


def fmt_utc_iso(ms: int) -> str:
    """Clockify wants 2026-05-12T15:00:00.000Z."""
    d = datetime.fromtimestamp(ms / 1000, tz=timezone.utc)
    return (f"{d.year:04d}-{d.month:02d}-{d.day:02d}T"
            f"{d.hour:02d}:{d.minute:02d}:{d.second:02d}.{(ms % 1000):03d}Z")


def parse_iso(s: str | None) -> int:
    """Parse an ISO-8601 timestamp (Jira/Clockify) to epoch ms. 0 on failure."""
    if not s:
        return 0
    txt = s.strip()
    # Normalise: trailing Z -> +00:00, and bare +0000 offset -> +00:00.
    candidates = [txt]
    if txt.endswith("Z"):
        candidates.append(txt[:-1] + "+00:00")
    if len(txt) >= 5 and txt[-5] in "+-" and txt[-3] != ":":
        candidates.append(txt[:-2] + ":" + txt[-2:])
        if txt.endswith("Z"):
            pass
    for cand in candidates:
        try:
            dt = datetime.fromisoformat(cand)
            return int(dt.timestamp() * 1000)
        except (ValueError, TypeError):
            continue
    return 0


def hex_rgba(hex_str: str | None, alpha: float = 1.0) -> Gdk.RGBA:
    c = Gdk.RGBA()
    c.red = c.green = c.blue = 0.5
    c.alpha = alpha
    if not hex_str:
        return c
    h = hex_str.strip()
    if not h.startswith("#") or len(h) < 7:
        return c
    try:
        c.red = int(h[1:3], 16) / 255.0
        c.green = int(h[3:5], 16) / 255.0
        c.blue = int(h[5:7], 16) / 255.0
        c.alpha = alpha
    except ValueError:
        pass
    return c


# ----- null-safe JSON access over plain dict/list (json.loads output) -----

def js_str(obj, key) -> str:
    if not isinstance(obj, dict):
        return ""
    v = obj.get(key)
    if isinstance(v, str):
        return v
    if isinstance(v, (int, float)):
        return str(v)
    return ""


def js_int(obj, key) -> int:
    if not isinstance(obj, dict):
        return 0
    v = obj.get(key)
    if isinstance(v, bool):
        return 0
    if isinstance(v, (int, float)):
        return int(v)
    if isinstance(v, str):
        try:
            return int(v)
        except ValueError:
            return 0
    return 0


def js_has_num(obj, key) -> bool:
    return isinstance(obj, dict) and isinstance(obj.get(key), (int, float)) and not isinstance(obj.get(key), bool)


def js_bool(obj, key) -> bool:
    return isinstance(obj, dict) and obj.get(key) is True


def js_obj(obj, key):
    if isinstance(obj, dict):
        v = obj.get(key)
        if isinstance(v, dict):
            return v
    return None


def js_arr(obj, key):
    if isinstance(obj, dict):
        v = obj.get(key)
        if isinstance(v, list):
            return v
    return None
