# Claude Code + DeepSeek Router

Proxy de enrutamiento inteligente para [Claude Code CLI](https://github.com/anthropics/claude-code) con modelos DeepSeek. Sin dependencias externas, solo Node.js nativo.

## Cómo funciona

```
claude → proxy (127.0.0.1:3456) → DeepSeek API
                                   ├─ v4-flash (tareas simples)
                                   └─ v4-pro  (thinking / contexto largo)
```

El proxy inspecciona cada request y decide:

| Condición | Modelo |
|---|---|
| Sin thinking, contexto < 60K tokens | `deepseek-v4-flash` |
| Thinking activado (`/effort high`+) | `deepseek-v4-pro` |
| Conversación > 60K tokens | `deepseek-v4-pro` |

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

Te pedirá la API key de DeepSeek y configura todo automáticamente.

## Qué instala

| Archivo | Propósito |
|---|---|
| `~/.claude-code-router/proxy.mjs` | Proxy (~50 líneas, Node nativo) |
| `~/.claude-code-router/proxy.log` | Logs: modelo + tokens por request |
| `~/.claude/hooks/on-stop.sh` | Hook Stop: registra git diff por rama al salir |
| `~/.claude/hooks/on-checkout.sh` | Hook PreToolUse: registra cambios antes de git checkout |
| `~/.claude/hooks/on-session-start.sh` | Hook SessionStart: avisa cambios + sesiones para retomar |
| `~/.claude/settings.json` | Config de Claude Code + 3 hooks |
| `$PROJECT/.claude/sessions.json` | Metadata de sesiones (id, fecha, rama, titulo) |
| `~/.claude-code-router/logs.sh` | Visor de logs del proxy (alias de `logs.sh` en el repo) |
| `~/.claude-code-router/config.json` | Configuración de providers y routing |
| `~/.claude-code-router/router-config` | CLI para consultar/modificar config.json |
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
[proxy] → deepseek-v4-flash | in:1234 out:567 cache:0
[proxy] → deepseek-v4-pro  | in:8921 out:2341 cache:123
```

Columnas: `modelo | in:tokens_entrada out:tokens_salida cache:tokens_cache_hit`

## router-config CLI

`router-config` permite consultar y modificar la configuración del proxy en vivo.

```bash
router-config                              # Mostrar config actual
router-config get Router.think             # Ver modelo para thinking
router-config set Router.think "deepseek,deepseek-v4-pro"  # Cambiarlo
router-config set Router.longContextThreshold 80000         # Umbral de contexto
router-config provider deepseek            # Ver proveedor
router-config provider deepseek --api-base-url https://... --models "flash,pro"
```

### Configuración inicial con flags

`setup.sh` acepta flags para personalizar el routing sin intervención interactiva:

```bash
bash setup.sh \
  --default-model deepseek-v4-flash \
  --think-model deepseek-v4-pro \
  --longcontext-model deepseek-v4-pro \
  --background-model deepseek-v4-flash \
  --provider-url https://api.deepseek.com/anthropic/v1/messages \
  --provider-models "deepseek-v4-flash,deepseek-v4-pro"
```

Sin flags, el instalador pregunta interactivamente los valores (pulsar Enter usa el default).

## Sesiones

Al cerrar Claude Code, el hook Stop guarda metadata de la sesion en `.claude/sessions.json`:

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

Al abrir una nueva sesion en el mismo proyecto, el hook SessionStart muestra las sesiones recientes y Claude Code pregunta si quieres retomar alguna.

```
Sesiones recientes en este proyecto:
  - [2026-05-23 16:30] Fix login button (main)  /resume abc12345
```

Usa `/resume <id>` para retomar una sesion anterior.

## Credenciales

Solo necesitas la **API key de DeepSeek**. Se pide durante la instalación y se guarda como variable de entorno en `~/.zshrc`/`~/.bashrc`. Nunca se guarda en `config.json` ni en archivos del proyecto.

## Portar a otra máquina

```bash
git clone https://github.com/edugithub/claude-deepseek-router.git
cd claude-deepseek-router && bash setup.sh
```

## Licencia

Dominio público. Sin restricciones.
