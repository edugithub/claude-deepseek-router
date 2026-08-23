#!/bin/bash
set -e

usage() {
  cat <<'EOF'
Claude Code + DeepSeek Router — installer

  bash setup.sh                            interactive install
  bash setup.sh --help                     this help
  bash setup.sh --no-hooks                 install without hooks
  bash setup.sh --dry-run                  show what would be installed

Config flags (optional):
  --default-model <m>      model for normal requests (default: deepseek-v4-flash)
  --think-model <m>        model for thinking (default: deepseek-v4-pro)
  --longcontext-model <m>  model for long context (default: deepseek-v4-pro)
  --background-model <m>   model for background tasks (reserved: no signal detected
                           yet; traffic uses default routing today)
  --provider-url <url>     provider API base URL
  --provider-models <list> provider models, comma-separated

Example:
  bash setup.sh --think-model deepseek-v4-pro --default-model deepseek-v4-flash

What it does:
  1. Creates the routing proxy (~/.claude-code-router/proxy.mjs)
  2. Configures variables in .zshrc/.bashrc (ANTHROPIC_BASE_URL, etc.)
  3. Adds proxy auto-start when the terminal opens
  4. Installs the router-config CLI to manage the configuration
  5. (Optional) Installs 3 hooks:
     - Stop: records changes on exit (per branch)
     - SessionStart: warns if there are unprocessed changes for CLAUDE.md
     - PreToolUse: records changes before git checkout
  6. Installs global skills in ~/.claude/skills/ (coding-workflow, refactoring, debugging)
  7. Writes ~/.claude-code-router/.env (credentials/config source) and projects its
     env block into ~/.claude/settings.json

Requirements: Node.js >= 18, Claude Code CLI, DeepSeek API key
EOF
  exit 0
}

DRY_RUN=false
NO_HOOKS=false
DEFAULT_MODEL="deepseek-v4-flash"
THINK_MODEL="deepseek-v4-pro"
LONGCONTEXT_MODEL="deepseek-v4-pro"
# Reserved: background requests cannot be detected reliably (no field/header from
# Claude Code), so this config is NOT read by pickModel today. Kept for when a
# signal exists. Background traffic follows the default flash routing.
BACKGROUND_MODEL="deepseek-v4-pro"
PROVIDER_URL="https://api.deepseek.com/anthropic/v1/messages"
PROVIDER_MODELS="deepseek-v4-flash,deepseek-v4-pro"
FLAGS_SET=false

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --help|-h) usage ;;
    --dry-run) DRY_RUN=true; shift ;;
    --no-hooks) NO_HOOKS=true; shift ;;
    --default-model) DEFAULT_MODEL="$2"; FLAGS_SET=true; shift 2 ;;
    --think-model) THINK_MODEL="$2"; FLAGS_SET=true; shift 2 ;;
    --longcontext-model) LONGCONTEXT_MODEL="$2"; FLAGS_SET=true; shift 2 ;;
    --background-model) BACKGROUND_MODEL="$2"; FLAGS_SET=true; shift 2 ;;
    --provider-url) PROVIDER_URL="$2"; FLAGS_SET=true; shift 2 ;;
    --provider-models) PROVIDER_MODELS="$2"; FLAGS_SET=true; shift 2 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

echo "=== Claude Code + DeepSeek Router Setup ==="
$DRY_RUN && echo "[DRY RUN — nothing will be modified]" && set +e

# Funciones de escritura que respetan --dry-run. Todos los heredocs (<<DELIM)
# pasan por aqui: en dry-run se muestra que se haria pero NO se escribe.
write_file() { if $DRY_RUN; then echo "[dry-run] would write: $1"; else cat > "$1"; fi; }
append_file() { if $DRY_RUN; then echo "[dry-run] would append to: $1"; else cat >> "$1"; fi; }

# ── .env fuente: reutilizar si ya existe ──────────────
# En Camino B, ~/.claude-code-router/.env es la fuente de verdad. Si ya existe
# (de una instalacion previa o porque se copio a otra maquina), lo leemos como
# defaults y no volvemos a pedir la key. Los flags explícitos siguen mandando.
ENV_PATH="$HOME/.claude-code-router/.env"
ENV_EXISTS=false
load_env_defaults() {
  [ -f "$ENV_PATH" ] || return 0
  ENV_EXISTS=true
  local k v
  while IFS= read -r line; do
    line="${line%%#*}"
    [ -z "$line" ] && continue
    k="${line%%=*}"; v="${line#*=}"
    k="${k//[[:space:]]/}"; v="${v//[[:space:]]/}"
    [ -z "$k" ] && continue
    case "$k" in
      DEEPSEEK_API_KEY)        [ -z "$DS_KEY" ] && DS_KEY="${v//\'/}" ;;
      ANTHROPIC_DEFAULT_OPUS_MODEL)  [ -z "$THINK_MODEL" ] && THINK_MODEL="${v//\'/}" ;;
      ANTHROPIC_DEFAULT_SONNET_MODEL) [ -z "$DEFAULT_MODEL" ] && DEFAULT_MODEL="${v//\'/}" ;;
      ANTHROPIC_DEFAULT_HAIKU_MODEL)  [ -z "$LONGCONTEXT_MODEL" ] && LONGCONTEXT_MODEL="${v//\'/}" ;;
    esac
  done < "$ENV_PATH"
}
load_env_defaults
if $ENV_EXISTS && ! $FLAGS_SET; then
  echo "→ Existing .env detected (~/.claude-code-router/.env). Reusing configuration."
