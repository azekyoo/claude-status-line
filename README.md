# claude-code-status-line

A gradient, emoji-accented status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — with first-class **Windows** support.

This is a Windows-compatible fork of [kcchien/claude-code-statusline](https://github.com/kcchien/claude-code-statusline), rebuilt and extended for git-bash / Windows Terminal, with a heavier focus on gradient rendering, rate-limit visibility, and git status.

## What it looks like

![Normal state](docs/images/normal.svg?v=3)

- Model name and directory path render as smooth per-character truecolor gradients.
- Context-window usage bar: green → yellow → orange → red, 10 blocks.
- 5h / 7d rate-limit usage: same gradient bar style, label + value gradient text, plus when each window resets (local clock time — always visible, "--%" placeholder before Claude Code has usage data yet).
- Git branch, dirty flag (`*`), ahead/behind vs. upstream (`↑`/`↓`).
- Lines added/removed, current directory, active subagent/worktree indicator.
- Degrades cleanly: truecolor → ANSI 256 → plain ASCII, and Nerd Font / emoji / plain-Unicode icon sets.

### All states

**Warning** (75% context)
![Warning](docs/images/warning.svg?v=3)

**Danger** (92% context, high rate limits)
![Danger](docs/images/danger.svg?v=3)

**Dirty branch, ahead/behind upstream**
![Git status](docs/images/git-status.svg?v=3)

**Active worktree**
![Worktree](docs/images/worktree.svg?v=3)

**Active subagent**
![Agent](docs/images/agent.svg?v=3)

**ASCII fallback** (`CLAUDE_STATUSLINE_ASCII=1`)
![ASCII](docs/images/ascii.svg?v=3)

## Why this fork exists

The original script assumes a macOS/Linux bash + native `jq`. On Windows (git-bash), four things break silently:

1. **No `jq`** — the script has a hard `command -v jq` gate and just goes blank without it.
2. **CRLF corruption** — native Windows `jq.exe` writes CRLF line endings (text-mode stdio). git-bash reads that raw, and the stray `\r` breaks every numeric field's arithmetic.
3. **Backslash paths** — `workspace.current_dir` on Windows uses `\`, not `/`. The original `split("/")` never finds a separator, so the *entire path* leaks into the display — and because it contains literal backslashes, `printf '%b'` later misinterprets them as escape sequences (`\U`, `\0nn`, ...), corrupting the rest of the line.
4. **`stat` flag mismatch** — the git-status cache reads the cache file's mtime with BSD `stat -f %m` (macOS). git-bash ships GNU coreutils, which uses `stat -c %Y` instead; the BSD form silently fails there. Harmless in effect (the cache just always misses and re-runs git, not a correctness bug), but worth fixing since it defeats the whole point of caching.

This fork fixes all four, plus adds the gradient/rate-limit/git features above.

## Requirements

- Claude Code
- `bash.exe` present on disk — on Windows this comes bundled with **Git for Windows**, which you almost certainly already have installed if the `git` command works for you. You don't need to use bash as your shell; Claude Code invokes it silently as a subprocess to run the script, regardless of whether you work in PowerShell, cmd, or anything else.
- `jq` — the installer fetches a static binary for you if missing.
- A truecolor-capable terminal for the full gradient experience (Windows Terminal, VS Code's integrated terminal, iTerm2, most modern Linux terminals). Falls back gracefully otherwise.

## Quick install (via Claude Code)

Paste this into Claude Code:

```
Install the Claude Code status line from https://github.com/azekyoo/claude-code-status-line — clone it, run install.sh, and add the statusLine block to my ~/.claude/settings.json.
```

## Manual install

```bash
git clone https://github.com/azekyoo/claude-code-status-line.git
cd claude-code-status-line
./install.sh
```

This copies `statusline.sh` to `~/.claude/statusline/claude-code-statusline.sh`, and — on Windows only — downloads a static `jq.exe` to `~/bin/jq.exe` if `jq` isn't already on your PATH (the script auto-detects it there even without a PATH change).

### Wire it into Claude Code

Add this to `~/.claude/settings.json`:

**Windows:**
```json
{
  "statusLine": {
    "type": "command",
    "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" \"C:\\Users\\YOURNAME\\.claude\\statusline\\claude-code-statusline.sh\"",
    "timeout": 10
  }
}
```
Replace `YOURNAME` with your Windows username. This invokes git-bash directly with a full path, since Claude Code runs the `command` string outside of any interactive shell profile (so PATH additions from `.bashrc` won't apply).

**macOS / Linux:**
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline/claude-code-statusline.sh",
    "timeout": 10
  }
}
```

Restart Claude Code. The status line appears after your next message.

### Reverting

If you don't like it, just restore your previous `statusLine.command` value in `settings.json` (or delete the `statusLine` key entirely to go back to Claude Code's default). Nothing else on your system is touched — `~/bin/jq.exe`, if installed, is harmless to leave in place or delete.

## Configuration

All via environment variables (set them in `~/.bashrc`, or `env` in `settings.json` if you want them applied specifically for Claude Code):

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_STATUSLINE_ASCII` | `0` | `1` = plain ASCII only, no Unicode/emoji/truecolor |
| `CLAUDE_STATUSLINE_NERDFONT` | `0` | `1` = use Nerd Font icons instead of emoji (requires a Nerd Font set in your terminal) |
| `CLAUDE_STATUSLINE_EMOJI` | `1` | `0` = disable emoji, fall back to plain Unicode symbols (`◆`, `⎇`, `⚠`) |
| `CLAUDE_STATUSLINE_POWERLINE` | follows `NERDFONT` | `1` = Powerline-arrow separators |
| `CLAUDE_STATUSLINE_JQ` | auto-detect | explicit path to a `jq` binary |
| `COLORTERM` | (terminal-set) | `truecolor` / `24bit` enables the gradient bars/text; also auto-enabled under Windows Terminal via `WT_SESSION` |

## Notes

- Cost (`$`) is parsed from the JSON payload but intentionally not displayed — on a Claude subscription plan it's a notional API-equivalent estimate, not a real charge, and was more confusing than useful.
- Elapsed session time is likewise parsed but not shown, by request — feel free to re-enable by reading `duration_ms` and building a `Xm Ys` string if you want it back.
- Git branch/dirty/ahead-behind status is cached for 5 seconds (`/tmp/claude-statusline-git-cache`) to keep the status line fast on large repos.

## License

MIT — see [LICENSE](LICENSE). Original work Copyright (c) 2026 KC Chien ([kcchien/claude-code-statusline](https://github.com/kcchien/claude-code-statusline)).
