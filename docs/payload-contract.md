# The harness contract

What Claude Code hands the status line command, and what it does with what comes back. Verified against Claude Code 2.1.263 by reading the installed binary. The derivation, with the exact commands to re-run it after a version bump, is in `~/Documents/Claude/Notes/claude/claude-07-statusline.md`; this file is the working reference.

## Invocation

The command runs through the ordinary hook path with the payload on stdin. Three gates sit in front of it:

```
workspace trust not accepted?    ──▶  skipped, warning to the debug log, nothing renders
policy settings override?        ──▶  the managed statusLine wins over your own
policySettings.disableAllHooks?  ──▶  skipped entirely
your own disableAllHooks?        ──▶  warning logged, the command still runs
```

The spawn copies the environment and adds **`COLUMNS` and `LINES` from `process.stdout`**. That is the only reason right alignment is possible, and it is not in the documented schema.

## Stdin payload

Optional fields are marked; the rest are always present.

| Field | Shape | Notes |
|---|---|---|
| `session_id` | string | |
| `session_name` | string, optional | what `/rename` sets |
| `prompt_id` | string, optional | same as the OTel `prompt.id` |
| `transcript_path` | string | |
| `cwd` | string | |
| `model` | `{id, display_name}` | |
| `workspace` | `{current_dir, project_dir, added_dirs[]}` | plus optional `git_worktree` and `repo` (`{host, owner, name}` from origin) |
| `version` | string | CLI version |
| `output_style` | `{name}` | |
| `context_window` | see below | |
| `effort` | `{level}`, optional | `low`, `medium`, `high`, `xhigh`, `max`, after any silent downgrade |
| `thinking` | `{enabled}` | |
| `rate_limits` | optional | `five_hour`, `seven_day`, `spend_limit`, each `{used_percentage, resets_at}` |
| `prompt_cache` | optional | see below |
| `vim` | `{mode}`, optional | |
| `agent` | `{name}`, optional | set under `--agent` |
| `pr` | optional | `{number, url, review_state?, kind?}` |
| `worktree` | optional | `{name, path, branch?, original_cwd, original_branch?}` |

Undocumented but emitted, so usable and less stable: `cost` (`total_cost_usd`, `total_duration_ms`, `total_api_duration_ms`, `total_lines_added`, `total_lines_removed`), `exceeds_200k_tokens`, `fast_mode`, `remote` (`{session_id}`).

### context_window

```
total_input_tokens     tokens in the window right now, cache reads and writes included
total_output_tokens    output tokens from the most recent response only
context_window_size    200000, or 1000000 on a [1m] model
current_usage          last call only: {input_tokens, output_tokens,
                       cache_creation_input_tokens, cache_read_input_tokens} or null
used_percentage        0-100, null before the first message
remaining_percentage   0-100, null before the first message
```

**There is no cumulative token count anywhere in the payload.** `total_input_tokens` is the window's current size, `current_usage` is one call, and `cost` has no token fields. A true session total would need parsing `transcript_path`, which at 1 Hz is not worth it. The bar therefore shows window occupancy, not spend.

### prompt_cache

```
warm, caching_observed, ttl ("5m"|"1h"), expires_at, requests, misses,
expected_rebuilds, hit_ratio, cache_write_tokens, miss_recache_tokens,
last_miss_at, last_miss_cause {causes[], ...}, miss_causes {}, recache_tokens_if_cold
```

Cause names are a closed set: `system_prompt_changed`, `tools_changed`, `model_changed`, `messages_rewritten`, `ttl_expired_5m`, `ttl_expired_1h`, `likely_server_side`, `unknown`. Read the booleans with `== true` / `== false`, never with jq's `//`, which treats `false` as absent and would report a cold cache as no cache at all.

## What comes back

```
stdout  ──▶  .trim()  ──▶  .split("\n")  ──▶  ink <Box paddingX={padding ?? 0} gap={2}>
                                              <Text dimColor wrap="truncate">
```

- **Multi-line works.** Two lines out gives a two-row bar.
- **The line is truncated, not wrapped.** Overflow is cut and ends in an ellipsis. The usable width is about four columns less than `COLUMNS`, because the frame takes some back. Hence `CLAUDE_STATUSLINE_MARGIN`.
- **ANSI SGR renders**, 8-colour, 256 and truecolor alike.
- **stderr is discarded** to the debug log, prefixed `StatusLine [<command>] stderr:`.
- **Failure keeps the previous text.** Non-zero exit, spawn failure and timeout all render nothing new, with no indicator. Telemetry logs one of `spawn_failed`, `timeout`, `nonzero_exit`, `exec_error`, once per session per kind.

## When it re-runs

```
tokenUsage, permissionMode, vimMode, mainLoopModel,   ──┐
fastMode, effortValue, thinkingEnabled, prStatus       ├──▶ debounce 300ms ──▶ spawn
a new assistant message                                ┤
refreshInterval elapsed (only when set, min 1s)        ┤
a rate limit window resets                             ┤
the prompt cache expires                              ──┘
```

No timer unless `refreshInterval` is set. A plan doc edit is picked up on the next spawn; there is no file watcher.

## Settings

| Setting | Effect |
|---|---|
| `statusLine.command` | the command, run through the shell |
| `statusLine.refreshInterval` | re-run every N seconds on top of the events above, minimum 1 |
| `statusLine.padding` | horizontal padding of the containing box, default 0 |
| `statusLine.hideVimModeIndicator` | suppress the built-in `-- INSERT --` line |
| `subagentStatusLine` | a separate `{type, command}` for the per-subagent line in the agent panel |
