# Custom Prompt Game Engine

A menu-driven bash engine: colored terminal UI, a config-driven "prompt" that
picks a theme/intensity/rounds/speed for a session, and a shuffle-bag
selector (every entry gets drawn once before anything repeats).

**The engine ships with no real content** — just three neutral placeholder
entries under `variants/demo/` so you can run it immediately and see the
format. Everything else is yours to fill in.

## Run it

```bash
chmod +x game.sh
./game.sh
```

Everything is stored under `~/.customgame/`:

```
~/.customgame/
├── config/prompt.txt   ← the active session config
├── variants/<theme>/   ← your content, one .variant file per entry
├── state/              ← shuffle-bag queues (auto-managed, safe to delete)
└── logs/history.log    ← what got shown, when
```

## Adding your own content

Create a folder per theme: `~/.customgame/variants/<theme-name>/`, and inside
it, one `.variant` file per entry. Format:

```
ID=001
TITLE=Some short title
INTENSITY=medium
DESC<<END
Whatever descriptive text you want. Multiple lines are fine.
END
ASCII<<END
Your ASCII art / symbols go here, line by line.
END
```

Rules:
- `ID`, `TITLE`, `INTENSITY` are single-line `KEY=VALUE` fields.
- `DESC` and `ASCII` are multi-line blocks: `KEY<<END`, then any number of
  lines, then a line containing exactly `END`.
- `INTENSITY` can be anything you want (`low`/`medium`/`high`, or your own
  scheme) — it's just a filter tag, the engine doesn't interpret it.
- File names don't matter, only the `.variant` extension and the `ID=`
  field inside.

Drop in as many files as you want — 10, 1000, doesn't matter. The engine
just globs `*.variant` in the theme folder.

## The prompt (`config/prompt.txt`)

This is what "Custom Prompt Mode" reads. Same block format as above:

```
TITLE=My Session
THEME=demo
INTENSITY=any
ROUNDS=10
SPEED=normal
DESC<<END
Free-text description shown as the session banner.
END
```

- `THEME` — which folder under `variants/` to draw from.
- `INTENSITY` — `any`, or a value matching entries' `INTENSITY` tag.
- `ROUNDS` — how many entries to show before the session ends; `0` means
  keep going until you press `q`.
- `SPEED` — `normal` (instant text) or `typewriter` (character-by-character).

You can edit this file directly, or from the menu: **Custom Prompt Mode →
Guided setup** walks you through it with prompts (title, a free-text
description you type until you enter a line with just `.`, theme picked
from a numbered list, intensity, rounds, speed) and writes the file for you.
**Edit raw prompt.txt** opens it in `$EDITOR` (or `nano`/`vim` if found).

## How selection works

For a given `(theme, intensity)` pair, the engine builds a shuffled list of
every matching `.variant` file and stores it in `state/`. Each round pops
one entry off that list. When the list runs out, it reshuffles from
scratch — so you see every entry once before anything repeats, and the
order is different each cycle. You can also force an early reshuffle
mid-session with `r`.

## Menu overview

- **Quick Start** — runs immediately with whatever `prompt.txt` currently
  has.
- **Custom Prompt Mode** — view the active config, guided setup, raw edit,
  or start.
- **Manage Content Library** — lists themes and how many entries each has
  (broken down by `low`/`medium`/`high` if you use those tags).
- **Session History** — tail of `logs/history.log` (timestamp, theme, id).
