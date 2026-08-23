# Claude Code + DeepSeek Router

Proxy de enrutamiento inteligente para [Claude Code CLI](https://github.com/anthropics/claude-code) con modelos DeepSeek (v4-flash / v4-pro). Sin dependencias externas, solo Node.js nativo.

## Cómo funciona

```
claude → proxy (127.0.0.1:3456) → DeepSeek API
                                   ├─ v4-flash (tareas simples)
                                   └─ v4-pro  (thinking / plan mode / contexto largo)
```

El proxy inspecciona cada request y decide el modelo:

| Condición | Modelo |
|---|---|
| Primera llamada (sin uso real aún) | `deepseek-v4-flash` |
| Contexto real < `longContextThreshold` (500K) | `deepseek-v4-flash` |
| Contexto real > `longContextThreshold` (500K) | `deepseek-v4-pro` |
| Plan mode activo (`/plan`) | `deepseek-v4-pro` + `reasoning.effort` |
| Tareas en background | `deepseek-v4-pro` |

### Detalles de comportamiento

- **Contexto real por sesión**: el proxy suma `input + cache_read + cache_creation` del `usage` que devuelve DeepSeek en cada respuesta, y lo guarda por `x-claude-code-session-id`. Así el routing usa el contexto *real* (no estimado) tras la primera respuesta. Al arrancar (sin dato aún) va a `flash`.
- **Thinking solo en plan mode**: con `Router.thinking = "plan"`, el proxy solo activa razonamiento cuando detecta el marcador `"Plan mode is active"` en los últimos mensajes (`reasoning.effort = "high"`). Fuera de plan mode desactiva thinking (`thinking.type = "disabled"`) para que Flash no piense.
- **Umbral real (500K)**: el `longContextThreshold` instalado por defecto es **500.000** tokens (no 60K). Se ajusta con `router-config set Router.longContextThreshold`.

## Requisitos

- **Node.js >= 18**
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview)** instalado
- **DeepSeek API key** — [obtener aquí](https://platform.deepseek.com/api_keys)

## Instalación

```bash
git clone https://github.com/edugithub/claude-deepseek-router.git
cd claude-deepseek-router
bash setup.sh
```

Te pedirá la API key de DeepSeek y configura todo automáticamente (proxy, hooks, variables de shell, status line y skills globales).

## Qué instala

| Archivo | Propósito |
|---|---|
| `~/.claude-code-router/proxy.mjs` | Proxy (~235 líneas, Node nativo) |
| `~/.claude-code-router/proxy.log` | Logs: modelo + tokens por request (escritura directa, sin buffering) |
| `~/.claude-code-router/config.json` | Configuración de providers y routing |
| `~/.claude-code-router/router-config` | CLI para consultar/modificar config.json en vivo |
| `~/.claude-code-router/logs.sh` | Visor de logs del proxy (alias de `logs.sh` en el repo) |
| `~/.claude-code-router/rotate-logs.sh` | Rotación del log vía SIGUSR1 |
| `~/.claude-code-router/last-model/<session-id>` | Último modelo por sesión (para status line) |
| `~/.claude-code-router/last-effort/<session-id>` | Effort real usado por sesión (para status line) |
| `~/.claude-code-router/last-balance` | Saldo de DeepSeek cacheado (consulta automática) |
| `~/.claude/hooks/on-stop.sh` | Hook Stop: registra git diff por rama + metadata de sesión al salir |
| `~/.claude/hooks/on-checkout.sh` | Hook PreToolUse: registra cambios antes de git checkout |
| `~/.claude/hooks/on-session-start.sh` | Hook SessionStart: avisa cambios + sesiones para retomar |
| `~/.claude/statusline.sh` | Status line: rama, contexto, tokens, effort, modelo, balance |
| `~/.claude/settings.json` | Config de Claude Code + hooks + status line |
| `~/.claude/skills/` | Skills globales (coding-workflow, refactoring, debugging) |
| `$PROJECT/.claude/sessions.json` | Metadata de sesiones (id, fecha, rama, título) |
| Variables en `.zshrc`/`.bashrc` | `ANTHROPIC_BASE_URL`, auto-arranque del proxy, `PATH` |

## Uso diario

Abrir terminal y Claude Code normalmente. El proxy arranca solo.

```bash
claude
```

Para ver el routing en vivo:

```bash
bash logs.sh                      # últimas 20 líneas (desde el repo)
bash ~/.claude-code-router/logs.sh  # o desde donde estés
bash logs.sh -f                   # seguir en vivo (tail -f)
bash logs.sh -n 5                 # solo 5 líneas
```

Salida típica:

```
[proxy] >> deepseek-v4-flash | in:1234 out:567 cache:0
[proxy] >> deepseek-v4-pro  | in:8921 out:2341 cache:123
```

Columnas: `modelo | in:tokens_entrada out:tokens_salida cache:tokens_cache_hit`

## Status line

El instalador configura una **status line** en el prompt de Claude Code con la información de la sesión en tiempo real:

```
⎇ main  ▰▰▱▱▱▱▱▱▱▱  19%  ·  15.0k in  3.5k out  ·  -  [deepseek-v4-flash]  ·  $ 5.71
```

| Componente | Descripción |
|---|---|
| `⎇ main` | Rama git actual (con `⊞` si es un worktree) |
| `▰▰▱▱▱▱▱▱▱▱  19%` | Porcentaje de uso de la ventana de contexto + barra visual de 10 bloques |
| `15.0k in  3.5k out` | Tokens totales de entrada/salida en la sesión (formateados a k) |
| `-` | Effort real usado por el proxy (`R:high` en plan mode, `no-thinking` fuera) |
| `[deepseek-v4-flash]` | Modelo real enrutado por el proxy (lee de `last-model/<sid>`) |
| `$ 5.71` | Saldo de DeepSeek en USD (lee de `last-balance`) |

> **Nota:** El modelo que muestra refleja la decisión de routing del proxy en tiempo real (flash para requests simples, pro para plan mode/contexto largo), no el modelo configurado en `ANTHROPIC_MODEL`. El balance se actualiza automáticamente en cada request (consulta gratuita de la API, cacheada en `last-balance`).

## Balance de DeepSeek

El proxy consulta el [endpoint de saldo](https://api-docs.deepseek.com/api/get-user-balance/) de DeepSeek automáticamente:

- Se dispara en **cada request** (cada prompt) en background, sin bloquear el enrutado.
- Es un endpoint **gratuito** (no consume tokens del modelo), por lo que no hay throttling.
- Escribe el resultado a `~/.claude-code-router/last-balance`, que la status line lee localmente (microsegundos, sin red).
- Si falla (p. ej. HTTP 500), escribe una línea `[proxy] balance warn` en el log y **no rompe el proxy**.

## Skills globales

`setup.sh` copia los skills del repo a `~/.claude/skills/`, disponibles en **todos** los proyectos:

| Skill | Propósito |
|---|---|
| `coding-workflow` | Workflow de implementación: clasificación de tarea, cambio mínimo, consistencia multi-fichero, verificación y completion check |
| `refactoring` | Protocolo de refactor que preserva comportamiento |
| `debugging` | Distinguir root cause de síntoma, trazar el path, corregir lo mínimo |

Estos skills **reducen los fallos de proceso** (especialmente en Flash con thinking desactivado y output reducido), pero **no deciden el modelo** — eso lo hace siempre el proxy.

## router-config CLI

`router-config` permite consultar y modificar la configuración del proxy en vivo.

```bash
router-config                              # Mostrar config actual
router-config get Router.think             # Ver modelo para thinking
router-config set Router.think "deepseek,deepseek-v4-pro"  # Cambiarlo
router-config set Router.longContextThreshold 500000       # Umbral de contexto
router-config provider deepseek            # Ver proveedor
router-config provider deepseek --api-base-url https://... --models "flash,pro"
router-config restart                      # Reiniciar el proxy (aplica cambios)
```

### Configuración inicial con flags

`setup.sh` acepta flags para personalizar el routing sin intervención interactiva:

```bash
bash setup.sh \
  --default-model deepseek-v4-flash \
  --think-model deepseek-v4-pro \
  --longcontext-model deepseek-v4-pro \
  --background-model deepseek-v4-pro \
  --provider-url https://api.deepseek.com/anthropic/v1/messages \
  --provider-models "deepseek-v4-flash,deepseek-v4-pro"
```

Sin flags, el instalador pregunta interactivamente los valores (pulsar Enter usa el default).

## Sesiones

Al cerrar Claude Code, el hook Stop guarda metadata de la sesión en `.claude/sessions.json`:

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

Al abrir una nueva sesión en el mismo proyecto, el hook SessionStart muestra las sesiones recientes y Claude Code pregunta si quieres retomar alguna.

```
Sesiones recientes en este proyecto:
  - [2026-05-23 16:30] Fix login button (main)  /resume abc12345
```

Usa `/resume <id>` para retomar una sesión anterior.

## Credenciales

Solo necesitas la **API key de DeepSeek**. Se pide durante la instalación y se guarda como variable de entorno en `~/.zshrc`/`~/.bashrc` (y la usa el proxy desde `DEEPSEEK_API_KEY` en cada request). **Nunca** se escribe en `config.json` ni en archivos del proyecto.

> **Aviso de seguridad:** no uses la key en permisos de `~/.claude/settings.local.json`. Un `PermissionRule` que contenga la key en texto plano la expone en ficheros locales y logs; usa variables de entorno (`DEEPSEEK_API_KEY`) en su lugar. Si ya está ahí, rótala.

## Portar a otra máquina

```bash
git clone https://github.com/edugithub/claude-deepseek-router.git
cd claude-deepseek-router && bash setup.sh
```

## Licencia

Dominio público. Sin restricciones.
