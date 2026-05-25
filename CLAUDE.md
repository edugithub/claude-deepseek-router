# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Claude Code + DeepSeek Router

## Proyecto

Proxy de enrutamiento inteligente para Claude Code CLI con modelos DeepSeek (v4-flash / v4-pro). Sin dependencias externas, solo Node.js nativo.

- **Proxy**: `~/.claude-code-router/proxy.mjs` (~120 líneas, Node nativo HTTP)
- **Config**: `~/.claude-code-router/config.json` — routing, providers, umbrales
- **Setup**: `setup.sh` — instalación interactiva
- **router-config** — CLI para consultar/modificar config en vivo

## Arquitectura

```
Claude Code CLI → proxy.mjs (127.0.0.1:3456) → DeepSeek API
                      │
                      ├─ decide modelo según request (thinking, tamaño contexto)
                      ├─ loggea modelo + tokens por request
                      └─ lee config.json (recargado en cada request)
```

El proxy se inyecta via `ANTHROPIC_BASE_URL=http://127.0.0.1:3456` y arranca automáticamente al abrir terminal (linea en `.zshrc`/`.bashrc`).

El codigo del proxy se genera desde `setup.sh` (here-doc), no hay un archivo independiente en el repo.

## Routing

| Condición | Modelo |
|---|---|
| Sin thinking, contexto < threshold | `deepseek-v4-flash` |
| Thinking activado (`thinking.type = "enabled"`) | `deepseek-v4-pro` |
| Contexto > threshold (`longContextThreshold`, default 30K) | `deepseek-v4-pro` |
| Background | `deepseek-v4-pro` |

El threshold se configura en `config.json` via `Router.longContextThreshold`. El README dice 60K como documentación pública; el valor real instalado por `setup.sh` es 30K.

## Convenciones

- **Idioma**: README y mensajes al usuario en español
- **Sin dependencias externas**: Solo Node.js nativo (http, fetch, fs, os, path)
- **Hooks**: Se instalan en `~/.claude/hooks/` con `setup.sh`
  - `on-stop.sh` — registra git diff + guarda metadata de sesión al cerrar
  - `on-checkout.sh` — registra cambios antes de git checkout
  - `on-session-start.sh` — avisa cambios pendientes + ofrece retomar sesiones
- **Change log**: `.claude-change-log.md` — diff log de cambios entre sesiones. Solo registra cambios en archivos del proyecto (excluye cambios al propio `.claude-change-log.md`)
- **Sesiones**: `.claude/sessions.json` — historial de sesiones (últimas 20)
- **Logs del proxy**: `~/.claude-code-router/proxy.log` — escritura directa con `fs.writeSync` (sin buffering)
- **Status line**: Muestra modelo, directorio, tokens totales (in/out), % de contexto con barra visual y nivel de esfuerzo

## Comandos comunes

```bash
# Ver enrutamiento en vivo
bash logs.sh              # últimas 20 líneas
bash logs.sh -f           # seguir en vivo (tail -f)
bash logs.sh -n 5         # solo 5 líneas

# Ver/configurar routing
router-config                           # mostrar config completa
router-config get Router.think          # modelo para thinking
router-config set Router.longContextThreshold 80000
router-config provider deepseek         # ver proveedor
router-config provider deepseek --api-base-url https://...

# Rotar log del proxy sin reiniciar
bash ~/.claude-code-router/rotate-logs.sh

# Retomar sesión anterior
/resume <session-id>

# Revisar cambios pendientes y actualizar CLAUDE.md
cat .claude-change-log.md
```

## Archivos clave

| Archivo | Propósito |
|---|---|
| `setup.sh` | Instalador completo (proxy, hooks, variables de shell, statusline) |
| `logs.sh` | Visor de logs del proxy |
| `README.md` | Documentación pública del proyecto |
| `.gitignore` | Ignora `node_modules/`, logs, change log, sesiones |
| `CLAUDE.md` | Este archivo — guía de trabajo |
| `.claude-change-log.md` | Registro de cambios entre sesiones |
| `.claude/sessions.json` | Metadata de sesiones anteriores (id, fecha, rama, título) |
| `~/.claude-code-router/proxy.mjs` | Proxy runtime (generado por setup.sh) |
| `~/.claude-code-router/config.json` | Config en JSON: providers, routing, umbrales |
| `~/.claude-code-router/router-config` | CLI para gestionar config (Node.js script, generado por setup.sh) |
| `~/.claude-code-router/logs.sh` | Visor de logs (copiado desde el repo) |
| `~/.claude-code-router/rotate-logs.sh` | Rotación de log via SIGUSR1 |
| `~/.claude/statusline.sh` | Status line en prompt (modelo, tokens, %contexto, esfuerzo) |
| `~/.claude/settings.json` | Config de Claude Code (hooks, statusLine) |

## Flujo de trabajo

1. `bash setup.sh` configura todo (API key, proxy, hooks, variables de entorno, statusline)
2. El proxy arranca automáticamente al abrir terminal (o se puede iniciar manualmente)
3. Claude Code se conecta al proxy via `ANTHROPIC_BASE_URL=http://127.0.0.1:3456`
4. Al cerrar, `on-stop.sh` guarda metadata de sesión en `.claude/sessions.json`
5. Al abrir, `on-session-start.sh` revisa `.claude-change-log.md` y ofrece retomar sesiones

## Detalles técnicos del proxy

- **Re-escritura de modelo**: Inspecciona el body del request y sobreescribe `body.model` según las reglas de `config.json`
- **Streaming**: Reenvía SSE (text/event-stream) leyendo con `getReader()`, parsea eventos para extraer token usage
- **Timeout**: Configurable via `config.json` → `API_TIMEOUT_MS` (default 600s)
- **Logging**: Escribe con `fs.writeSync` (sin buffering), rotación via `SIGUSR1`
- **Config**: Carga `config.json` en cada request (no cachea), modificable en vivo con `router-config` y `router-config restart`
- **Provider routing**: Busca el provider que contiene el modelo seleccionado; soporta múltiples providers
