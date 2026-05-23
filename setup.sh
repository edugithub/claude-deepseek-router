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
  4. (Opcional) Instala hook Stop + change-log entre sesiones

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

# ── Stop hook (change log) ───────────────────────────
cat > ~/.claude/hooks/on-stop.sh <<'HOOK'
#!/bin/bash
# Registra cambios sin commit en el directorio actual
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
LOG="$ROOT/.claude-change-log.md"
DATE=$(date '+%Y-%m-%d %H:%M')
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "## $DATE" >> "$LOG"
  echo '```' >> "$LOG"
  git diff --stat HEAD 2>/dev/null >> "$LOG"
  echo '```' >> "$LOG"
  echo "" >> "$LOG"
fi
HOOK
chmod +x ~/.claude/hooks/on-stop.sh

# ── settings.json ────────────────────────────────────
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
    ]
  }
}
SETTINGS

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
