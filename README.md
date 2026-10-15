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
  each app's desktop entry, the same file your launcher reads, so nothing is
  guessed and nothing is looked up online.
- **Pick-ups.** Coming back after five minutes away (idle, locked or asleep)
  counts as one, with the first of the day and the busiest hour.
- **Limits that nudge.** A daily allowance for an app or a whole category, with
  a notice five minutes before and when it is used up. It never closes or
  blocks anything.
- **Private by construction.** Only which app was in front and for how long is
  kept, never window titles or pages, in a private directory on your laptop.

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

## Requirements

Omarchy's Quickshell-based shell, Python 3 and `notify-send` for limit notices.

## Tests

```bash
python3 -I tests/core_test.py
```

## Licence

MIT

## Support

Hourglass is free and always will be. If it earns a place on your bar, you can
support its development at [donatello.to/DuduPhudu](https://donatello.to/DuduPhudu).
