#!/usr/bin/python3 -I
"""Hourglass's conclusions, its app lookup and its helper, on made-up days with known answers."""
from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "app"))
import apps  # noqa: E402
import core  # noqa: E402

DAY = dt.date(2026, 10, 14)
T0 = int(dt.datetime(2026, 10, 14, 0, 0).timestamp())
NOW = T0 + 86400 * 3


def plain(app):
    return {"name": app.title(), "category": "Games" if app == "cs2" else "Web" if app == "brave" else "Development"}


def h(hours, minutes=0):
    return T0 + hours * 3600 + minutes * 60


class Reading(unittest.TestCase):
    def test_only_real_stretches_and_pickups_are_read(self):
        self.assertEqual(core.read_stretch({"a": "brave", "s": h(9), "e": h(9, 5)}, NOW), {"a": "brave", "s": h(9), "e": h(9, 5)})
        self.assertEqual(core.read_stretch({"p": h(9)}, NOW), {"p": h(9)})
        for bad in ({"a": "../etc", "s": h(9), "e": h(9, 1)}, {"a": "brave", "s": h(9), "e": h(9)},
                    {"a": "brave", "s": h(9), "e": h(11)}, {"a": "brave", "s": h(9), "e": NOW + 9999},
                    {"a": "brave", "s": True, "e": h(9)}, {"p": -1}, [], "x", {"a": "<b>", "s": h(9), "e": h(9, 1)}):
            self.assertIsNone(core.read_stretch(bad, NOW), bad)

    def test_hours_split_where_the_clock_does(self):
        self.assertEqual(core.split_hours(h(9, 50), h(11, 10)), [(9, 600), (10, 3600), (11, 600)])


class Day(unittest.TestCase):
    def records(self):
        return [{"a": "brave", "s": h(9), "e": h(9, 30)}, {"a": "zed", "s": h(9, 30), "e": h(10, 45)},
                {"a": "zed", "s": h(10, 45, ) + 5, "e": h(11, 30)}, {"a": "cs2", "s": h(22), "e": h(23)},
                {"p": h(9)}, {"p": h(14)}, {"p": h(14, 30)}]

    def test_a_day_adds_up(self):
        d = core.summarise_day(self.records(), T0, T0 + 86400, plain)
        self.assertEqual(d["total"], 1800 + 4500 + 2695 + 3600)
        self.assertEqual(sum(d["hours"]), d["total"])
        self.assertEqual(d["hours"][22], 3600)
        self.assertEqual([a["app"] for a in d["apps"]], ["zed", "cs2", "brave"])
        self.assertEqual(d["categories"][0], {"name": "Development", "seconds": 7195})
        self.assertEqual((d["pickups"], d["firstPickup"], d["busiestPickupHour"]), (3, h(9), 14))

    def test_the_longest_sitting_bridges_a_blink(self):
        d = core.summarise_day(self.records(), T0, T0 + 86400, plain)
        self.assertEqual(d["longest"], {"app": "zed", "seconds": 7200, "start": h(9, 30)})

    def test_an_empty_day(self):
        d = core.summarise_day([], T0, T0 + 86400, plain)
        self.assertEqual((d["total"], d["pickups"], d["longest"], d["firstPickup"]), (0, 0, None, None))


class Week(unittest.TestCase):
    def test_week_average_and_comparison(self):
        totals = [{"d": (DAY - dt.timedelta(days=k)).isoformat(), "t": 3600 * (k % 3 + 1), "p": 5,
                   "apps": {"zed": 1800}, "cats": {"Development": 1800}} for k in range(1, 14)]
        today = core.summarise_day([{"a": "zed", "s": h(9), "e": h(10)}], T0, T0 + 86400, plain)
        w = core.week(totals, today, DAY.isoformat())
        self.assertEqual(len(w["days"]), 7)
        self.assertEqual(w["days"][-1], {"d": DAY.isoformat(), "seconds": 3600})
        self.assertEqual(w["total"], 3600 + sum(3600 * (k % 3 + 1) for k in range(1, 7)))
        self.assertEqual(w["previous"], sum(3600 * (k % 3 + 1) for k in range(7, 14)))
        self.assertEqual(w["apps"][0]["app"], "zed")
        self.assertAlmostEqual(core.average(totals, DAY.isoformat()), sum(3600 * (k % 3 + 1) for k in range(1, 8)) / 7)
        self.assertIsNone(core.average([], DAY.isoformat()))
        self.assertIn("less than last week", core.weekly_text(w))

    def test_saved_totals_are_checked(self):
        self.assertIsNotNone(core.read_totals({"d": "2026-10-14", "t": 100, "p": 2, "apps": {"zed": 50}, "cats": {"Development": 50}}))
        self.assertIsNone(core.read_totals({"d": "../x", "t": 1, "p": 1}))
        self.assertIsNone(core.read_totals({"d": "2026-10-14", "t": 999999, "p": 1}))
        self.assertEqual(core.read_totals({"d": "2026-10-14", "t": 1, "p": 0, "apps": {"<x>": 5}, "cats": {"Nope": 1}})["apps"], {})