fi

# ── API key ──────────────────────────────────────────
if $DRY_RUN; then
  DS_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxx"
elif $ENV_EXISTS && [ -n "$DS_KEY" ] && [ "$DS_KEY" != "sk-xxxxxxxxxxxxxxxxxxxxxxxx" ]; then
  read -p "DeepSeek API key [already in .env, Enter to keep]: " INPUT
  [ -n "$INPUT" ] && DS_KEY="$INPUT"
else
  read -p "DeepSeek API key: " DS_KEY
fi
export DEEPSEEK_API_KEY="$DS_KEY"

# ── routing config (interactivo si no se usaron flags) ─
if ! $FLAGS_SET && ! $DRY_RUN; then
  echo ""
  echo "--- Routing configuration (Enter = defaults) ---"
  read -p "  Default model [$DEFAULT_MODEL]: " INPUT
  [ -n "$INPUT" ] && DEFAULT_MODEL="$INPUT"
  read -p "  Thinking model [$THINK_MODEL]: " INPUT
  [ -n "$INPUT" ] && THINK_MODEL="$INPUT"
  read -p "  Long-context model [$LONGCONTEXT_MODEL]: " INPUT
  [ -n "$INPUT" ] && LONGCONTEXT_MODEL="$INPUT"
  read -p "  Provider API base URL [$PROVIDER_URL]: " INPUT
  [ -n "$INPUT" ] && PROVIDER_URL="$INPUT"
  echo ""
fi

# ── nvm + node ─────────────────────────────────────
load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm use default 2>/dev/null || true
    # nvm a veces no exporta PATH correctamente desde una funcion
    NODE_BIN=$(nvm which default 2>/dev/null | head -1) || true
    [ -n "$NODE_BIN" ] && export PATH="$(dirname "$NODE_BIN"):$PATH"
  fi
  true
}
NVM_LTS="lts/jod"
NEED_NODE=false
load_nvm
if ! command -v node >/dev/null 2>&1; then
  NEED_NODE=true
else
  NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v//;s/\..*//')
  if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ]; then
    NEED_NODE=true
  fi
fi
if $NEED_NODE; then
  if $DRY_RUN; then
    echo "[dry-run] would install nvm + Node.js $NVM_LTS"
  else
    echo "Node.js >= 18 not found (current: $(node -v 2>/dev/null || echo 'none'))."
    if ! command -v nvm >/dev/null 2>&1 && [ ! -s "$HOME/.nvm/nvm.sh" ]; then
      read -p "  Install nvm + Node.js $NVM_LTS? [S/n] " INSTALL_NVM
    else
      load_nvm
      read -p "  Install Node.js $NVM_LTS via nvm? [S/n] " INSTALL_NVM
    fi
    if [ "$INSTALL_NVM" != "n" ] && [ "$INSTALL_NVM" != "N" ]; then
      if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
        load_nvm
      fi
      if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
        echo "ERROR: Could not load nvm. Restart the terminal and re-run setup.sh"
        exit 1
      fi
      nvm install "$NVM_LTS" && nvm use "$NVM_LTS" || true
    else
      echo "Install Node.js >= 18 manually and re-run setup.sh"
      echo "  Recommended: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
      exit 1
    fi
  fi
fi
# Re-validate: only load nvm if node is not already in PATH
if ! node -v >/dev/null 2>&1; then
  load_nvm
fi
NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v//;s/\..*//')
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ]; then
  echo "ERROR: Node.js >= 18 required (current: $(node -v 2>/dev/null || echo 'none'))."
  echo "  Install via: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
  exit 1
fi

# ── jq ─────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  if $DRY_RUN; then
    echo "[dry-run] would install jq"
  else
    echo "jq not found. Installing..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y jq
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm jq
    elif command -v brew >/dev/null 2>&1; then
      brew install jq
    else
      echo "ERROR: Could not install jq automatically. Install it manually."
      exit 1
    fi
  fi
fi

# ── npm ────────────────────────────────────────────
load_nvm
if ! command -v npm >/dev/null 2>&1; then
  if $DRY_RUN; then
    echo "[dry-run] would install npm"
  else
    echo "npm not found. Installing..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y npm
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y npm
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm npm
    elif command -v brew >/dev/null 2>&1; then
      brew install npm
    else
      echo "ERROR: Could not install npm automatically. Install it manually."
      exit 1
    fi
  fi
fi

# ── claude ─────────────────────────────────────────
load_nvm
if ! command -v claude >/dev/null 2>&1; then
  if $DRY_RUN; then
    echo "[dry-run] would install Claude Code CLI"
  else
    echo ""
    echo "Claude Code CLI not found."
    echo "  Official install: npm install -g @anthropic-ai/claude-code"
    read -p "  Install now with npm? [S/n] " INSTALL_CLAUDE
    if [ "$INSTALL_CLAUDE" != "n" ] && [ "$INSTALL_CLAUDE" != "N" ]; then
      npm install -g @anthropic-ai/claude-code || {
        echo "ERROR: Install failed. Install it manually:"
        echo "  npm install -g @anthropic-ai/claude-code"
        exit 1
      }
    else
      echo "Install Claude Code CLI manually and re-run setup.sh"
      echo "  npm install -g @anthropic-ai/claude-code"
      exit 1
    fi
  fi
