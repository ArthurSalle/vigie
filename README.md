# Vigie

> *Vigie* (French): the lookout post on a ship's mast — the sailor who watches the horizon.

A macOS menu bar app that watches your listening TCP ports and reminds you about the dev servers you forgot to kill.

Built for the AI-coding era: agents like Claude Code or Cursor happily spawn `npm run dev`, `uvicorn`, `vite` — and nobody remembers to stop them. Vigie tells you **what's listening, who launched it, and since when**, and lets you kill it in one click.

## Features

- **Live port list** in your menu bar, grouped into *Dev / unknown*, *Applications*, and *System* (collapsed by default). Rescans every 5 s (configurable).
- **Who launched it** — walks the parent-process chain: 🤖 badge when the server was spawned by an AI agent (Claude Code, Codex, Aider…), otherwise shows the terminal or IDE (Warp, iTerm, Cursor, VS Code…).
- **Context at a glance** — process name, uptime, RAM, working directory (`~/dev/my-project`), full command line on hover, and the port's likely role when well-known (Vite, PostgreSQL, Ollama, Jupyter…).
- **New-port notifications** — when a new dev port appears, get a notification with inline *Kill* / *Ignore* actions. System ports never spam you.
- **Stale-port reminders** — after N hours (default 3, configurable 1–24), Vigie asks: *"Port 3000 has been open for 3+ hours — still useful?"* with *Kill* / *Remind me later* / *Stop reminding* actions.
- **Graceful kill** — SIGTERM first, SIGKILL 3 s later only if the process resists. Right-click for instant SIGKILL. System processes are locked 🔒.
- **Network-exposure warning** — ⚠️ orange icon when a port is bound to all interfaces (`*` / `0.0.0.0`) instead of localhost only.
- **Open in browser** — one click to `http://localhost:PORT`.
- **Launch at login** (optional), ignore list, and per-section collapsing.

## Install

Requires macOS 15+ and Xcode (or Command Line Tools with the macOS SDK).

```bash
git clone https://github.com/ArthurSalle/vigie.git
cd vigie
./build-app.sh          # builds release, assembles Vigie.app, installs to ~/Applications
open ~/Applications/Vigie.app
```

Accept the notification permission prompt on first launch.

## Privacy

Everything runs **100 % locally**:

- No network calls, no telemetry, no analytics — the code contains zero outbound connections.
- No root, no sudo, no kernel extensions.
- Ad hoc code signature; nothing is sent to any store or server.

## How it works

Vigie shells out to three standard macOS tools, no privileges needed:

| Tool | Provides |
|------|----------|
| `netstat -anv -p tcp` | every listening TCP socket with its owning PID |
| `ps` | process name, user, uptime, RSS, full command line, parent chain |
| `lsof -d cwd` | working directory (your own processes only) |

Classification heuristics: Apple system paths (`/System`, `/usr/libexec`…) or another user → *System*; dev runtimes (node, python, cargo…), Homebrew/nvm paths, or a working directory inside `$HOME` → *Dev*; `.app` bundles → *Applications*.

The age shown is the **process** age (`ps -o etime`), so it stays accurate even if Vigie itself just started.

## CLI mode

Test the scanner without the UI:

```bash
swift build
.build/debug/Vigie --scan
```

```
:3000  node        2 h 14   210 MB   dev | 🤖 via Claude Code | ~/dev/my-app
:5432  postgres    3 j 2 h  89 MB    dev | PostgreSQL
:7000  ControlCenter 19 j   43 MB    system | EXPOSED | AirPlay
```

## License

[MIT](LICENSE)
