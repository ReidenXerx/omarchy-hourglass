"""The Plasma edition's recorder service, on the session bus as app.duduphudu.Hourglass.

The widget tells it which app is in front and the label it derived (never a window title); this keeps the clock,
asks the desktop how long it has been idle, reads what runs in a terminal, writes the history, and answers the
widget's reports. Only the user's own session can reach it, and everything it is sent is checked as the command line
checks it.
"""
from __future__ import annotations

import json
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

import history  # noqa: E402
import terminal  # noqa: E402
from recorder import Recorder  # noqa: E402

NAME = "app.duduphudu.Hourglass"
PATH = "/app/duduphudu/Hourglass"
XML = """
<node>
  <interface name="app.duduphudu.Hourglass1">
    <method name="Focus">
      <arg type="s" name="app" direction="in"/>
      <arg type="s" name="label" direction="in"/>
      <arg type="b" name="terminal" direction="in"/>
      <arg type="u" name="pid" direction="in"/>
    </method>
    <method name="Report">
      <arg type="s" name="limits" direction="in"/>
      <arg type="s" name="json" direction="out"/>
    </method>
    <method name="Told">
      <arg type="s" name="key" direction="in"/>
    </method>
    <method name="ForgetDetails"/>
    <method name="Weekly">
      <arg type="s" name="text" direction="out"/>
    </method>
    <method name="Version">
      <arg type="s" name="version" direction="out"/>
    </method>
  </interface>
</node>
"""
VERSION = "1"
TICK = 15
FLUSH = 60
PROBE = 20


class Service:
    def __init__(self, bus: Gio.DBusConnection) -> None:
        self.bus = bus
        self.rec = Recorder(60, time.time())
        self.terminal_pid = 0
        self.terminal_label = ""
        self.app = ""

    # ---------------------------------------------------------------- the desktop

    def idle_ms(self) -> int | None:
        """How long the desktop has had no input, from the screensaver interface Plasma provides."""
        try:
            reply = self.bus.call_sync("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver",
                                       "org.freedesktop.ScreenSaver", "GetSessionIdleTime", None,
                                       GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 2000, None)
            return int(reply.unpack()[0])
        except GLib.Error:
            return None

    def tick(self) -> bool:
        self.rec.tick(time.time(), self.idle_ms())
        return True

    def flush(self) -> bool:
        batch = self.rec.flush(time.time())
        if batch:
            try:
                history.keep(batch, time.time())
            except OSError:
                self.rec.pending = batch + self.rec.pending      # kept for the next flush
        return True

    def probe(self) -> bool:
        if self.terminal_pid:
            label = terminal.describe(self.terminal_pid)
            if label != self.terminal_label:
                self.terminal_label = label
                self.rec.focus(self.app, label, time.time())
        return True

    # ---------------------------------------------------------------- the widget

    def on_call(self, conn, sender, path, iface, method, params, invocation):
        try:
            args = params.unpack()
            if method == "Focus":
                app, label, is_terminal, pid = args
                self.app = str(app)[:64]
                self.terminal_pid = int(pid) if is_terminal and 0 < int(pid) < 1 << 22 else 0
                self.terminal_label = terminal.describe(self.terminal_pid) if self.terminal_pid else ""
                self.rec.focus(self.app, self.terminal_label if self.terminal_pid else str(label)[:120], time.time())
                invocation.return_value(None)
            elif method == "Report":
                self.flush()
                rep = history.build_report(str(args[0])[:2000], time.time())
                cur = self.rec.current
                # The stretch in progress, not yet written, so the widget's total moves with you.
                rep["live"] = {"app": cur["a"], "seconds": int(time.time() - cur["s"])} if cur else None
                out = json.dumps(rep, separators=(",", ":"))
                invocation.return_value(GLib.Variant("(s)", (out,)))
            elif method == "Told":
                history.told(str(args[0])[:120])
                invocation.return_value(None)
            elif method == "ForgetDetails":
                self.rec.forget_labels()
                history.forget_details()
                invocation.return_value(None)
            elif method == "Weekly":
                invocation.return_value(GLib.Variant("(s)", (history.weekly_due(time.time()),)))
            elif method == "Version":
                invocation.return_value(GLib.Variant("(s)", (VERSION,)))
            else:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)
        except Exception as problem:  # noqa: BLE001 - one bad call must not take the recorder down
            invocation.return_dbus_error("app.duduphudu.Hourglass.Error", str(problem)[:200])


def run() -> int:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    service = Service(bus)
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    bus.register_object(PATH, node.interfaces[0], service.on_call, None, None)
    loop = GLib.MainLoop()

    def lost(*_):
        loop.quit()                 # another recorder holds the name: this one is not needed

    Gio.bus_own_name_on_connection(bus, NAME, Gio.BusNameOwnerFlags.NONE, None, lost)
    GLib.timeout_add_seconds(TICK, service.tick)
    GLib.timeout_add_seconds(FLUSH, service.flush)
    GLib.timeout_add_seconds(PROBE, service.probe)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 15, lambda: (service.flush(), loop.quit(), False)[2])
    loop.run()
    service.flush()
    return 0
