#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$DIR/.env"
TEMPLATE="$DIR/prod.yml.template"
PROD_YML="$DIR/prod.yml"

if [[ -e "$ENV_FILE" || -e "$PROD_YML" ]]; then
  echo "ERROR: '.env' oder 'prod.yml' existieren bereits in '$DIR'. Vor Neugenerierung sichern oder loeschen." >&2
  exit 1
fi

rand_hex() {
  local bytes="${1:-24}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  else
    od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
  fi
}

SERVER_KEY="${SOCKET_SERVER_KEY:-shadowspore_live_client_v1}"
if [[ "${1:-}" == "--random-server-key" ]]; then
  SERVER_KEY="ssp_live_$(rand_hex 18)"
elif [[ -n "${1:-}" ]]; then
  SERVER_KEY="$1"
fi

if [[ -z "$SERVER_KEY" || "$SERVER_KEY" =~ [\|\\\&] ]]; then
  echo "ERROR: Ungueltiger SERVER_KEY." >&2
  exit 1
fi

PG_PASS="$(rand_hex 24)"
SESS_KEY="$(rand_hex 32)"
REFRESH_KEY="$(rand_hex 32)"
CONSOLE_PASS="$(rand_hex 20)"
HTTP_KEY="$(rand_hex 24)"

ARCH="$(uname -m)"
NAKAMA_TAG="3.24.2"
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  NAKAMA_TAG="3.24.2-arm"
fi

printf 'POSTGRES_PASSWORD=%s\nNAKAMA_TAG=%s\n' "$PG_PASS" "$NAKAMA_TAG" > "$ENV_FILE"
chmod 600 "$ENV_FILE"

sed \
  -e "s|__SESSION_ENCRYPTION_KEY__|$SESS_KEY|g" \
  -e "s|__REFRESH_ENCRYPTION_KEY__|$REFRESH_KEY|g" \
  -e "s|__SOCKET_SERVER_KEY__|$SERVER_KEY|g" \
  -e "s|__CONSOLE_PASSWORD__|$CONSOLE_PASS|g" \
  -e "s|__RUNTIME_HTTP_KEY__|$HTTP_KEY|g" \
  "$TEMPLATE" > "$PROD_YML"
chmod 600 "$PROD_YML"

echo "Produktions-Secrets erzeugt:"
echo "  - $ENV_FILE"
echo "  - $PROD_YML"
echo "  socket.server_key = $SERVER_KEY"
if [[ "$SERVER_KEY" != "shadowspore_live_client_v1" ]]; then
  echo "HINWEIS: Release-Build mit -ServerKey \"$SERVER_KEY\" bauen!"
fi
