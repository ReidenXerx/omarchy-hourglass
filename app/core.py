"""What Hourglass concludes, with no I/O in it, so it can be tested on its own.

A stretch is time with one app in front and you at the keyboard: {"a": app, "s": start, "e": end}, seconds since the
epoch. A pick-up is coming back after five minutes away: {"p": time}. From those this works out the day and the week:
totals, hours, apps, categories, pick-ups, averages and how much of each limit is used. Only the app's class is ever
recorded, never a window title.
"""
from __future__ import annotations

import datetime as dt
import re

APP_MAX = 64
STRETCH_MAX = 3600          # the service flushes every minute, so a longer stretch is not one of ours
MERGE_GAP = 10              # seconds between two stretches of one app that still count as one sitting
CATEGORIES = ["Development", "Web", "Social", "Games", "Entertainment", "Creativity", "Productivity", "Utilities", "Other"]
APP_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._+:@-]{0,63}$")
LABEL_MAX = 60
DETAIL_MIN = 600            # a detail is shown from ten minutes,
DETAIL_SHARE = 0.10         # or a tenth of its app's time,
DETAIL_FLOOR = 120          # but never for less than two minutes
DETAILS_SHOWN = 5


def clean_label(text) -> str:
    """A detail label as the service sent it: printable, one line, short. "" when it is not one."""
    if not isinstance(text, str):
        return ""
    s = "".join(ch for ch in text if ch.isprintable()).strip()
    return s if 0 < len(s) <= LABEL_MAX + 1 else ""


def clean_app(name) -> str:
    s = str(name or "").strip()[:APP_MAX]
    return s if APP_RE.match(s) else ""


def read_stretch(obj, now: float):
    """A stretch or a pick-up read back, or None when it is not one (a torn line, a hand edit, a clock gone wrong)."""
    if not isinstance(obj, dict):
        return None
    if "p" in obj:
        p = obj.get("p")
        if isinstance(p, int) and not isinstance(p, bool) and 0 < p <= now + 120:
            return {"p": p}
        return None
    a, s, e = clean_app(obj.get("a")), obj.get("s"), obj.get("e")
    if not a or not all(isinstance(v, int) and not isinstance(v, bool) for v in (s, e)):
        return None
    if not 0 < e - s <= STRETCH_MAX or e > now + 120:
        return None
    out = {"a": a, "s": s, "e": e}
    d = clean_label(obj.get("d"))
    if d:
        out["d"] = d
    return out


def significant(details: dict[str, int], app_seconds: int) -> list[dict]:
    """The details worth showing for an app: ten minutes or a tenth of its time (never under two minutes), the
    five biggest, and the rest as one "Other" line when anything was shown."""
    ranked = sorted(details.items(), key=lambda kv: (-kv[1], kv[0]))
    shown = [{"label": k, "seconds": v} for k, v in ranked
             if v >= DETAIL_FLOOR and (v >= DETAIL_MIN or v >= DETAIL_SHARE * app_seconds)][:DETAILS_SHOWN]
    if shown:
        rest = app_seconds - sum(x["seconds"] for x in shown)
        if rest >= DETAIL_FLOOR:
            shown.append({"label": "Other", "seconds": rest})
    return shown


# ---------------------------------------------------------------- days

def midnight(t: float) -> int:
    d = dt.datetime.fromtimestamp(t)
    return int(dt.datetime(d.year, d.month, d.day).timestamp())


def day_key(t: float) -> str:
    return dt.datetime.fromtimestamp(t).strftime("%Y-%m-%d")


def split_hours(s: int, e: int) -> list[tuple[int, int]]:
    """(hour of the day, seconds) for a stretch, split where it crosses an hour (by the local clock)."""
    out = []
    t = s
    while t < e:
        d = dt.datetime.fromtimestamp(t)
        next_hour = int((d.replace(minute=0, second=0, microsecond=0) + dt.timedelta(hours=1)).timestamp())
        end = min(e, next_hour)
        out.append((d.hour, end - t))
        t = end
    return out