fi

# ── dirs ─────────────────────────────────────────────
mkdir -p ~/.claude-code-router ~/.claude/hooks

# ── .env (fuente de credenciales y de los defaults del CLI) ──────────────
write_file ~/.claude-code-router/.env <<ENV
# Fuente de verdad de credenciales/config del proxy Claude Code + DeepSeek Router.
# Lo consume el proxy (proxy.mjs) y setup.sh para generar el bloque "env" de
# settings.json (las variables que necesita Claude Code). NO se commitnea.
DEEPSEEK_API_KEY='$DS_KEY'
ANTHROPIC_AUTH_TOKEN='$DS_KEY'
ANTHROPIC_BASE_URL=http://127.0.0.1:3456
ANTHROPIC_MODEL=$THINK_MODEL
ANTHROPIC_DEFAULT_OPUS_MODEL=$THINK_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL=$DEFAULT_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL=$DEFAULT_MODEL
CLAUDE_CODE_SUBAGENT_MODEL=$DEFAULT_MODEL
CLAUDE_CODE_EFFORT_LEVEL=auto
ENV

# ── proxy ────────────────────────────────────────────
write_file ~/.claude-code-router/proxy.mjs <<'PROXY'
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// Cargar variables del fichero .env (junto al proxy) si existe. Se aplican SOLO
// si la variable no esta ya en el entorno (el proceso env tiene prioridad). Esto
// permite que el proxy funcione sin depender de exports del shell.
function loadDotEnv() {
  try {
    const envPath = path.join(os.homedir(), ".claude-code-router", ".env");
    const raw = fs.readFileSync(envPath, "utf-8");
    for (let line of raw.split("\n")) {
      line = line.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq === -1) continue;
      let key = line.slice(0, eq).trim();
      let val = line.slice(eq + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      if (!(key in process.env)) process.env[key] = val;
    }
  } catch {
    /* .env opcional; usa process.env */
  }
}
loadDotEnv();

const CONFIG_PATH = path.join(os.homedir(), ".claude-code-router", "config.json");
let config;
try {
  config = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8"));
} catch {
  config = {};
}

const PORT = config.PORT || 3456;
const API_KEY = process.env.DEEPSEEK_API_KEY;
const LOG_PATH = process.env.PROXY_LOG_PATH || path.join(os.homedir(), ".claude-code-router", "proxy.log");
const TIMEOUT_MS = config.API_TIMEOUT_MS || 600_000;

fs.mkdirSync(path.dirname(LOG_PATH), { recursive: true });
fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });

function defaultProvider() {
  return config.Providers?.[0] || { api_base_url: "https://api.deepseek.com/anthropic/v1/messages", models: [] };
}

function parseRouter(str) {
  const parts = (str || "").split(",");
  return { providerName: parts[0] || "deepseek", model: parts[1] || "deepseek-v4-flash" };
}

function providerForModel(model) {
  for (const p of config.Providers || []) {
    if (p.models?.includes(model)) return p;
  }
  return defaultProvider();
}

function pickModel(body, contextTokens) {
  if (body?.reasoning?.effort) {
    return parseRouter(config.Router?.think).model;
  }
  const threshold = config.Router?.longContextThreshold ?? 60_000;
  // Use the real usage tracked from previous responses when available;
  // otherwise start on the lower-cost model (flash) until we have a response.
  if (contextTokens == null) {
    return parseRouter(config.Router?.default).model;
  }
  if (contextTokens > threshold) {
    return parseRouter(config.Router?.longContext).model;
  }
  return parseRouter(config.Router?.default).model;
}

// Real context usage per session, tracked from the provider's response usage
// (input + cache_read + cache_creation). Keyed by x-claude-code-session-id.
const contextBySession = new Map();

// Detect plan mode: Claude Code injects a "Plan mode is active" system message
// into messages[]. It lingers after exiting plan mode (until compaction), so
// only check the most recent messages to avoid false positives in normal mode.
function isPlanMode(body) {
  const msgs = body?.messages || [];
  return msgs.slice(-10).some(
    (m) => m?.role === "system" && /Plan mode is active/i.test(
      typeof m.content === "string" ? m.content : JSON.stringify(m.content || [])
    )
  );
}

// ── balance ───────────────────────────────────────────
// Consulta el saldo de DeepSeek (GET /user/balance) escribiendo el resultado a
// last-balance. Fire-and-forget y asincrono: nunca bloquea el enrutado de
// requests (no va en el camino caliente). Endpoint gratuito (no consume tokens
// de modelo), por lo que se refresca en cada request sin throttling.
const BALANCE_PATH = path.join(os.homedir(), ".claude-code-router", "last-balance");

async function refreshBalance() {
  if (!API_KEY) return;
  try {
    const res = await fetch("https://api.deepseek.com/user/balance", {
      headers: {
        "Accept": "application/json",
        "Authorization": "Bearer " + API_KEY,
      },
    });
    if (!res.ok) throw new Error("balance HTTP " + res.status);
    const data = await res.json();
    fs.mkdirSync(path.dirname(BALANCE_PATH), { recursive: true });
    fs.writeFileSync(BALANCE_PATH, JSON.stringify({
      updated: new Date().toISOString(),
      is_available: data.is_available,
      balance_infos: data.balance_infos,
    }));
  } catch (e) {
    // Falla silenciosa: el balance es un dato no critico, jamas debe romper el proxy.
    log(`[proxy] balance warn: ${e.message}`);
  }
}

