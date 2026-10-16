"""Counting time where the desktop cannot do it in QML: the Plasma edition's recorder.

On Omarchy the shell service counts (shell/Service.qml). On Plasma a widget cannot keep a clock for itself, write
files or ask how long you have been idle, so this does it instead, with the same rules:

  - time counts while an app is in front and you are not idle;
  - going idle ends the stretch where the input stopped, a sleep where the clock jumped;
  - coming back after five minutes away is a pick-up;
  - a change of app or of detail label cuts the stretch;
  - the minute flush cuts where you were surely there (now minus the idle timeout).

It holds nothing but app ids, labels already derived by the widget, and times. Clock and storage are passed in, so
the rules can be tested without either.
"""
from __future__ import annotations

import core

PICKUP_AWAY = 300           # seconds away that make coming back a pick-up
SLEEP_JUMP = 60             # seconds the clock may jump between ticks before it counts as a sleep


class Recorder:
    def __init__(self, idle_seconds: int = 60, now: float = 0.0) -> None:
        self.idle_seconds = max(30, min(600, int(idle_seconds)))
        self.app = ""               # the app in front, as its id
        self.label = ""             # its detail label, already derived; "" for none
        self.current: dict | None = None    # {"a", "s", "d"} while counting
        self.pending: list[dict] = []       # stretches and pick-ups not yet written
        self.away_since = 0.0
        self.idle = False
        self.last_tick = now

    # ---------------------------------------------------------------- stretches

    def _close(self, end: float) -> None:
        c = self.current
        self.current = None
        if not c or end - c["s"] < 2:
            return
        r = {"a": c["a"], "s": int(c["s"]), "e": int(end)}
        if c.get("d"):
            r["d"] = c["d"]
        self.pending.append(r)

    def _open(self, start: float) -> None:
        if self.app and not self.idle:
            self.current = {"a": self.app, "s": start, "d": self.label}

    def _back(self, now: float) -> None:
        if self.away_since and now - self.away_since >= PICKUP_AWAY:
            self.pending.append({"p": int(now)})
        self.away_since = 0.0

    # ---------------------------------------------------------------- what the desktop says

    def focus(self, app: str, label: str, now: float) -> None:
        """The app in front changed, or its label did. Ids and labels are checked the way the helper checks them."""
        app = core.clean_app(app)
        label = core.clean_label(label) if app else ""
        if app == self.app and label == self.label:
            return
        self.app, self.label = app, label
        self._close(now)
        self._open(now)

    def tick(self, now: float, idle_ms: int | None) -> None:
        """Called every few seconds with how long the desktop has had no input (None when it cannot tell)."""
        if now - self.last_tick > SLEEP_JUMP:
            self._close(self.last_tick)
            if not self.away_since:
                self.away_since = self.last_tick
            self.idle = False
            self._back(now)
            self._open(now)
        self.last_tick = now
        if idle_ms is None:
            return
        idle_now = idle_ms >= self.idle_seconds * 1000
        if idle_now and not self.idle:
            stopped = now - idle_ms / 1000
            self._close(max(stopped, self.current["s"]) if self.current else stopped)
            self.idle = True
            self.away_since = stopped
        elif not idle_now and self.idle:
            self.idle = False
            self._back(now)
            self._open(now)

    def flush(self, now: float) -> list[dict]:
        """What is ready to be written: finished stretches, and the one in progress cut where you were surely here."""
        if self.current:
            cut = now - self.idle_seconds
            # A cut under two seconds would be dropped as too short, losing that slice: leave it for the next flush.
            if cut - self.current["s"] >= 2:
                keep = self.current
                self._close(cut)
                self.current = {"a": keep["a"], "s": cut, "d": keep.get("d", "")}
        out, self.pending = self.pending, []
        return out

    def forget_labels(self) -> None:
        for r in self.pending:
            r.pop("d", None)
        if self.current:
            self.current["d"] = ""
        self.label = ""