def summarise_day(records: list[dict], start: int, end: int, resolve) -> dict:
    """One day: total, by hour, by app, by category, pick-ups, the longest sitting. `resolve(app)` gives
    {"name", "category"} for an app class."""
    hours = [0] * 24
    apps: dict[str, int] = {}
    details: dict[str, dict[str, int]] = {}
    pickups = []
    stretches = []
    for r in records:
        if "p" in r:
            if start <= r["p"] < end:
                pickups.append(r["p"])
            continue
        s, e = max(r["s"], start), min(r["e"], end)
        if e <= s:
            continue
        stretches.append((r["a"], s, e))
        apps[r["a"]] = apps.get(r["a"], 0) + (e - s)
        if r.get("d"):
            per = details.setdefault(r["a"], {})
            per[r["d"]] = per.get(r["d"], 0) + (e - s)
        for hour, seconds in split_hours(s, e):
            hours[hour] += seconds
    cats: dict[str, int] = {}
    listed = []
    for app, seconds in sorted(apps.items(), key=lambda kv: -kv[1]):
        info = resolve(app)
        cats[info["category"]] = cats.get(info["category"], 0) + seconds
        listed.append({"app": app, "name": info["name"], "category": info["category"], "seconds": seconds,
                       "details": significant(details.get(app, {}), seconds), "raw": details.get(app, {})})
    pick_hours = [0] * 24
    for p in pickups:
        pick_hours[dt.datetime.fromtimestamp(p).hour] += 1
    return {
        "total": sum(apps.values()),
        "hours": hours,
        "apps": listed,
        "categories": [{"name": c, "seconds": cats[c]} for c in sorted(cats, key=lambda c: -cats[c])],
        "pickups": len(pickups),
        "firstPickup": min(pickups) if pickups else None,
        "busiestPickupHour": pick_hours.index(max(pick_hours)) if pickups else None,
        "longest": longest_sitting(stretches),
    }


def longest_sitting(stretches: list[tuple[str, int, int]]) -> dict | None:
    """The longest time in one app without leaving it for more than a few seconds."""
    best = None
    current = None
    for app, s, e in sorted(stretches, key=lambda x: x[1]):
        if current and current[0] == app and s - current[2] <= MERGE_GAP:
            current = (app, current[1], max(current[2], e))
        else:
            current = (app, s, e)
        if best is None or current[2] - current[1] > best[2] - best[1]:
            best = current
    return {"app": best[0], "seconds": best[2] - best[1], "start": best[1]} if best else None


def day_totals(summary: dict, date: str) -> dict:
    """What is kept of a day for a year: its total, top apps, categories and pick-ups."""
    det = {}
    for a in summary["apps"][:12]:
        top = dict(sorted(a.get("raw", {}).items(), key=lambda kv: -kv[1])[:8])
        if top:
            det[a["app"]] = top
    out = {"d": date, "t": summary["total"], "p": summary["pickups"],
           "apps": {a["app"]: a["seconds"] for a in summary["apps"][:12]},
           "cats": {c["name"]: c["seconds"] for c in summary["categories"]}}
    if det:
        out["det"] = det
    return out


def read_totals(obj) -> dict | None:
    if not isinstance(obj, dict) or not isinstance(obj.get("d"), str) or not re.match(r"^\d{4}-\d{2}-\d{2}$", obj["d"]):
        return None
    t, p = obj.get("t"), obj.get("p")
    if not isinstance(t, int) or not 0 <= t <= 86400 or not isinstance(p, int) or not 0 <= p <= 10000:
        return None
    apps = {clean_app(k): v for k, v in (obj.get("apps") or {}).items()
            if clean_app(k) and isinstance(v, int) and 0 <= v <= 86400} if isinstance(obj.get("apps"), dict) else {}
    cats = {k: v for k, v in (obj.get("cats") or {}).items()
            if k in CATEGORIES and isinstance(v, int) and 0 <= v <= 86400} if isinstance(obj.get("cats"), dict) else {}
    det = {}
    if isinstance(obj.get("det"), dict):
        for app, per in list(obj["det"].items())[:12]:
            if clean_app(app) and isinstance(per, dict):
                kept = {clean_label(k): v for k, v in list(per.items())[:8]
                        if clean_label(k) and isinstance(v, int) and 0 <= v <= 86400}
                if kept:
                    det[clean_app(app)] = kept
    return {"d": obj["d"], "t": t, "p": p, "apps": apps, "cats": cats, "det": det}


# ---------------------------------------------------------------- the week, averages and limits

def average(totals: list[dict], before: str, days: int = 7) -> float | None:
    """The mean daily total over the `days` days with data before `before`."""
    seen = [x["t"] for x in sorted(totals, key=lambda x: x["d"]) if x["d"] < before and x["t"] > 0][-days:]
    return sum(seen) / len(seen) if seen else None