let logFd = fs.openSync(LOG_PATH, "a");

function log(msg) {
  fs.writeSync(logFd, msg + "\n");
}

process.on("SIGUSR1", () => {
  fs.closeSync(logFd);
  logFd = fs.openSync(LOG_PATH, "a");
  log("[proxy] log reopened (SIGUSR1)");
});

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST" || !req.url.startsWith("/v1/messages")) {
    res.writeHead(404).end();
    return;
  }

  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", async () => {
    try {
      const body = JSON.parse(raw);
      if (config.Router?.thinking === "plan") {
        if (isPlanMode(body)) {
          body.reasoning = { effort: config.Router?.planEffort || "high" };
        } else {
          body.thinking = { type: "disabled" };
        }
      }
      const sid = req.headers["x-claude-code-session-id"];
      const contextTokens = sid ? contextBySession.get(sid) : null;
      body.model = pickModel(body, contextTokens);
      if (sid) {
        fs.mkdirSync(path.join(os.homedir(), ".claude-code-router", "last-model"), { recursive: true });
        fs.writeFileSync(path.join(os.homedir(), ".claude-code-router", "last-model", sid), body.model);
        const effortLabel = body.reasoning?.effort ? `R:${body.reasoning.effort}` : (body.thinking?.type === "disabled" ? "no-thinking" : "-");
        const effDir = path.join(os.homedir(), ".claude-code-router", "last-effort");
        fs.mkdirSync(effDir, { recursive: true });
        fs.writeFileSync(path.join(effDir, sid), effortLabel);
      }
      const provider = providerForModel(body.model);
      const upstreamUrl = provider.api_base_url;

      // Disparar refresco de balance en background (no bloquea; throttle por cache).
      refreshBalance();

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

      const upstream = await fetch(upstreamUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": API_KEY,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timer);

      const contentType = upstream.headers.get("content-type") || "";
      const resHeaders = { "anthropic-version": "2023-06-01" };
      if (contentType) resHeaders["Content-Type"] = contentType;
      res.writeHead(upstream.status, resHeaders);

      if (contentType.includes("text/event-stream")) {
        let inputTokens = 0, outputTokens = 0, cacheRead = 0, cacheCreation = 0;
        const reader = upstream.body.getReader();
        const decoder = new TextDecoder();

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          const chunk = decoder.decode(value, { stream: true });
          for (const line of chunk.split("\n")) {
            if (line.startsWith("data: ")) {
              try {
                const data = JSON.parse(line.slice(6));
                if (data.type === "message_start" && data.message?.usage) {
                  inputTokens = data.message.usage.input_tokens || 0;
                  cacheRead = data.message.usage.cache_read_input_tokens || 0;
                  cacheCreation = data.message.usage.cache_creation_input_tokens || 0;
                }
                if (data.type === "message_delta" && data.usage) {
                  outputTokens = data.usage.output_tokens || 0;
                }
              } catch (_) {}
            }
          }
          res.write(chunk);
        }
        if (sid) contextBySession.set(sid, inputTokens + cacheRead + cacheCreation);
        log(`[proxy] >> ${body.model} | in:${inputTokens} out:${outputTokens} cache:${cacheRead}`);
        res.end();
      } else {
        const text = await upstream.text();
        try {
          const u = JSON.parse(text).usage;
          if (u) {
            if (sid) contextBySession.set(sid, (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0));
            log(`[proxy] >> ${body.model} | in:${u.input_tokens} out:${u.output_tokens} cache:${u.cache_read_input_tokens || 0}`);
          }
        } catch (_) {}
        res.end(text);
      }
    } catch (e) {
      log(`[proxy] ERROR: ${e.message}`);
      res.writeHead(502).end(JSON.stringify({ error: e.message }));
    }
  });
});

server.listen(PORT, () => log(`proxy >> http://127.0.0.1:${PORT}`));

PROXY
# ── config.json ───────────────────────────────────────
# NOTE: "background" is RESERVED (no background signal detected from Claude Code;
# pickModel does not read it). Kept in config for future use. Do not add JSON
# comments inside the heredoc below — it must stay valid JSON.
write_file ~/.claude-code-router/config.json <<CONFIG
{
  "PORT": 3456,
  "API_TIMEOUT_MS": 600000,
  "Providers": [
    {
      "name": "deepseek",
      "api_base_url": "$PROVIDER_URL",
      "models": [$(echo "$PROVIDER_MODELS" | sed 's/,/","/g; s/^/"/; s/$/"/')]
    }
  ],
  "Router": {
    "default": "deepseek,$DEFAULT_MODEL",
    "background": "deepseek,$BACKGROUND_MODEL",
    "think": "deepseek,$THINK_MODEL",
    "longContext": "deepseek,$LONGCONTEXT_MODEL",
    "longContextThreshold": 500000,
    "thinking": "plan",
    "planEffort": "high"
  }
}
CONFIG

