"""Hourglass's history: keeping stretches, summarising days, and answering the panel.

Shared by the command line (bin/hourglass, which the Omarchy edition calls) and the recorder service (the Plasma
edition), so both keep and read the same files the same way.
"""
from __future__ import annotations

import datetime as dt
import re

import apps
import core
import store

KEEP_DAYS = 30
SUMMARY_DAYS = 40           # how far back a missing day summary is filled in
KEY_RE = re.compile(r"^(app|cat):[A-Za-z0-9 ._+:@-]{1,64}\|(five|done)$")


def keep(batch, now: float) -> None:
    """Write checked stretches and pick-ups; a stretch across midnight is kept as two, one in each day's file."""
    for item in (batch if isinstance(batch, list) else [])[:5000]:
        r = core.read_stretch(item, now)
        if r is None:
            continue
        if "p" in r:
            store.append("days", store.day_name(r["p"]), r)
            continue
        s, e = r["s"], r["e"]
        while s < e:
            next_midnight = int(dt.datetime.combine(dt.date.fromtimestamp(s) + dt.timedelta(days=1), dt.time()).timestamp())
            cut = min(e, next_midnight)
            part = {"a": r["a"], "s": s, "e": cut}
            if r.get("d"):
                part["d"] = r["d"]
            store.append("days", store.day_name(s), part)
            s = cut
    summarise_past(now)
    store.prune("days", KEEP_DAYS, dt.date.fromtimestamp(now))
    store.prune("totals", 800, dt.date.fromtimestamp(now))


def day_records(day: dt.date, now: float) -> list[dict]:
    rows = store.read_lines("days", day.isoformat() + ".jsonl")
    return [r for r in (core.read_stretch(x, now) for x in rows) if r]


def all_totals(now: float) -> list[dict]:
    year = dt.date.fromtimestamp(now).year
    rows = store.read_lines("totals", f"{year - 1}.jsonl", 2 * 1024 * 1024) + \
        store.read_lines("totals", f"{year}.jsonl", 2 * 1024 * 1024)
    out = {}
    for r in rows:
        t = core.read_totals(r)
        if t:
            out[t["d"]] = t
    return list(out.values())


def summarise_past(now: float) -> None:
    """Keep two years of days: summarise each finished day that has no summary yet."""
    done = {t["d"] for t in all_totals(now)}
    today = dt.date.fromtimestamp(now)
    resolve = apps.Resolver()
    for k in range(SUMMARY_DAYS, 0, -1):
        day = today - dt.timedelta(days=k)
        if day.isoformat() in done:
            continue
        records = day_records(day, now)
        if not records:
            continue
        start = int(dt.datetime.combine(day, dt.time()).timestamp())
        summary = core.summarise_day(records, start, start + 86400 + 3600, resolve)
        store.append("totals", f"{day.year}.jsonl", core.day_totals(summary, day.isoformat()))


def build_report(limits_text: str, now: float) -> dict:
    today = dt.date.fromtimestamp(now)
    start = int(dt.datetime.combine(today, dt.time()).timestamp())
    resolve = apps.Resolver()
    day = core.summarise_day(day_records(today, now), start, int(now) + 1, resolve)
    totals = all_totals(now)
    avg = core.average(totals, today.isoformat())
    w = core.week(totals, day, today.isoformat())
    for a in w["apps"]:
        info = resolve(a["app"])
        a["name"], a["category"] = info["name"], info["category"]
    for a in day["apps"]:
        a.pop("raw", None)      # only the significant details leave the helper
    limits = core.limit_use(core.parse_limits(str(limits_text)[:2000]), day)
    for x in limits:
        x["name"] = resolve(x["key"])["name"] if x["kind"] == "app" else x["key"]
    told_today = sorted({r["k"] for r in store.read_lines("state", "told.jsonl", 256 * 1024)
                         if isinstance(r, dict) and r.get("d") == today.isoformat() and isinstance(r.get("k"), str)})[:100]
    return {"now": int(now), "today": day, "average": round(avg) if avg is not None else None, "week": w,
            "limits": limits, "categories": core.CATEGORIES, "told": told_today}


def weekly_due(now: float) -> str:
    """This week's summary the first time it is asked for after Sunday 20:00, and "" otherwise."""
    d = dt.datetime.fromtimestamp(now)
    if d.isoweekday() != 7 or d.hour < 20:
        return ""
    week_id = f"{d.isocalendar()[0]}-W{d.isocalendar()[1]:02d}"
    sent = {r.get("w") for r in store.read_lines("state", "weekly.jsonl", 64 * 1024) if isinstance(r, dict)}
    if week_id in sent:
        return ""
    today = d.date()
    start = int(dt.datetime.combine(today, dt.time()).timestamp())
    resolve = apps.Resolver()
    day = core.summarise_day(day_records(today, now), start, int(now) + 1, resolve)
    w = core.week(all_totals(now), day, today.isoformat())
    if w["total"] <= 0:
        return ""
    for a in w["apps"]:
        a["app"] = resolve(a["app"])["name"]
    store.append("state", "weekly.jsonl", {"w": week_id})
    return core.weekly_text(w)


def forget_details() -> None:
    for sub in ("days", "totals"):
        key = "d" if sub == "days" else "det"
        for name in store.names(sub):
            rows = store.read_lines(sub, name, 2 * 1024 * 1024 if sub == "totals" else store.DAY_MAX)
            if any(isinstance(r, dict) and key in r for r in rows):
                store.rewrite(sub, name, [core.without_details(r, sub) for r in rows])


def told(key: str) -> bool:
    if not KEY_RE.match(key):
        return False
    today = dt.date.today().isoformat()
    rows = store.read_lines("state", "told.jsonl", 256 * 1024)
    kept = [r for r in rows if isinstance(r, dict) and r.get("d") == today]
    if not any(r.get("k") == key for r in kept):
        store.rewrite("state", "told.jsonl", kept[-200:] + [{"d": today, "k": key}])
    return True
