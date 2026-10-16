# Hourglass

Screen time for your [Omarchy](https://omarchy.org) laptop, the way a phone
shows it: how long you were at the laptop today and this week, by hour, by
category and by app, how often you came back to it, and daily limits that
nudge rather than lock.

## What only Hourglass does

- **It counts only while you are actually there.** Time stops a minute after
  your last key or pointer movement (the Wayland idle monitor), so a laptop left
  open on a browser does not pile up hours. A film that keeps the screen awake
  still counts, because you are watching it.
- **Categories like a phone's, from your own apps.** Development, Web, Social,
  Games, Entertainment, Creativity, Productivity, Utilities: worked out from
  each app's desktop entry, the same file your launcher reads (with a short
  built-in list for terminals and games that ship none), and nothing is looked
  up online.
- **Pick-ups.** Coming back after five minutes away (idle, locked or asleep)
  counts as one, with the first of the day and the busiest hour.
- **Limits that nudge.** A daily allowance for an app or a whole category, with
  a notice five minutes before and when it is used up. It never closes or
  blocks anything.
- **What you did, when you want it.** Turn details on and each app opens to
  show what the time went on: the site in a browser (and the page, for sites
  you choose, such as a YouTube video or a GitHub repository), the project in
  your editor, the program and folder in a terminal ("Claude Code in
  omarchy-dusk"), read from what runs there rather than its title. Only
  significant entries are shown: ten minutes, or a tenth of the app's time, and
  the rest as one "Other" line.
- **Private by construction.** Details are off until you turn them on, and are
  only ever short labels, never a window's title. Private windows and password
  managers are never described, you can name apps that never are, and "Forget
  details" takes every label out of the history while keeping the times. All of
  it stays in a private directory on your laptop.

## Using it

Put the widget on your bar: an hourglass, with today's time in its tooltip and
a dot when a limit you set is close. A click opens the panel.

| In the panel | What it shows |
|---|---|
| **Today / Week** | The total, against your daily average or the week before |
| **The chart** | Today by hour, or the week by day with your average as a line |
| **Categories** | Where the time went, in one bar |
| **Most used** | Each app's time |
| **Daily limits** | Add one for the app in front or a category, then move it in 15-minute steps |

## Where the data comes from, and where it goes

The shell's own focus tracking says which app is in front, and the Wayland idle
monitor says whether you are there. Once a minute the time is handed to a small
helper (`bin/hourglass add`) on stdin, which keeps it in
`~/.local/state/hourglass`, a private directory: 30 days of individual
stretches, and a summary of each day for two years. Nothing is sent anywhere
and nothing needs root.

## Install

```bash
omarchy plugin add https://github.com/ReidenXerx/omarchy-hourglass.git --enable
```

Then add the Hourglass widget to your bar and restart the shell with
`omarchy-restart-shell`.

## Remove

```bash
omarchy plugin remove reidenxerx.hourglass
```

Your history stays in `~/.local/state/hourglass` until you delete it.

## On KDE Plasma

Hourglass also comes as a Plasma 6 widget, with the same panel, limits and
details, drawn with Plasma's own controls and colours. Install it from the KDE
Store (Add Widgets → Get New Widgets → search "Hourglass"), or build it here:

```bash
tools/build-plasma          # dist/hourglass.plasmoid
kpackagetool6 -t Plasma/Applet -i dist/app.duduphudu.hourglass
```

A Plasma widget cannot keep a clock or write files, so the first time you open
it, it offers **Start recording**: that sets up a small recorder (the same
Python helper, `hourglass serve`) as a systemd user service on your session
bus. The widget tells it which app is in front, using Plasma's task manager,
and, if you turned details on, a short label it derived from the window title.
The title itself never leaves the widget. The recorder asks Plasma how long you
have been idle, keeps the history in the same private
`~/.local/state/hourglass`, and sends limit notices as Plasma notifications.
**Stop recording** in the panel removes the service again.

## Requirements

Omarchy's Quickshell-based shell, Python 3 and `notify-send` for limit notices.
On Plasma: Plasma 6, systemd, Python 3 with PyGObject (`python-gobject`), and `notify-send` (libnotify) for limit notices.

## Tests

```bash
python3 -I tests/core_test.py
python3 -I tests/recorder_test.py
node tests/detail-test.js
```

## Licence

MIT

## Support

Hourglass is free and always will be. If it earns a place on your bar, you can
support its development at [donatello.to/DuduPhudu](https://donatello.to/DuduPhudu).