class Limits(unittest.TestCase):
    def test_limits_parse_strictly_and_count_use(self):
        limits = core.parse_limits("app:cs2=60; cat:Web=30; cat:Nope=10; app:../x=5; app:zed=0; garbage")
        self.assertEqual(limits, [{"kind": "app", "key": "cs2", "minutes": 60}, {"kind": "cat", "key": "Web", "minutes": 30}])
        self.assertEqual(core.limits_text(limits), "app:cs2=60; cat:Web=30")
        today = core.summarise_day([{"a": "cs2", "s": h(20), "e": h(20, 50)}, {"a": "brave", "s": h(21), "e": h(21, 40)}],
                                   T0, T0 + 86400, plain)
        use = core.limit_use(limits, today)
        self.assertEqual([(u["used"], u["left"]) for u in use], [(3000, 600), (2400, 0)])


class Lookup(unittest.TestCase):
    def test_entries_by_class_file_name_and_tail(self):
        with tempfile.TemporaryDirectory() as d:
            def entry(name, body):
                pathlib.Path(d, name).write_text("[Desktop Entry]\n" + body)
            entry("brave-browser.desktop", "Name=Brave\nCategories=Network;WebBrowser;\nStartupWMClass=brave-browser\n")
            entry("org.gnome.Nautilus.desktop", "Name=Files\nCategories=GNOME;System;FileManager;\n")
            entry("chat.desktop", "Name=Chatty\nCategories=Network;InstantMessaging;\nStartupWMClass=ChattyApp\n")
            entry("big.desktop", "Name=Big\n" + "x" * 70000)
            os.symlink("/etc/passwd", os.path.join(d, "evil.desktop"))
            r = apps.Resolver([d])
            self.assertEqual(r("brave-browser"), {"name": "Brave", "category": "Web"})
            self.assertEqual(r("ChattyApp"), {"name": "Chatty", "category": "Social"})
            self.assertEqual(r("org.gnome.Nautilus"), {"name": "Files", "category": "Utilities"})
            self.assertEqual(r("cs2"), {"name": "Counter-Strike 2", "category": "Games"})
            self.assertEqual(r("steam_app_570"), {"name": "steam_app_570", "category": "Games"})
            self.assertEqual(r("unknown.app"), {"name": "unknown.app", "category": "Other"})
            self.assertNotIn("evil", r.by_file)


class Helper(unittest.TestCase):
    def run_helper(self, *args, stdin=b""):
        env = {"PATH": "/usr/bin", "HOME": self.tmp.name, "XDG_STATE_HOME": self.tmp.name, "XDG_DATA_HOME": self.tmp.name}
        return subprocess.run(["/usr/bin/python3", "-I", str(ROOT / "bin" / "hourglass"), *args], input=stdin,
                               capture_output=True, env=env, timeout=30)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def test_add_then_report_and_midnight_split(self):
        now = int(time.time())
        midnight = int(dt.datetime.combine(dt.date.today(), dt.time()).timestamp())
        lines = [{"a": "zed", "s": now - 600, "e": now - 60}, {"p": now - 600}]
        if now - midnight > 120:
            lines.append({"a": "brave", "s": midnight - 60, "e": midnight + 60})
        out = self.run_helper("add", stdin=(json.dumps(lines + ["junk", {"a": "../x", "s": 1, "e": 2}]) + "\n").encode())
        self.assertEqual(out.returncode, 0, out.stderr)
        rep = json.loads(self.run_helper("report", "--limits", "app:zed=5").stdout)
        apps_today = {a["app"]: a["seconds"] for a in rep["today"]["apps"]}
        self.assertEqual(apps_today["zed"], 540)
        if now - midnight > 120:
            self.assertEqual(apps_today["brave"], 60, "only the part after midnight counts today")
        self.assertEqual(rep["limits"][0]["used"], 540)
        self.assertEqual(rep["today"]["pickups"], 1)

    def test_too_much_input_is_refused(self):
        out = self.run_helper("add", stdin=b"x" * (300 * 1024))
        self.assertEqual(out.returncode, 1)
        self.assertEqual(self.run_helper("add", stdin=b"not json\n").returncode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=0)
