#!/bin/bash
# Muestra los logs del proxy en vivo (routing + tokens)

case "${1:-}" in
  -f|--follow) tail -f ~/.claude-code-router/proxy.log ;;
  -n)          tail -"${2:-20}" ~/.claude-code-router/proxy.log ;;
  --help|-h)
    echo "Uso: bash logs.sh [-f] [-n N]"
    echo "  sin flags   últimas 20 líneas"
    echo "  -f          seguir en vivo (tail -f)"
    echo "  -n N        mostrar N líneas"
    ;;
  *)           tail -20 ~/.claude-code-router/proxy.log ;;
esac