# ── rotate-logs.sh ────────────────────────────────────
write_file ~/.claude-code-router/rotate-logs.sh <<'ROTATE'
#!/bin/bash
PID=$(pgrep -f "proxy.mjs" | head -1)
if [ -z "$PID" ]; then
  echo "proxy no corriendo"
  exit 1
fi
TS=$(date '+%Y%m%d-%H%M%S')
mv ~/.claude-code-router/proxy.log ~/.claude-code-router/proxy.log."$TS"
kill -USR1 "$PID"
echo "log rotado: proxy.log -> proxy.log.$TS"
ROTATE
chmod +x ~/.claude-code-router/rotate-logs.sh

# ── logs.sh ────────────────────────────────────────────
install -m 755 "$(dirname "$0")/logs.sh" ~/.claude-code-router/logs.sh 2>/dev/null || true

# ── router-config CLI ──────────────────────────────────
write_file ~/.claude-code-router/router-config <<'RCCLI'
#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execSync } from "node:child_process";

const CONFIG_PATH = path.join(os.homedir(), ".claude-code-router", "config.json");

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8"));
  } catch { return {}; }
}

function writeConfig(cfg) {
  fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2) + "\n");
}

function getByPath(obj, kp) {
  let cur = obj;
  for (const p of kp.split(".")) {
    if (cur == null || typeof cur !== "object") return undefined;
    cur = cur[p];
  }
  return cur;
}

function setByPath(obj, kp, val) {
  const parts = kp.split(".");
  let cur = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!(parts[i] in cur) || typeof cur[parts[i]] !== "object") cur[parts[i]] = {};
    cur = cur[parts[i]];
  }
  cur[parts[parts.length - 1]] = val;
}

function findProvider(cfg, name) {
  const ps = cfg.Providers || [];
  return { providers: ps, idx: ps.findIndex((p) => p.name === name) };
}

function parseValue(raw) {
  if (raw === "true") return true;
  if (raw === "false") return false;
  if (raw === "null") return null;
  if (/^-?\d+$/.test(raw)) return parseInt(raw, 10);
  if (/^-?\d+\.\d+$/.test(raw)) return parseFloat(raw);
  return raw;
}

function help() {
  console.log([
    "Usage: router-config <command> [args]",
    "",
    "Commands:",
    "  (no command)                    Show current config",
    "  get <key.dotted.path>           Get a value (e.g. Router.default)",
    "  set <key.dotted.path> <value>   Set a value",
    "  help                            Show this help",
    "  restart                         Restart the proxy (apply config changes)",
    "",
    "  provider <name>                 Show provider",
    "  provider <name> --api-base-url <url> [--models \"m1,m2\"]",
    "                                  Update or create provider",
    "",
    "Examples:",
    "  router-config",
    '  router-config get Router.think',
    '  router-config set Router.think "deepseek,deepseek-v4-pro"',
    "  router-config set Router.longContextThreshold 80000",
    "  router-config provider deepseek --api-base-url https://...",
  ].join("\n"));
}

function main() {
  const args = process.argv.slice(2);
  const cmd = args[0] || "show";
  if (cmd === "help" || cmd === "--help" || cmd === "-h") { help(); return; }

  const config = readConfig();

  if (cmd === "show") { console.log(JSON.stringify(config, null, 2)); return; }

  if (cmd === "get") {
    const key = args[1];
    if (!key) { console.error("Usage: router-config get <key>"); process.exit(1); }
    const val = getByPath(config, key);
    if (val === undefined) { console.error("Key not found: " + key); process.exit(1); }
    console.log(typeof val === "object" ? JSON.stringify(val, null, 2) : val);
    return;
  }

  if (cmd === "set") {
    const key = args[1];
    const raw = args.slice(2).join(" ");
    if (!key || !raw) { console.error("Usage: router-config set <key> <value>"); process.exit(1); }
    setByPath(config, key, parseValue(raw));
    writeConfig(config);
    console.log("[ok] " + key + " = " + JSON.stringify(getByPath(config, key)));
    return;
  }

  if (cmd === "provider") {
    const name = args[1];
    if (!name) { console.error("Usage: router-config provider <name> [--api-base-url ...] [--models ...]"); process.exit(1); }
    const { providers, idx } = findProvider(config, name);
    const apiIdx = args.indexOf("--api-base-url");
    const modIdx = args.indexOf("--models");
    if (apiIdx === -1 && modIdx === -1) {
      if (idx === -1) { console.error("Provider not found: " + name); process.exit(1); }
      console.log(JSON.stringify(providers[idx], null, 2));
      return;
    }
    if (idx === -1) {
      config.Providers = config.Providers || [];
      config.Providers.push({ name, api_base_url: "", models: [] });
    }
    const p = config.Providers[idx === -1 ? config.Providers.length - 1 : idx];
    if (apiIdx !== -1) p.api_base_url = args[apiIdx + 1];
    if (modIdx !== -1) p.models = args[modIdx + 1].split(",").map((s) => s.trim());
    writeConfig(config);
    console.log("[ok] provider " + name + " updated:\n" + JSON.stringify(p, null, 2));
    return;
  }

  if (cmd === "restart") {
    try {
      const pid = execSync("pgrep -f 'proxy\\.mjs' | head -1", { encoding: "utf-8" }).trim();
      if (pid) execSync("kill " + pid);
    } catch (_) { /* proxy not running */ }
    const proxyPath = path.join(os.homedir(), ".claude-code-router", "proxy.mjs");
    execSync("node " + proxyPath + " &", { stdio: "ignore" });
    console.log("[ok] proxy restarted");
    return;
  }

  console.error("Unknown command: " + cmd + " — use: router-config help");
  process.exit(1);
}
main();
RCCLI
chmod +x ~/.claude-code-router/router-config

