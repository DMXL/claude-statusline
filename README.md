# claude-statusline

The status line for Claude Code: a single `bash` script that reads the harness's JSON payload on stdin and renders one line at the bottom of the session.

```
~/Work/DMXL/dmon-studio-com  main | DeepSeek V4 Pro  xhigh | Phase 2/5: Custom SVG wordmark    142.3k ██████ 71%
```

Three groups on the left split by a grey pipe, one usage group pushed to the right edge. What each segment means and why it looks the way it does is in [docs/design.md](docs/design.md); what the harness actually hands the script, and what it does with what comes back, is in [docs/payload-contract.md](docs/payload-contract.md).

## Layout

| Group | Shows |
|---|---|
| where | working directory, git branch |
| what answers | model, reasoning effort (colour coded by level) |
| what is worked | `Phase N/M` and the current phase title, parsed from a plan doc |
| usage | context tokens, a six cell usage bar, used percentage |

Groups with nothing in them disappear along with their divider, so a non-repo directory with no plan file renders `/tmp | Opus 5   8.2k █████ 12%`.

## Install

The script is the deliverable; there is no build step. Point Claude Code at it in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash /path/to/claude-statusline/statusline-command.sh",
  "refreshInterval": 1
}
```

`refreshInterval` is what makes the bar track a plan file edit within a second. Without it the command only re-runs on a handful of state changes and each new assistant message.

This machine currently wires it through a symlink at `~/.claude/statusline-command.sh` instead, so `settings.json` keeps its original path. See [docs/design.md](docs/design.md) for why that indirection is the weaker of the two options.

## Configuration

Everything tunable is a constant at the top of the script, plus four environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_STATUSLINE_PLAN` | `PLAN.md` | plan doc filename to look for |
| `CLAUDE_STATUSLINE_MARGIN` | `4` | columns left free at the right edge |
| `CLAUDE_STATUSLINE_GIT` | `/opt/homebrew/bin/git` | git binary, pinned away from any slow auth wrapper on PATH |
| `COLUMNS` | set by the harness | terminal width, used for right alignment |

Colours live in the `C_*` block at the top of the script, one line each.

## The plan doc

The phase group parses the first plan doc it finds, trying `$cwd/PLAN.md`, `$cwd/docs/PLAN.md`, then the same two at the repo root. Markers, all at column 0:

| Marker | Meaning |
|---|---|
| `- [x]` | done |
| `- [/]`, `- [~]` | in progress, this is the phase the bar names |
| `- [-]` | cancelled, counted but never current |
| `- [ ]` | pending |

The current phase is the first `[/]`, falling back to the first `[ ]`. Both numbers come from the plan's own `Phase N` labels when it has any, so a plan numbered 0 to 5 reads `Phase 3/5`.

## Tests

```zsh
./test/render-cases.sh          # render every case
./test/render-cases.sh --check  # assert widths and exit non-zero on drift
```

The suite covers every optional field, all five effort levels, the usage thresholds, the no-git and no-plan paths, malformed stdin, and right-alignment under both a UTF-8 locale and `LC_ALL=C`.

## Licence

MIT. See [LICENSE](LICENSE).
