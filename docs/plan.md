# claude-statusline: plan

Turn the status line from a script that grew inside `~/.claude` into a project with a contract, a test suite and room to add the payload fields it currently ignores. Done means every segment is covered by an assertion, the bar surfaces the things worth knowing mid-session, and a fresh session can change it without rediscovering how the width arithmetic works.

## Phases

- [x] Phase 0: Extract into a project
- [ ] Phase 1: Test harness
- [ ] Phase 2: Rate limits and cache health
- [ ] Phase 3: PR and worktree awareness
- [ ] Phase 4: Theme adaptation

## Phase 0: Extract into a project

Status: complete.

- Moved `statusline-command.sh` out of `~/.claude` into this repo, wired through a symlink so `settings.json` is untouched.
- Wrote `README.md`, `CLAUDE.md`, `docs/payload-contract.md` and `docs/design.md`, carrying over everything learned while the script lived in `~/.claude`.
- Pinned the git binary to `/opt/homebrew/bin/git`. The `git` on PATH on this machine is a corporate auth wrapper at roughly 390ms a call against 45ms, and the script makes three calls a render at 1 Hz. Measured 2.5x faster end to end.

## Phase 1: Test harness

Goal: no visual change can silently break the width arithmetic again.

Tasks:

1. `test/render-cases.sh` renders a fixed matrix of payloads: every optional field present and absent, all five effort levels, the four usage thresholds plus 0% and 100%, no git, no plan doc, malformed stdin, empty stdin.
2. `--check` asserts that every rendered line is exactly `COLUMNS - margin` wide once escapes are stripped, at several widths, and that the count is identical under `LC_ALL=C`.
3. Assert the phase parser separately against plan fixtures: 0-indexed, 1-indexed, reordered, `[/]` present and absent, `[-]` cancelled, all done, unlabelled titles, over-length title.
4. Exit non-zero on any drift so it can gate a commit.

Exit criteria: `./test/render-cases.sh --check` passes, and deliberately breaking the glyph accounting makes it fail.

## Phase 2: Rate limits and cache health

Goal: surface the two payload fields that change what you should do next.

`rate_limits.five_hour.used_percentage` with its `resets_at` is the highest value unused field for a heavy session. `prompt_cache.warm` with `last_miss_cause.causes[0]` explains sudden latency and is otherwise invisible. Both are optional and absent early in a session, so both must degrade to nothing.

Open question: the bar is already dense. This may need the second line the harness allows rather than more segments on the first.

## Phase 3: PR and worktree awareness

Goal: stop losing track of which branch is which.

`pr.number` with `review_state` mirrors the footer badge, `worktree.name` names a `--worktree` session, and `workspace.repo` gives `owner/name` without shelling out to git at all, which may let the directory segment shorten to something more useful than a truncated path.

## Phase 4: Theme adaptation

Goal: the pinned 256-colour values assume a dark terminal.

The payload carries no theme field and `settings.json` says `"theme": "auto"`, so the options are a cached `defaults read -g AppleInterfaceStyle`, an environment variable set by the shell profile, or retreating to basic ANSI and losing the finer hues. Investigate before committing to one.

## Queued, outside the phases

- Cumulative session token usage, which needs `transcript_path` parsing and a cache, since the payload has no such field.
- A `subagentStatusLine` for the agent panel, which is a separate command with its own payload.
- Whether any of this should be a Node binary. Only worth it if measured, and interpreter startup at 1 Hz is the thing to measure.
