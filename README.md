# claude-statusline

The status line for Claude Code: a single `bash` script that reads the harness's JSON payload on stdin and renders one line at the bottom of the session.

```
~/Work/DMXL/dmon-studio-com  main | DeepSeek V4 Pro  xhigh | 2/5: Custom SVG wordmark    142.3k ██████ 71%
```

Three groups on the left split by a grey pipe, one usage group pushed to the right edge. What each segment means and why it looks the way it does is in [docs/design.md](docs/design.md); what the harness actually hands the script, and what it does with what comes back, is in [docs/payload-contract.md](docs/payload-contract.md).

## Layout

| Group | Shows |
|---|---|
| where | working directory, git branch |
| what answers | model, reasoning effort (colour coded by level) |
| what is worked | `N/M` and a phase title, parsed from a plan doc, led by a glyph saying whether that phase is finished, pending or in flight |
| usage | context tokens, a six cell usage bar, used percentage |

Groups with nothing in them disappear along with their divider, so a non-repo directory with no plan file renders `/tmp | Opus 5   8.2k █████ 12%`.

## Overflow

`COLUMNS` is a budget, not a hint. When the content will not fit, the line sheds it a rung at a time, cheapest loss first, and stops the moment it fits:

| Rung | Effect |
|---|---|
| 1 | working directory collapses to its last folder |
| 2 | phase collapses to `3/5`, losing both the title and the word |
| 3 | working directory drops |
| 4 | usage bar becomes a single separator in the percentage's own colour |
| 5 | phase number drops |
| 6 | effort drops |
| 7 | token count drops, taking that separator with it |
| 8 | branch drops |

The model name and the used percentage are the last two things standing. A separator disappears whenever either of the things it separates does, so a shed segment never leaves a dangling pipe behind.

The order is the `for rung in ...` list in the script, and reordering that list is the whole edit. Below the last rung, where even the model and the percentage do not fit, the script gives up and the harness truncates the line as it always did.

Without this the script simply emitted an over-long line and let the harness cut the tail, which always ate the usage group first: `~/Work/DMXL/dmon-studio-com  main | DeepSeek V4 Pro  xhigh | 3/5: Responsive static composition  122.8k █████…`

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

It is also what the phase group's five second acknowledgement needs (see [The plan doc](#the-plan-doc)). The harness runs no timer of its own, so with no `refreshInterval` the first form holds until the next spawn happens for some other reason. The bar still never names the wrong phase, it just lingers on the finished one.

This machine currently wires it through a symlink at `~/.claude/statusline-command.sh` instead, so `settings.json` keeps its original path. See [docs/design.md](docs/design.md) for why that indirection is the weaker of the two options.

## Configuration

Everything tunable is a constant at the top of the script, plus these environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_STATUSLINE_PLAN` | `PLAN.md` | plan doc filename to look for |
| `CLAUDE_STATUSLINE_MARGIN` | `4` | columns left free at the right edge |
| `CLAUDE_STATUSLINE_GIT` | `/opt/homebrew/bin/git` | git binary, pinned away from any slow auth wrapper on PATH |
| `CLAUDE_STATUSLINE_FLASH` | `5` | seconds a finished phase is acknowledged before the bar moves to the next one. `0` skips the acknowledgement entirely |
| `CLAUDE_STATUSLINE_STATE` | `$TMPDIR/claude-statusline-<session id>` | where the acknowledgement clock is kept |
| `CLAUDE_STATUSLINE_NOW` | `$EPOCHSECONDS` | override the clock, for tests |
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

Both numbers come from the plan's own `Phase N` labels when it has any, so a plan numbered 0 to 5 reads `3/5`. The word `Phase` is not printed: beside a title, a bare fraction reads as one without spending the columns.

### Which phase gets named

A `[/]` settles it, and that phase is named on its own:

```
2/5: Rendering
```

Without one there are two useful things to say and no room for both, so the group says them in turn. For five seconds it acknowledges the phase just finished, then it settles on the one coming up:

```
✓ 2/5: Extraction        for five seconds
→ 3/5: Rendering         from then on
```

A glyph rather than a word carries the state, which keeps the fraction on the line in both forms. That matters twice: `3 of 5` is worth knowing exactly when you are being told what is next, and the [overflow ladder](#overflow) needs something to collapse to when the title has to go.

The finished phase is the last `[x]` reached before the first pending line, in execution order. A `[-]` is never acknowledged, since cancelling a phase is not finishing it.

Two plans have only one thing to say and so never alternate. Nothing finished yet gives `→ 1/5: Scaffold` at any moment, and nothing left pending gives `✓ 5/5: Ship`.

### The five seconds

The script is stateless and runs only when the harness spawns it, so it keeps one line in `$TMPDIR`: a fingerprint of what is being displayed and the epoch it was first seen. A render whose fingerprint matches inherits that clock, one whose fingerprint differs resets it.

The acknowledgement is therefore derived from the plan's state rather than animated over the top of it, which is what makes the plan changing part way through a non-event:

| Edit the plan mid acknowledgement | What happens |
|---|---|
| tick a further box | the fingerprint changes, so the acknowledgement restarts on the newly finished phase |
| mark the pending phase `[/]` | it leaves the pair altogether and renders that phase at once, with no glyph |
| untick the finished phase | there is nothing to acknowledge, so it shows the pending phase |
| edit prose below the checklist | the fingerprint is unchanged, so nothing restarts |

That last row is why the clock is a fingerprint rather than the plan file's mtime, which would restart the acknowledgement on any edit to the file, including notes nowhere near the checkboxes.

The file is keyed by session id, because two sessions open on the same repo share the plan doc and a clock keyed on the doc alone would have each restarting the other. A stale file from a previous boot fails the fingerprint and resets, and a timestamp in the future gives a negative age, which resets too.

The clock is `$EPOCHSECONDS`, which is bash 5. With no clock the group settles on the pending phase and never acknowledges anything, which is also what `CLAUDE_STATUSLINE_FLASH=0` does and what a state file that cannot be written falls back to.

## Tests

```zsh
./test/render-cases.sh          # render every case
./test/render-cases.sh --check  # assert widths and exit non-zero on drift
```

The suite covers every optional field, all five effort levels, the usage thresholds, the no-git and no-plan paths, malformed stdin, and right-alignment under both a UTF-8 locale and `LC_ALL=C`. Both glyph forms of the phase group get their own width cases in both locales, since a glyph is one column and three bytes and a form that let one into its measured copy would run two columns long with nothing about the line looking wrong.

The acknowledgement clock is asserted as a sequence rather than as single renders, because what the group shows depends on what it showed before. The sequence walks a plan through ticking a box, ticking another one part way through the five seconds, editing prose below the checklist, marking a phase `[/]`, unticking, a clock that moves backwards, a missing state file and a corrupt one. `CLAUDE_STATUSLINE_NOW` and `CLAUDE_STATUSLINE_STATE` are what make that deterministic; the whole suite runs on a frozen clock.

The overflow ladder is checked by sweeping every column width from the natural width down to the floor, asserting three things at once: the line is exactly `COLUMNS` minus the margin wide the whole way down, nothing that has been shed ever comes back, and the widths at which things vanish run in the ladder's own order. Sweeping rather than pinning a rendering at a fixed width is deliberate, since the fixture lives under `mktemp` and its path length differs between machines.

## Licence

MIT. See [LICENSE](LICENSE).
