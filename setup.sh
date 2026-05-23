#!/bin/bash
set -e

usage() {
  cat <<'EOF'
Claude Code + DeepSeek Router — instalador

  bash setup.sh              instalación interactiva (pide API key)
  bash setup.sh --help       esta ayuda
  bash setup.sh --no-hooks   instalar sin hook Stop ni change-log
  bash setup.sh --dry-run    mostrar qué se instalaría, sin tocar nada

Qué hace:
  1. Crea el proxy de enrutamiento (~/.claude-code-router/proxy.mjs)
  2. Configura variables en .zshrc/.bashrc (ANTHROPIC_BASE_URL, etc.)
  3. Añade auto-arranque del proxy al abrir terminal
  4. (Opcional) Instala 3 hooks:
     - Stop: registra cambios al salir (por rama)
     - SessionStart: avisa si hay cambios sin procesar para CLAUDE.md
     - PreToolUse: registra cambios antes de git checkout

Requisitos: Node.js >= 18, Claude Code CLI, DeepSeek API key
EOF
  exit 0
}

DRY_RUN=false
NO_HOOKS=false
case "${1:-}" in
  --help|-h) usage ;;
  --dry-run) DRY_RUN=true ;;
  --no-hooks) NO_HOOKS=true ;;
esac

echo "=== Claude Code + DeepSeek Router Setup ==="
$DRY_RUN && echo "[DRY RUN — no se modificará nada]" && set +e

# ── API key ──────────────────────────────────────────
if $DRY_RUN; then
  DS_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxx"
else
  read -p "DeepSeek API key: " DS_KEY
fi
export DEEPSEEK_API_KEY="$DS_KEY"

# ── dirs ─────────────────────────────────────────────
mkdir -p ~/.claude-code-router ~/.claude/hooks

# ── proxy ────────────────────────────────────────────
cat > ~/.claude-code-router/proxy.mjs <<'PROXY'
import http from "node:http";

const UPSTREAM = "https://api.deepseek.com/anthropic/v1/messages";
const API_KEY = process.env.DEEPSEEK_API_KEY;
const FLASH = "deepseek-v4-flash";
const PRO = "deepseek-v4-pro";

function pickModel(body) {
  if (body?.thinking?.type === "enabled") return PRO;
  const json = JSON.stringify(body?.messages ?? "");
  if (json.length / 4 > 60_000) return PRO;
  return FLASH;
}

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
      const upstream = await fetch(UPSTREAM, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": API_KEY,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(body),
      });
      res.writeHead(upstream.status, {
        "Content-Type": "application/json",
        "anthropic-version": "2023-06-01",
      });
      const text = await upstream.text();
      try {
        const u = JSON.parse(text).usage;
        if (u) {
          process.stderr.write(
            `[proxy] → ${body.model} | in:${u.input_tokens} out:${u.output_tokens} cache:${u.cache_read_input_tokens || 0}\n`
          );
        }
      } catch (_) {}
      res.end(text);
    } catch (e) {
      res.writeHead(502).end(JSON.stringify({ error: e.message }));
    }
  });
});

server.listen(3456, () => process.stderr.write("proxy → http://127.0.0.1:3456\n"));
PROXY

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

# Parte 1: change log
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "## $DATE — $BRANCH" >> "$CHANGELOG"
  echo '```' >> "$CHANGELOG"
  git diff --stat HEAD 2>/dev/null >> "$CHANGELOG"
  echo '```' >> "$CHANGELOG"
  echo "" >> "$CHANGELOG"
fi

# Parte 2: guardar sesion
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
from datetime import datetime

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
    'title': '''$(echo "$TITLE" | sed "s/'/\\\'/g")'''
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

python3 -c "
import json, os
from datetime import datetime

sessions_file = '$SESSIONS_FILE'
current_sid = '$CURRENT_SID'
now_ts = $NOW

with open(sessions_file) as f:
    sessions = json.load(f)

recent = []
for s in sessions:
    if s.get('id') == current_sid:
        continue
    try:
        dt = datetime.strptime(s['date'], '%Y-%m-%d %H:%M')
        age = now_ts - dt.timestamp()
        if age > 60:
            recent.append(s)
    except:
        continue

if recent:
    print()
    print('*** SESIONES ANTERIORES ENCONTRADAS ***')
    print('Como primer mensaje en esta conversacion, DEBES preguntar al usuario si quiere retomar alguna:')
    for s in recent[:5]:
        print(f\"  [{s['date']}] {s['title']} ({s.get('branch', '?')})  /resume {s['id'][:8]}\")
    print()
    print('Indica al usuario que puede usar /resume <id> para retomar cualquiera de ellas.')
" 2>/dev/null
HOOK
  chmod +x ~/.claude/hooks/on-session-start.sh

  # settings.json con los 3 hooks
  [ -f ~/.claude/settings.json ] && cp ~/.claude/settings.json ~/.claude/settings.json.bak
  cat > ~/.claude/settings.json <<'SETTINGS'
{
  "theme": "auto",
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/on-stop.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/on-session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "if": "Bash(git checkout *)",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/on-checkout.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
fi

# ── .zshrc / .bashrc ─────────────────────────────────
RC=""
if [ -f ~/.zshrc ]; then RC=~/.zshrc
elif [ -f ~/.bashrc ]; then RC=~/.bashrc
fi

if [ -n "$RC" ]; then
  # remove old lines if re-running
  sed -i '/ANTHROPIC_BASE_URL=http:\/\/127.0.0.1:3456/d' "$RC"
  sed -i '/ANTHROPIC_MODEL=deepseek-v4-pro/d' "$RC"
  sed -i '/DEEPSEEK_API_KEY/d' "$RC"
  sed -i '/proxy.mjs/d' "$RC"
  sed -i '/# Claude Code + DeepSeek Router/d' "$RC"

  cat >> "$RC" <<SHELL

# Claude Code + DeepSeek Router
export DEEPSEEK_API_KEY='$DS_KEY'
export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
export ANTHROPIC_AUTH_TOKEN='$DS_KEY'
export ANTHROPIC_MODEL=deepseek-v4-pro
ss -tln | grep -q 3456 || node ~/.claude-code-router/proxy.mjs 2>>~/.claude-code-router/proxy.log &
SHELL
fi

# ── start proxy now ──────────────────────────────────
ss -tln | grep -q 3456 || node ~/.claude-code-router/proxy.mjs 2>>~/.claude-code-router/proxy.log &

echo ""
echo "Listo. Abre una terminal nueva o ejecuta: source $RC"
echo "Logs del proxy: tail -f ~/.claude-code-router/proxy.log"
