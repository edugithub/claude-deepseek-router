#!/bin/bash
set -e

usage() {
  cat <<'EOF'
Claude Code + DeepSeek Router — instalador

  bash setup.sh                            instalacion interactiva
  bash setup.sh --help                     esta ayuda
  bash setup.sh --no-hooks                 instalar sin hooks
  bash setup.sh --dry-run                  mostrar que se instalaria

Flags de configuracion (opcional):
  --default-model <m>      modelo para requests normales (default: deepseek-v4-flash)
  --think-model <m>        modelo para thinking (default: deepseek-v4-pro)
  --longcontext-model <m>  modelo para contexto largo (default: deepseek-v4-pro)
  --background-model <m>   modelo para tareas en background (default: deepseek-v4-pro)
  --provider-url <url>     API base URL del provider
  --provider-models <list> modelos del provider separados por coma

Ejemplo:
  bash setup.sh --think-model deepseek-v4-pro --default-model deepseek-v4-flash

Que hace:
  1. Crea el proxy de enrutamiento (~/.claude-code-router/proxy.mjs)
  2. Configura variables en .zshrc/.bashrc (ANTHROPIC_BASE_URL, etc.)
  3. Anade auto-arranque del proxy al abrir terminal
  4. Instala router-config CLI para gestionar la configuracion
  5. (Opcional) Instala 3 hooks:
     - Stop: registra cambios al salir (por rama)
     - SessionStart: avisa si hay cambios sin procesar para CLAUDE.md
     - PreToolUse: registra cambios antes de git checkout

Requisitos: Node.js >= 18, Claude Code CLI, DeepSeek API key
EOF
  exit 0
}

DRY_RUN=false
NO_HOOKS=false
DEFAULT_MODEL="deepseek-v4-flash"
THINK_MODEL="deepseek-v4-pro"
LONGCONTEXT_MODEL="deepseek-v4-pro"
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
    *) echo "Opcion desconocida: $1"; usage ;;
  esac
done

echo "=== Claude Code + DeepSeek Router Setup ==="
$DRY_RUN && echo "[DRY RUN — no se modificara nada]" && set +e

# ── API key ──────────────────────────────────────────
if $DRY_RUN; then
  DS_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxx"
else
  read -p "DeepSeek API key: " DS_KEY
fi
export DEEPSEEK_API_KEY="$DS_KEY"

# ── routing config (interactivo si no se usaron flags) ─
if ! $FLAGS_SET && ! $DRY_RUN; then
  echo ""
  echo "--- Routing configuration (Enter = defaults) ---"
  read -p "  Modelo por defecto [$DEFAULT_MODEL]: " INPUT
  [ -n "$INPUT" ] && DEFAULT_MODEL="$INPUT"
  read -p "  Modelo para thinking [$THINK_MODEL]: " INPUT
  [ -n "$INPUT" ] && THINK_MODEL="$INPUT"
  read -p "  Modelo para contexto largo [$LONGCONTEXT_MODEL]: " INPUT
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
    echo "[dry-run] se instalaria nvm + Node.js $NVM_LTS"
  else
    echo "Node.js >= 18 no encontrado (actual: $(node -v 2>/dev/null || echo 'none'))."
    if ! command -v nvm >/dev/null 2>&1 && [ ! -s "$HOME/.nvm/nvm.sh" ]; then
      read -p "  Instalar nvm + Node.js $NVM_LTS? [S/n] " INSTALL_NVM
    else
      load_nvm
      read -p "  Instalar Node.js $NVM_LTS via nvm? [S/n] " INSTALL_NVM
    fi
    if [ "$INSTALL_NVM" != "n" ] && [ "$INSTALL_NVM" != "N" ]; then
      if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
        load_nvm
      fi
      if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
        echo "ERROR: No se pudo cargar nvm. Reinicia la terminal y vuelve a ejecutar setup.sh"
        exit 1
      fi
      nvm install "$NVM_LTS" && nvm use "$NVM_LTS" || true
    else
      echo "Instala Node.js >= 18 manualmente y vuelve a ejecutar setup.sh"
      echo "  Recomendado: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
      exit 1
    fi
  fi
fi
# Re-validate: solo cargar nvm si node no esta ya en PATH
if ! node -v >/dev/null 2>&1; then
  load_nvm
fi
NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v//;s/\..*//')
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ]; then
  echo "ERROR: Node.js >= 18 requerido (actual: $(node -v 2>/dev/null || echo 'none'))."
  echo "  Instalalo via: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
  exit 1
fi

# ── jq ─────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  if $DRY_RUN; then
    echo "[dry-run] se instalaria jq"
  else
    echo "jq no encontrado. Instalando..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y jq
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm jq
    elif command -v brew >/dev/null 2>&1; then
      brew install jq
    else
      echo "ERROR: No se pudo instalar jq automaticamente. Instalalo manualmente."
      exit 1
    fi
  fi
fi

