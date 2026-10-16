#!/usr/bin/python3 -I
"""The Plasma edition's recorder: the same counting rules as the Omarchy service, on a made-up clock."""
from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "app"))
from recorder import Recorder  # noqa: E402

T = 1_800_000_000


class Counting(unittest.TestCase):
    def test_focus_changes_cut_stretches(self):
        r = Recorder(60, T)
        r.focus("zed", "omarchy-dusk", T)
        r.tick(T + 10, 0)
        r.focus("brave-browser", "YouTube", T + 100)
        r.focus("brave-browser", "GitHub", T + 160)
        out = r.flush(T + 400)
        self.assertEqual(out[:2], [{"a": "zed", "s": T, "e": T + 100, "d": "omarchy-dusk"},
                                   {"a": "brave-browser", "s": T + 100, "e": T + 160, "d": "YouTube"}])
        self.assertEqual(out[2], {"a": "brave-browser", "s": T + 160, "e": T + 340, "d": "GitHub"},
                         "the flush cuts a minute back, where you were surely here")

    def test_going_idle_ends_where_the_input_stopped_and_coming_back_late_is_a_pickup(self):
        r = Recorder(60, T)
        r.focus("zed", "", T)
        for t in range(15, 600, 15):     # ticks every 15 s; no input from T+125 until T+600
            r.tick(T + t, max(0, t - 125) * 1000)
        r.tick(T + 600, 0)
        out = r.flush(T + 600)
        self.assertEqual(out[0], {"a": "zed", "s": T, "e": T + 125})
        self.assertEqual(out[1], {"p": T + 600})

    def test_a_short_break_is_no_pickup(self):
        r = Recorder(60, T)
        r.focus("zed", "", T)
        r.tick(T + 100, 70_000)
        r.tick(T + 150, 0)
        self.assertNotIn({"p": T + 150}, r.flush(T + 150))

    def test_a_sleep_ends_the_stretch_when_the_laptop_went_down(self):
        r = Recorder(60, T)
        r.focus("zed", "", T)
        r.tick(T + 15, 0)
        r.tick(T + 3600, 0)              # the clock jumped an hour
        out = r.flush(T + 3600)
        self.assertEqual(out[0], {"a": "zed", "s": T, "e": T + 15})
        self.assertEqual(out[1], {"p": T + 3600})

    def test_bad_ids_and_labels_are_dropped_and_labels_can_be_forgotten(self):
        r = Recorder(60, T)
        r.focus("../etc", "x", T)
        self.assertIsNone(r.current)
        r.focus("brave-browser", "y" * 500, T)
        self.assertEqual(r.current["d"], "")
        r.focus("brave-browser", "YouTube", T + 10)
        r.focus("zed", "", T + 20)
        r.forget_labels()
        self.assertTrue(all("d" not in x for x in r.flush(T + 30)))


if __name__ == "__main__":
    unittest.main(verbosity=0)