# ── Hooks ────────────────────────────────────────────
if $NO_HOOKS; then
  echo "Saltando instalacion de hooks (--no-hooks)"
else
  mkdir -p ~/.claude/hooks

  # on-stop: registra cambios + guarda metadata de sesion
  write_file ~/.claude/hooks/on-stop.sh <<'HOOK'
#!/bin/bash
STDIN=$(cat)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git branch --show-current 2>/dev/null)
DATE=$(date '+%Y-%m-%d %H:%M')
SESSIONS_FILE="$ROOT/.claude/sessions.json"
CHANGELOG="$ROOT/.claude-change-log.md"

if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  UNSTAGED=$(git diff --name-only 2>/dev/null | grep -v '^.claude-change-log.md$' || true)
  STAGED=$(git diff --cached --name-only 2>/dev/null | grep -v '^.claude-change-log.md$' || true)
  if [ -n "$UNSTAGED" ] || [ -n "$STAGED" ]; then
    echo "## $DATE — $BRANCH" >> "$CHANGELOG"
    echo '```' >> "$CHANGELOG"
    git diff --stat HEAD 2>/dev/null | grep -v '.claude-change-log.md' >> "$CHANGELOG"
    echo '```' >> "$CHANGELOG"
    echo "" >> "$CHANGELOG"
  fi
fi

SID=$(echo "$STDIN" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('session_id', ''))
" 2>/dev/null)

TRANSCRIPT=$(echo "$STDIN" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('transcript_path', ''))
" 2>/dev/null)

[ -z "$SID" ] && exit 0