# ── npm ────────────────────────────────────────────
load_nvm
if ! command -v npm >/dev/null 2>&1; then
  if $DRY_RUN; then
    echo "[dry-run] se instalaria npm"
  else
    echo "npm no encontrado. Instalando..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y npm
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y npm
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm npm
    elif command -v brew >/dev/null 2>&1; then
      brew install npm
    else
      echo "ERROR: No se pudo instalar npm automaticamente. Instalalo manualmente."
      exit 1
    fi
  fi
fi

# ── claude ─────────────────────────────────────────
load_nvm
if ! command -v claude >/dev/null 2>&1; then
  if $DRY_RUN; then
    echo "[dry-run] se instalaria Claude Code CLI"
  else
    echo ""
    echo "Claude Code CLI no encontrado."
    echo "  Instalacion oficial: npm install -g @anthropic-ai/claude-code"
    read -p "  Instalar ahora con npm? [S/n] " INSTALL_CLAUDE
    if [ "$INSTALL_CLAUDE" != "n" ] && [ "$INSTALL_CLAUDE" != "N" ]; then
      npm install -g @anthropic-ai/claude-code || {
        echo "ERROR: Fallo la instalacion. Instalalo manualmente:"
        echo "  npm install -g @anthropic-ai/claude-code"
        exit 1
      }
    else
      echo "Instala Claude Code CLI manualmente y vuelve a ejecutar setup.sh"
      echo "  npm install -g @anthropic-ai/claude-code"
      exit 1
    fi
  fi
fi

# ── dirs ─────────────────────────────────────────────
mkdir -p ~/.claude-code-router ~/.claude/hooks

# ── proxy ────────────────────────────────────────────
cat > ~/.claude-code-router/proxy.mjs <<'PROXY'
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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

function pickModel(body) {
  if (body?.thinking?.type === "enabled") {
    return parseRouter(config.Router?.think).model;
  }
  const json = JSON.stringify(body?.messages ?? "");
  const threshold = config.Router?.longContextThreshold ?? 60_000;
  if (json.length / 4 > threshold) {
    return parseRouter(config.Router?.longContext).model;
  }
  return parseRouter(config.Router?.default).model;
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
      body.model = pickModel(body);
      const sid = req.headers["x-claude-code-session-id"];
      if (sid) {
        fs.mkdirSync(path.join(os.homedir(), ".claude-code-router", "last-model"), { recursive: true });
        fs.writeFileSync(path.join(os.homedir(), ".claude-code-router", "last-model", sid), body.model);
      }
      const provider = providerForModel(body.model);
      const upstreamUrl = provider.api_base_url;

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
        let inputTokens = 0, outputTokens = 0, cacheTokens = 0;
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
                  cacheTokens = data.message.usage.cache_read_input_tokens || 0;
                }
                if (data.type === "message_delta" && data.usage) {
                  outputTokens = data.usage.output_tokens || 0;
                }
              } catch (_) {}
            }
          }
          res.write(chunk);
        }
        log(`[proxy] >> ${body.model} | in:${inputTokens} out:${outputTokens} cache:${cacheTokens}`);
        res.end();
      } else {
        const text = await upstream.text();
        try {
          const u = JSON.parse(text).usage;
          if (u) {
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
cat > ~/.claude-code-router/config.json <<CONFIG
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
    "longContextThreshold": 30000
  }
}
CONFIG

# ── rotate-logs.sh ────────────────────────────────────
cat > ~/.claude-code-router/rotate-logs.sh <<'ROTATE'
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
cat > ~/.claude-code-router/router-config <<'RCCLI'
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
    "Uso: router-config <comando> [args]",
    "",
    "Comandos:",
    "  (sin comando)                    Mostrar config actual",
    "  get <key.dotted.path>            Obtener un valor (ej: Router.default)",
    "  set <key.dotted.path> <valor>    Establecer un valor",
    "  help                             Mostrar esta ayuda",
    "  restart                          Reiniciar el proxy (aplica cambios de config)",
    "",
    "  provider <nombre>                Mostrar proveedor",
    "  provider <nombre> --api-base-url <url> [--models \"m1,m2\"]",
    "                                   Actualizar o crear proveedor",
    "",
    "Ejemplos:",
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
    if (!key) { console.error("Uso: router-config get <key>"); process.exit(1); }
    const val = getByPath(config, key);
    if (val === undefined) { console.error("Key not found: " + key); process.exit(1); }
    console.log(typeof val === "object" ? JSON.stringify(val, null, 2) : val);
    return;
  }

  if (cmd === "set") {
    const key = args[1];
    const raw = args.slice(2).join(" ");
    if (!key || !raw) { console.error("Uso: router-config set <key> <valor>"); process.exit(1); }
    setByPath(config, key, parseValue(raw));
    writeConfig(config);
    console.log("[ok] " + key + " = " + JSON.stringify(getByPath(config, key)));
    return;
  }

  if (cmd === "provider") {
    const name = args[1];
    if (!name) { console.error("Uso: router-config provider <nombre> [--api-base-url ...] [--models ...]"); process.exit(1); }
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
    console.log("[ok] provider " + name + " actualizado:\n" + JSON.stringify(p, null, 2));
    return;
  }

  if (cmd === "restart") {
    try {
      const pid = execSync("pgrep -f 'proxy\\.mjs' | head -1", { encoding: "utf-8" }).trim();
      if (pid) execSync("kill " + pid);
    } catch (_) { /* proxy not running */ }
    const proxyPath = path.join(os.homedir(), ".claude-code-router", "proxy.mjs");
    execSync("node " + proxyPath + " &", { stdio: "ignore" });
    console.log("[ok] proxy reiniciado");
    return;
  }

  console.error("Comando desconocido: " + cmd + " — usa: router-config help");
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
  cat > ~/.claude/hooks/on-stop.sh <<'HOOK'
