# Claude Code + DeepSeek Router

## Proyecto

Proxy de enrutamiento inteligente para Claude Code CLI con modelos DeepSeek (v4-flash / v4-pro). Sin dependencias externas, solo Node.js nativo.

- Proxy: `~/.claude-code-router/proxy.mjs` (~50 líneas, Node nativo HTTP)
- Setup: `setup.sh` — instalación interactiva (pide API key, configura hooks, variables de entorno)
- Logs: `logs.sh` — wrapper de tail para `~/.claude-code-router/proxy.log`

## Routing

| Condición | Modelo |
|---|---|
| Condición | Modelo |
|---|---|
| Sin thinking, contexto < 30K tokens, foreground | `deepseek-v4-flash` |
| Thinking activado o contexto > 30K tokens | `deepseek-v4-pro` |
| Background | `deepseek-v4-pro` |

## Convenciones

- **Idioma**: README y mensajes al usuario en español
- **Sin dependencias externas**: Solo Node.js nativo (http, fetch)
- **Hooks**: Los hooks se instalan en `~/.claude/hooks/` con `setup.sh`
  - `on-stop.sh` — registra git diff + guarda metadata de sesión al cerrar
  - `on-checkout.sh` — registra cambios antes de git checkout
  - `on-session-start.sh` — avisa cambios pendientes + ofrece retomar sesiones
- **Change log**: `.claude-change-log.md` en raíz del proyecto
- **Sesiones**: `.claude/sessions.json` — historial de sesiones (últimas 20)

## Archivos clave

| Archivo | Propósito |
|---|---|
| `setup.sh` | Instalador completo (proxy, hooks, variables de shell) |
| `logs.sh` | Visor de logs del proxy |
| `README.md` | Documentación del proyecto |
| `.gitignore` | Ignora `node_modules/` y `.claude/` |
| `.claude/sessions.json` | Metadata de sesiones anteriores |
| `.claude-change-log.md` | Registro de cambios entre sesiones |
| `~/.claude-code-router/logs.sh` | Visor de logs del proxy |
| `~/.claude-code-router/rotate-logs.sh` | Rotacion del log del proxy sin reiniciar |

## Rotacion de logs

El proxy escribe logs en `~/.claude-code-router/proxy.log` con escritura directa (sin buffering). Para rotar el log sin reiniciar el proxy:

```bash
bash ~/.claude-code-router/rotate-logs.sh
# log rotado: proxy.log -> proxy.log.20260523-183000
```

El script mueve el log actual y envia `SIGUSR1` al proxy para que abra un archivo nuevo. La ruta del log se configura via `PROXY_LOG_PATH` (default: `~/.claude-code-router/proxy.log`).

## Flujo de trabajo

1. `setup.sh` configura todo (API key, proxy, hooks, variables de entorno)
2. El proxy arranca automáticamente al abrir terminal
3. Claude Code se conecta al proxy via `ANTHROPIC_BASE_URL=http://127.0.0.1:3456`
4. Al cerrar, `on-stop.sh` guarda metadata de sesión
5. Al abrir, `on-session-start.sh` ofrece retomar sesiones previas