TITLE=""
if [ -f "$TRANSCRIPT" ]; then
  TITLE=$(python3 -c "
import sys, json
title = ''
first_prompt = ''
with open('$TRANSCRIPT') as f:
    for line in f:
        try:
            d = json.loads(line.strip())
        except:
            continue
        t = d.get('type', '')
        if t == 'custom-title':
            title = d.get('customTitle', '')
            break
        if t == 'ai-title' and not title:
            title = d.get('aiTitle', '')
        if t == 'user' and not first_prompt:
            msg = d.get('message', '')
            if isinstance(msg, str):
                first_prompt = msg.strip()[:80]
            elif isinstance(msg, list):
                for m in msg:
                    if isinstance(m, dict) and 'text' in m:
                        first_prompt = m['text'].strip()[:80]
                        break
if not title:
    title = first_prompt or 'Sin titulo'
print(title)
" 2>/dev/null)
fi
[ -z "$TITLE" ] && TITLE="Sin titulo"

python3 -c "
import json, os
f = '$SESSIONS_FILE'
sessions = []
if os.path.exists(f):
    try:
        with open(f) as fh:
            sessions = json.load(fh)
    except:
        sessions = []

entry = {
    'id': '$SID',
    'date': '$DATE',
    'branch': '$BRANCH',
    'title': '''$(echo "$TITLE" | sed \"s/'/\\\\'/g\")'''
}

found = False
for i, s in enumerate(sessions):
    if s.get('id') == '$SID':
        sessions[i] = entry
        found = True
        break

if not found:
    sessions.insert(0, entry)

sessions = sessions[:20]

os.makedirs(os.path.dirname(f), exist_ok=True)
with open(f, 'w') as fh:
    json.dump(sessions, fh, ensure_ascii=False, indent=2)
" 2>/dev/null || true
HOOK
  chmod +x ~/.claude/hooks/on-stop.sh

  # on-checkout: registra cambios antes de cambiar de rama
  write_file ~/.claude/hooks/on-checkout.sh <<'HOOK'
#!/bin/bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
LOG="$ROOT/.claude-change-log.md"
BRANCH=$(git branch --show-current 2>/dev/null)
DATE=$(date '+%Y-%m-%d %H:%M')
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  UNSTAGED=$(git diff --name-only 2>/dev/null | grep -v '^.claude-change-log.md$' || true)
  STAGED=$(git diff --cached --name-only 2>/dev/null | grep -v '^.claude-change-log.md$' || true)
  if [ -n "$UNSTAGED" ] || [ -n "$STAGED" ]; then
    echo "## $DATE — $BRANCH (checkout)" >> "$LOG"
    echo '```' >> "$LOG"
    git diff --stat HEAD 2>/dev/null | grep -v '.claude-change-log.md' >> "$LOG"
    echo '```' >> "$LOG"
    echo "" >> "$LOG"
  fi
fi
HOOK
  chmod +x ~/.claude/hooks/on-checkout.sh

  # on-session-start: avisa cambios + sesiones recientes
  write_file ~/.claude/hooks/on-session-start.sh <<'HOOK'
#!/bin/bash
STDIN=$(cat)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CHANGELOG="$ROOT/.claude-change-log.md"
SESSIONS_FILE="$ROOT/.claude/sessions.json"

if [ -f "$CHANGELOG" ] && [ "$(wc -l < "$CHANGELOG")" -gt 0 ]; then
  echo "WARNING: Changes are recorded in .claude-change-log.md."
  echo "Review the change log and update CLAUDE.md with anything relevant."
fi

CURRENT_SID=$(echo "$STDIN" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('session_id', ''))
" 2>/dev/null)

[ -z "$CURRENT_SID" ] && exit 0
[ ! -f "$SESSIONS_FILE" ] && exit 0

NOW=$(date +%s)
HOME_DIR="$HOME"
PROJECT_ROOT="$ROOT"

python3 -c "
import json, os
from datetime import datetime

sessions_file = '$SESSIONS_FILE'
current_sid = '$CURRENT_SID'
now_ts = $NOW
home = '$HOME_DIR'
root = '$PROJECT_ROOT'

sanitized = '-' + root.lstrip('/').replace('/', '-')
transcripts_dir = os.path.join(home, '.claude', 'projects', sanitized)

with open(sessions_file) as f:
    sessions = json.load(f)

valid = []
for s in sessions:
    sid = s.get('id', '')
    if sid == current_sid:
        continue
    try:
        dt = datetime.strptime(s['date'], '%Y-%m-%d %H:%M')
        age = now_ts - dt.timestamp()
        if age <= 60:
            continue
    except:
        continue

    transcript = os.path.join(transcripts_dir, sid + '.jsonl')
    if not os.path.exists(transcript):
        continue

    valid.append(s)

if valid:
    print()
    print('*** PREVIOUS SESSIONS ***')
    print('As the FIRST message, use the AskUserQuestion tool with these options:')
    print()
    opts = []
    for s in valid[:3]:
        label = s['title'][:60]
        sid = s['id']
        opts.append({
            'label': label,
            'description': f\"{s['date']} - {s.get('branch', '?')}\",
            'resume_id': sid
        })
    print('QUESTION: \"Do you want to resume a previous session?\"')
    print('OPTIONS: (mandatory header, max 4 items)')
    for i, o in enumerate(opts):
        print(f\"  {i+1}. {o['label']} ({o['description']}) -> /resume {o['resume_id']}\")
    print(f\"  {len(opts)+1}. No, start a new session\")
    print()
    print('IMPORTANT: Use AskUserQuestion RIGHT NOW, do not wait for the user to type.')
" 2>/dev/null || true
HOOK
  chmod +x ~/.claude/hooks/on-session-start.sh

  # ── statusline.sh ──────────────────────────────────────
  mkdir -p ~/.claude
  write_file ~/.claude/statusline.sh <<'STATUS'
#!/bin/bash
# ── status line for Claude Code ──────────────────────────────────────────────

input=$(cat)

# ── parse input ──────────────────────────────────────────────────────────────
sid=$(jq -r '.session_id // ""' <<<"$input")
dir=$(jq -r '.workspace.current_dir // ""' <<<"$input")
model=$(cat "$HOME/.claude-code-router/last-model/$sid" 2>/dev/null \
        || jq -r '.model.display_name // "?"' <<<"$input")
pct=$(jq -r '.context_window.used_percentage // 0 | floor' <<<"$input")
in_=$(jq -r '.context_window.total_input_tokens // 0' <<<"$input")
out=$(jq -r '.context_window.total_output_tokens // 0' <<<"$input")
eff=$(cat "$HOME/.claude-code-router/last-effort/$sid" 2>/dev/null || echo "-")
# ── balance (leido del cache del proxy; sin llamadas de red) ─────────────────
bal=""
if [ -f "$HOME/.claude-code-router/last-balance" ]; then
  bal=$(jq -r '
    if .is_available == false then "AGOTADO"
    else (.balance_infos[]? | select(.currency=="USD") | .total_balance) // "?"
    end' "$HOME/.claude-code-router/last-balance" 2>/dev/null)
  [ -n "$bal" ] && bal="\$ ${bal}"
fi
# ── git branch + worktree detection ──────────────────────────────────────────
branch=""; wt=""
if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  git -C "$dir" rev-parse --git-common-dir 2>/dev/null | grep -q worktrees && wt=" ⊞"
fi

# ── progress bar (10 blocks) ────────────────────────────────────────────────
fill=$((pct * 10 / 100)); bar=""
for ((i=0; i<10; i++)); do
  [[ $i -lt $fill ]] && bar+="▰" || bar+="▱"
done

# ── format tokens ────────────────────────────────────────────────────────────
fmt() { awk -v n="$1" 'BEGIN{printf "%.1f", n/1000}'; }
in_fmt=$(fmt "$in_")
out_fmt=$(fmt "$out")

# ── assemble output ──────────────────────────────────────────────────────────
git_part=""
[[ -n "$branch" ]] && git_part="⎇ ${branch}${wt}  "
[[ -n "$bal" ]] && bal_part="  ·  ${bal}" || bal_part=""

echo "${git_part}${bar}  ${pct}%  ·  ${in_fmt}k in  ${out_fmt}k out  ·  ${eff}  [${model}]${bal_part}"
STATUS
  chmod +x ~/.claude/statusline.sh

  # Merge hooks and statusline into settings.json (no sobrescribe)
  SETUP_DRY_RUN=$DRY_RUN python3 -c "
import json, os

# Hooks que instalamos
our_hooks = {
    'Stop': [
        {'matcher': '', 'hooks': [{'type': 'command', 'command': os.path.expanduser('~/.claude/hooks/on-stop.sh')}]}
    ],
    'SessionStart': [
        {'matcher': '', 'hooks': [{'type': 'command', 'command': os.path.expanduser('~/.claude/hooks/on-session-start.sh')}]}
    ],
    'PreToolUse': [
        {'matcher': 'Bash', 'if': 'Bash(git checkout *)', 'hooks': [{'type': 'command', 'command': os.path.expanduser('~/.claude/hooks/on-checkout.sh')}]}
    ]
}

cfg = {}
cfg_path = os.path.expanduser('~/.claude/settings.json')
if os.path.exists(cfg_path):
    with open(cfg_path) as f:
        try:
            cfg = json.load(f)
        except:
            pass

# Backup
if cfg:
    with open(cfg_path + '.bak', 'w') as f:
        json.dump(cfg, f, indent=2)

cfg.setdefault('hooks', {})

# Clean old-style PreToolUse entries that fire on every Bash command
ptu = cfg['hooks'].get('PreToolUse', [])
cfg['hooks']['PreToolUse'] = [
    e for e in ptu
    if not (e.get('matcher') == 'Bash' and 'if' not in e
            and any('on-checkout.sh' in h.get('command', '') for h in e.get('hooks', [])))
]

for event, our_triggers in our_hooks.items():
    existing = cfg['hooks'].setdefault(event, [])
    for ot in our_triggers:
        # Avoid duplicates
        already = False
        for et in existing:
            if et.get('matcher') == ot.get('matcher') and et.get('if') == ot.get('if'):
                et_cmds = [h.get('command') for h in et.get('hooks', [])]
                ot_cmds = [h.get('command') for h in ot.get('hooks', [])]
                if et_cmds == ot_cmds:
                    already = True
                    break
        if not already:
            existing.append(ot)

# Status line
cfg['statusLine'] = {
    'type': 'command',
    'command': os.path.expanduser('~/.claude/statusline.sh'),
    'padding': 2
}

# Env vars que necesita Claude Code, generadas desde ~/.claude-code-router/.env
# (fuente de verdad). Asi el CLI no depende de exports del shell.
try:
    env_cfg = {}
    env_path = os.path.expanduser('~/.claude-code-router/.env')
    if os.path.exists(env_path):
        with open(env_path) as ef:
            for line in ef:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                k, _, v = line.partition('=')
                k = k.strip(); v = v.strip()
                if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                    v = v[1:-1]
                # Solo las variables del CLI (no la key del proxy por duplicado no es problema,
                # pero evitamos meter KIMI etc.)
                if k.startswith(('ANTHROPIC_', 'CLAUDE_CODE_')):
                    env_cfg[k] = v
    cfg['env'] = env_cfg
    if os.environ.get('SETUP_DRY_RUN') == 'true':
        print('[dry-run] env block: leido de .env (no escribo)')
    else:
        print('[ok] env block merged into settings.json from .env')
except Exception as e:
    print('[warn] no se pudo mergear env: ' + str(e))

# Effort: 'auto' (deja que /effort o el CLI decidan) a menos que se pida max.
cfg['effortLevel'] = 'auto'

os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
if os.environ.get('SETUP_DRY_RUN') == 'true':
    print('[dry-run] se mergedaria settings.json (no escribo)')
else:
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
    print('[ok] hooks and statusline merged into settings.json')
"
fi

# ── skills globales ────────────────────────────────────
SKILLS_SRC="$(dirname "$0")/skills"
if [ -d "$SKILLS_SRC" ]; then
  if $DRY_RUN; then
    echo "[dry-run] would install global skills to ~/.claude/skills/"
  else
    mkdir -p ~/.claude/skills
    cp -R "$SKILLS_SRC"/. ~/.claude/skills/
    echo "[ok] global skills installed to ~/.claude/skills/"
  fi
fi

# ── .zshrc / .bashrc ─────────────────────────────────
RC=""
if [ -f ~/.zshrc ]; then RC=~/.zshrc
elif [ -f ~/.bashrc ]; then RC=~/.bashrc
fi

if [ -n "$RC" ]; then
  sed -i '/ANTHROPIC_BASE_URL=http:\/\/127.0.0.1:3456/d' "$RC"
  sed -i '/ANTHROPIC_MODEL=deepseek-v4-pro/d' "$RC"
  sed -i '/DEEPSEEK_API_KEY/d' "$RC"
  sed -i '/proxy.mjs/d' "$RC"
  sed -i '/router-config/d' "$RC"
  sed -i '/# Claude Code + DeepSeek Router/d' "$RC"

  append_file "$RC" <<SHELL

# Claude Code + DeepSeek Router
export DEEPSEEK_API_KEY='$DS_KEY'
export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
export ANTHROPIC_AUTH_TOKEN='$DS_KEY'
export ANTHROPIC_MODEL=deepseek-v4-pro
export PATH="\$HOME/.claude-code-router:\$PATH"
ss -tln | grep -q 3456 || node ~/.claude-code-router/proxy.mjs &
SHELL
fi

# ── start proxy now ──────────────────────────────────
ss -tln | grep -q 3456 || node ~/.claude-code-router/proxy.mjs &

echo ""
echo "Done. Open a new terminal or run: source $RC"
echo "Proxy logs: tail -f ~/.claude-code-router/proxy.log"