#!/bin/bash
STDIN=$(cat)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git branch --show-current 2>/dev/null)
DATE=$(date '+%Y-%m-%d %H:%M')
SESSIONS_FILE="$ROOT/.claude/sessions.json"
CHANGELOG="$ROOT/.claude-change-log.md"

if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "## $DATE — $BRANCH" >> "$CHANGELOG"
  echo '```' >> "$CHANGELOG"
  git diff --stat HEAD 2>/dev/null >> "$CHANGELOG"
  echo '```' >> "$CHANGELOG"
  echo "" >> "$CHANGELOG"
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
" 2>/dev/null
HOOK
  chmod +x ~/.claude/hooks/on-stop.sh

  # on-checkout: registra cambios antes de cambiar de rama
  cat > ~/.claude/hooks/on-checkout.sh <<'HOOK'
#!/bin/bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
LOG="$ROOT/.claude-change-log.md"
BRANCH=$(git branch --show-current 2>/dev/null)
DATE=$(date '+%Y-%m-%d %H:%M')
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "## $DATE — $BRANCH (checkout)" >> "$LOG"
  echo '```' >> "$LOG"
  git diff --stat HEAD 2>/dev/null >> "$LOG"
  echo '```' >> "$LOG"
  echo "" >> "$LOG"
fi
HOOK
  chmod +x ~/.claude/hooks/on-checkout.sh

  # on-session-start: avisa cambios + sesiones recientes
  cat > ~/.claude/hooks/on-session-start.sh <<'HOOK'
#!/bin/bash
STDIN=$(cat)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CHANGELOG="$ROOT/.claude-change-log.md"
SESSIONS_FILE="$ROOT/.claude/sessions.json"

if [ -f "$CHANGELOG" ] && [ "$(wc -l < "$CHANGELOG")" -gt 0 ]; then
  echo "AVISO: Hay cambios registrados en .claude-change-log.md."
  echo "Revisa el change log y actualiza CLAUDE.md con lo relevante."
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
    print('*** SESIONES ANTERIORES ***')
    print('Como PRIMER mensaje, usa la herramienta AskUserQuestion con estas opciones:')
    print()
    opts = []
    for s in valid[:4]:
        label = s['title'][:60]
        sid = s['id']
        opts.append({
            'label': label,
            'description': f\"{s['date']} - {s.get('branch', '?')}\",
            'resume_id': sid
        })
    print('PREGUNTA: \"Quieres retomar alguna sesion anterior?\"')
    print('OPCIONES:')
    for i, o in enumerate(opts):
        print(f\"  {i+1}. {o['label']} ({o['description']}) -> /resume {o['resume_id']}\")
    print('OPCION_EXTRA: \"No, empezar nueva sesion\"')
    print()
    print('IMPORTANTE: Usa AskUserQuestion YA MISMO, no esperes a que el usuario escriba.')
" 2>/dev/null
HOOK
  chmod +x ~/.claude/hooks/on-session-start.sh

  # ── statusline.sh ──────────────────────────────────────
  mkdir -p ~/.claude
  cat > ~/.claude/statusline.sh <<'STATUS'
#!/bin/bash
input=$(cat)
SID=$(echo "$input" | jq -r '.session_id // ""')
MODEL=$(cat "$HOME/.claude-code-router/last-model/$SID" 2>/dev/null || echo "$input" | jq -r '.model.display_name // "?"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "?"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | floor')
IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
EFFORT=$(echo "$input" | jq -r '.effort.level // "?"')
BAR_SIZE=10
FILL=$((PCT * BAR_SIZE / 100))
BAR=""
for ((i=0; i<BAR_SIZE; i++)); do
  if [ $i -lt $FILL ]; then BAR="${BAR}█"; else BAR="${BAR}░"; fi
done
echo "[$MODEL] 📁 ${DIR##*/} | in:${IN} out:${OUT} | ${PCT}% ${BAR} | ⚡${EFFORT}"
STATUS
  chmod +x ~/.claude/statusline.sh

  # Merge hooks and statusline into settings.json (no sobrescribe)
  python3 -c "
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

os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('[ok] hooks and statusline merged into settings.json')
"
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

  cat >> "$RC" <<SHELL

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
echo "Listo. Abre una terminal nueva o ejecuta: source $RC"
echo "Logs del proxy: tail -f ~/.claude-code-router/proxy.log"
