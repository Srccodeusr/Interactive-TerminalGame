# TermGame Executer Script

A one-file bash installer/launcher for the
[Interactive-TerminalGame](https://github.com/Srccodeusr/Interactive-TerminalGame)
repo. It clones or updates the repo, auto-detects what kind of project it is
(Node, Python, Rust, Make, or a plain bash entry script), installs whatever
dependencies that type needs, and runs it — all from one numbered menu.

It's content-agnostic: the script doesn't know or care what the target
project actually does. It only knows how to fetch, build, and run it.

## Requirements

- Linux with `bash`
- `git` and `curl` (the script installs these itself via `apt-get` if
  they're missing and you have root/sudo — otherwise install them
  manually first)
- Whatever runtime the target repo turns out to need (Node.js, Python 3,
  Rust/Cargo, or `make`) — the script installs Node automatically if
  needed; for Rust it'll ask you to install `rustup` yourself

## Run it

```bash
chmod +x termgame-executer.sh
./termgame-executer.sh
```

First time: pick **1) Install / Update**, then **2) Play**.

## Menu

| Option | What it does |
|---|---|
| **1) Install / Update** | Clones the repo (or pulls latest if already cloned), auto-detects the project type, installs dependencies |
| **2) Play** | Runs the project using the detected (or last-known) type |
| **3) Re-detect Project Type** | Re-scans the project folder — use this if the repo's structure changed since the last install |
| **4) View Logs** | Tails the git/install/run/apt logs |
| **5) Set Custom Run Command** | Manually tell it how to launch the project, for when auto-detection can't figure it out |

## How auto-detection works

After cloning, it checks the top level of the project folder for:

| Found | Detected type | Install step | Run step |
|---|---|---|---|
| `package.json` | `node` | `npm install` (or `pnpm`/`yarn` if a lockfile says so) | `npm start`, else `node index.js` |
| `requirements.txt` / `pyproject.toml` | `python` | `pip3 install -r requirements.txt` | `main.py` / `game.py` / `app.py` / `play.py`, first match |
| `Cargo.toml` | `rust` | `cargo build` | `cargo run` |
| `Makefile` | `make` | `make` | `make run` if that target exists |
| `run.sh` / `start.sh` / `main.sh` / `game.sh` / `play.sh` | `bash` | none | runs that script directly |

If nothing matches, it's marked `unknown` — it'll list the repo's top-level
files and tell you to use **5) Set Custom Run Command** so you can point it
at the real entry point by hand. Once set, that command is remembered and
used automatically going forward.

## Where things live

```
~/.termgame-executer/
├── logs/          ← git.log, install.log, run.log, apt.log
└── state/
    ├── detected_type      ← cached result of auto-detection
    └── custom_run_cmd     ← your manual override, if you set one
```

The cloned project itself goes to `~/interactive-terminalgame/`.

## Credit

Made by prime.dev1. Licensed under MIT + Attribution Requirement — see
`LICENSE`. If you fork or redistribute this, keep the `prime.dev1` credit
in the script header and banner intact.