def week(totals: list[dict], today: dict, today_key: str) -> dict:
    """The last seven days, today included, and how they compare with the seven before."""
    by_day = {x["d"]: x for x in totals}
    by_day[today_key] = {"d": today_key, "t": today["total"], "p": today["pickups"],
                         "apps": {a["app"]: a["seconds"] for a in today["apps"]},
                         "cats": {c["name"]: c["seconds"] for c in today["categories"]},
                         "det": {a["app"]: a.get("raw", {}) for a in today["apps"] if a.get("raw")}}
    end = dt.date.fromisoformat(today_key)
    days = [(end - dt.timedelta(days=k)).isoformat() for k in range(6, -1, -1)]
    before = [(end - dt.timedelta(days=k)).isoformat() for k in range(13, 6, -1)]
    this_total = sum(by_day.get(d, {"t": 0})["t"] for d in days)
    prev = [by_day[d]["t"] for d in before if d in by_day]
    apps: dict[str, int] = {}
    cats: dict[str, int] = {}
    det: dict[str, dict[str, int]] = {}
    for d in days:
        for a, s in by_day.get(d, {}).get("apps", {}).items():
            apps[a] = apps.get(a, 0) + s
        for a, per in by_day.get(d, {}).get("det", {}).items():
            into = det.setdefault(a, {})
            for k, v in per.items():
                into[k] = into.get(k, 0) + v
        for c, s in by_day.get(d, {}).get("cats", {}).items():
            cats[c] = cats.get(c, 0) + s
    return {
        "days": [{"d": d, "seconds": by_day.get(d, {"t": 0})["t"]} for d in days],
        "total": this_total,
        "previous": sum(prev) if prev else None,
        "pickups": sum(by_day.get(d, {"p": 0})["p"] for d in days),
        "apps": [{"app": a, "seconds": s, "details": significant(det.get(a, {}), s)}
                 for a, s in sorted(apps.items(), key=lambda kv: -kv[1])[:12]],
        "categories": [{"name": c, "seconds": s} for c, s in sorted(cats.items(), key=lambda kv: -kv[1])],
    }


def without_details(obj):
    """A stored record with its detail taken out, for "Forget details"."""
    if isinstance(obj, dict):
        return {k: v for k, v in obj.items() if k not in ("d", "det")}
    return obj


def parse_limits(text) -> list[dict]:
    """Limits as the settings keep them: "app:brave=60; cat:Games=90" (minutes a day)."""
    out = []
    for part in str(text or "").split(";")[:24]:
        m = re.match(r"^\s*(app|cat):([^=;]{1,64})=(\d{1,4})\s*$", part)
        if not m:
            continue
        kind, key, minutes = m.group(1), m.group(2).strip(), int(m.group(3))
        if kind == "app" and not clean_app(key):
            continue
        if kind == "cat" and key not in CATEGORIES:
            continue
        if 1 <= minutes <= 1440:
            out.append({"kind": kind, "key": key if kind == "cat" else clean_app(key), "minutes": minutes})
    return out


def limits_text(limits: list[dict]) -> str:
    return "; ".join(f"{x['kind']}:{x['key']}={x['minutes']}" for x in limits)


def limit_use(limits: list[dict], today: dict) -> list[dict]:
    apps = {a["app"]: a["seconds"] for a in today["apps"]}
    cats = {c["name"]: c["seconds"] for c in today["categories"]}
    out = []
    for x in limits:
        used = apps.get(x["key"], 0) if x["kind"] == "app" else cats.get(x["key"], 0)
        out.append(dict(x, used=used, left=max(0, x["minutes"] * 60 - used)))
    return out


def spell(seconds: int) -> str:
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{minutes} min"
    return f"{minutes // 60} h {minutes % 60:02d} min" if minutes % 60 else f"{minutes // 60} h"


def weekly_text(w: dict) -> str:
    line = f"{spell(w['total'])} at the laptop this week"
    if w["previous"]:
        change = round(100 * (w["total"] - w["previous"]) / w["previous"])
        line += f", {abs(change)}% {'more' if change > 0 else 'less'} than last week" if change else ", the same as last week"
    if w["apps"]:
        line += f". Most of it in {w['apps'][0]['app']} ({spell(w['apps'][0]['seconds'])})."
    return line
