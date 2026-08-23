# Claude Code + DeepSeek Router

Intelligent routing proxy for [Claude Code CLI](https://github.com/anthropics/claude-code) using DeepSeek models (v4-flash / v4-pro). No external dependencies, native Node.js only.

## How it works

```
claude → proxy (127.0.0.1:3456) → DeepSeek API
                                   ├─ v4-flash (simple tasks)
                                   └─ v4-pro  (thinking / plan mode / long context)
```

The proxy inspects each request and decides the model:

| Condition | Model |
|---|---|
| First call (no real usage yet) | `deepseek-v4-flash` |
| Real context < `longContextThreshold` (500K) | `deepseek-v4-flash` |
| Real context > `longContextThreshold` (500K) | `deepseek-v4-pro` |
| Plan mode active (`/plan`) | `deepseek-v4-pro` + `reasoning.effort` |
| Background tasks | `deepseek-v4-pro` |

### Behavior details

- **Per-session real context**: the proxy sums `input + cache_read + cache_creation` from the `usage` DeepSeek returns in each response, and stores it keyed by `x-claude-code-session-id`. Routing therefore uses the *real* context (not estimated) after the first response. On startup (no data yet) it goes to `flash`.
- **Thinking only in plan mode**: with `Router.thinking = "plan"`, the proxy only enables reasoning when it detects the marker `"Plan mode is active"` in the most recent messages (`reasoning.effort = "high"`). Outside plan mode it disables thinking (`thinking.type = "disabled"`) so Flash does not think.
- **Real threshold (500K)**: the `longContextThreshold` installed by default is **500,000** tokens (not 60K). Tune it with `router-config set Router.longContextThreshold`.

## Requirements

- **Node.js >= 18**
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview)** installed
- **DeepSeek API key** — [get one here](https://platform.deepseek.com/api_keys)

## Installation

```bash
git clone https://github.com/edugithub/claude-deepseek-router.git
cd claude-deepseek-router
bash setup.sh
```

It will ask for your DeepSeek API key and configure everything automatically (proxy, hooks, shell variables, status line, and global skills).

## What it installs

| File | Purpose |
|---|---|
| `~/.claude-code-router/proxy.mjs` | Proxy (~235 lines, native Node) |
| `~/.claude-code-router/proxy.log` | Logs: model + tokens per request (direct write, unbuffered) |
| `~/.claude-code-router/config.json` | Providers and routing configuration |
| `~/.claude-code-router/router-config` | CLI to view/modify config.json live |
| `~/.claude-code-router/logs.sh` | Proxy log viewer (alias of `logs.sh` in the repo) |
| `~/.claude-code-router/rotate-logs.sh` | Log rotation via SIGUSR1 |
| `~/.claude-code-router/last-model/<session-id>` | Last model per session (for the status line) |
| `~/.claude-code-router/last-effort/<session-id>` | Real effort used per session (for the status line) |
| `~/.claude-code-router/last-balance` | Cached DeepSeek balance (automatic polling) |
| `~/.claude-code-router/.env` | Source of truth for credentials/config (gitignored) |
| `~/.claude/hooks/on-stop.sh` | Stop hook: logs git diff per branch + session metadata on exit |
| `~/.claude/hooks/on-checkout.sh` | PreToolUse hook: logs changes before git checkout |
| `~/.claude/hooks/on-session-start.sh` | SessionStart hook: warns about changes + sessions to resume |
| `~/.claude/statusline.sh` | Status line: branch, context, tokens, effort, model, balance |
| `~/.claude/settings.json` | Claude Code config + hooks + status line + `env` block |
| `~/.claude/skills/` | Global skills (coding-workflow, refactoring, debugging) |
| `$PROJECT/.claude/sessions.json` | Session metadata (id, date, branch, title) |
| Variables in `.zshrc`/`.bashrc` | Auto-start of the proxy, `PATH` |

## Daily use

Open a terminal and run Claude Code normally. The proxy autostarts.

```bash
claude
```

To watch routing live:

```bash
bash logs.sh                      # last 20 lines (from the repo)
bash ~/.claude-code-router/logs.sh  # or from anywhere
bash logs.sh -f                   # follow live (tail -f)
bash logs.sh -n 5                 # only 5 lines
```

Typical output:

```
[proxy] >> deepseek-v4-flash | in:1234 out:567 cache:0
[proxy] >> deepseek-v4-pro  | in:8921 out:2341 cache:123
```

Columns: `model | in:input_tokens out:output_tokens cache:cache_hit_tokens`

## Status line

The installer configures a **status line** in the Claude Code prompt showing live session info:

```
⎇ main  ▰▰▱▱▱▱▱▱▱▱  19%  ·  15.0k in  3.5k out  ·  -  [deepseek-v4-flash]  ·  $ 5.71
```

| Component | Description |
|---|---|
| `⎇ main` | Current git branch (with `⊞` if it is a worktree) |
| `▰▰▱▱▱▱▱▱▱▱  19%` | Context window usage percentage + 10-block visual bar |
| `15.0k in  3.5k out` | Total input/output tokens in the session (k-formatted) |
| `-` | Real effort used by the proxy (`R:high` in plan mode, `no-thinking` outside) |
| `[deepseek-v4-flash]` | Real model routed by the proxy (reads `last-model/<sid>`) |
| `$ 5.71` | DeepSeek balance in USD (reads `last-balance`) |

> **Note:** The shown model reflects the proxy's real-time routing decision (flash for simple requests, pro for plan mode/long context), not the model set in `ANTHROPIC_MODEL`. The balance updates automatically on each request (a free API call, cached in `last-balance`).

## DeepSeek balance

The proxy polls the [balance endpoint](https://api-docs.deepseek.com/api/get-user-balance/) automatically:

- Fires on **each request** (each prompt) in the background, without blocking routing.
- It is a **free** endpoint (does not consume model tokens), so there is no throttling.
- Writes the result to `~/.claude-code-router/last-balance`, which the status line reads locally (microseconds, no network).
- On failure (e.g. HTTP 500) it writes a `[proxy] balance warn` line to the log and **does not break the proxy**.

## Global skills

`setup.sh` copies the skills in the repo to `~/.claude/skills/`, available in **all** projects:

| Skill | Purpose |
|---|---|
| `coding-workflow` | Implementation workflow: task classification, minimal change, multi-file consistency, verification, and completion check |
| `refactoring` | Refactoring protocol that preserves behavior |
| `debugging` | Distinguish root cause from symptom, trace the path, fix the minimum |

These skills **reduce process failures** (especially on Flash with thinking off and reduced output), but they **do not decide the model** — the proxy always does.

## router-config CLI

`router-config` lets you view and modify the proxy configuration live.

```bash
router-config                              # Show current config
router-config get Router.think             # See thinking model
router-config set Router.think "deepseek,deepseek-v4-pro"  # Change it
router-config set Router.longContextThreshold 500000       # Context threshold
router-config provider deepseek            # View provider
router-config provider deepseek --api-base-url https://... --models "flash,pro"
router-config restart                      # Restart the proxy (apply changes)
```

### Initial configuration with flags

`setup.sh` accepts flags to customize routing without interactive input:

```bash
bash setup.sh \
  --default-model deepseek-v4-flash \
  --think-model deepseek-v4-pro \
  --longcontext-model deepseek-v4-pro \
  --background-model deepseek-v4-pro \
  --provider-url https://api.deepseek.com/anthropic/v1/messages \
  --provider-models "deepseek-v4-flash,deepseek-v4-pro"
```

Without flags, the installer asks interactively (pressing Enter uses the default).

## Sessions

On exit, the Stop hook stores session metadata in `.claude/sessions.json`:

```json
[
  {
    "id": "abc12345",
    "date": "2026-05-23 16:30",
    "branch": "main",
    "title": "Fix login button"
  }
]
```

On opening a new session in the same project, the SessionStart hook shows recent sessions and Claude Code asks whether you want to resume one.

```
Recent sessions in this project:
  - [2026-05-23 16:30] Fix login button (main)  /resume abc12345
```

Use `/resume <id>` to resume a previous session.

## Credentials

You only need the **DeepSeek API key**. It is asked during installation and stored in `~/.claude-code-router/.env` (which the proxy reads) plus the `env` block of `~/.claude/settings.json` for Claude Code. It is **never** written to `config.json` or to files in the repo.

> **Security warning:** do not put the key in permissions of `~/.claude/settings.local.json`. A `PermissionRule` embedding the key in plain text exposes it in local files and logs; use the environment (`DEEPSEEK_API_KEY`) instead. If it is already there, rotate it.

## Porting to another machine

```bash
git clone https://github.com/edugithub/claude-deepseek-router.git
cd claude-deepseek-router && bash setup.sh
```

`setup.sh` reuses an existing `~/.claude-code-router/.env` as defaults (it will not ask again if one is present), so any machine that already has the `.env` installs without re-entering credentials.

## License

Public domain. No restrictions.
