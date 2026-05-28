#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./create-headscale-user-key.sh <HEADSCALE_URL> <USERNAME> [EXPIRATION]
# Example:
#   ./create-headscale-user-key.sh https://headscale.example.com main 24h

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

HEADSCALE_URL="${1:-${HEADSCALE_URL:-}}"
USERNAME="${2:-${HEADSCALE_USER:-}}"
EXPIRATION="${3:-${HEADSCALE_KEY_EXPIRATION:-24h}}"
SECRET_FILE="${SECRET_FILE:-key.txt}"

if [[ -z "$HEADSCALE_URL" || -z "$USERNAME" ]]; then
  echo "Usage: $0 [HEADSCALE_URL] [USERNAME] [EXPIRATION]" >&2
  echo "Or set HEADSCALE_URL and HEADSCALE_USER in .env" >&2
  exit 1
fi

detect_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    echo "docker-compose not found" >&2
    exit 1
  fi
}

compose_headscale() {
  "${COMPOSE_CMD[@]}" exec -T headscale headscale "$@"
}

ensure_headscale_running() {
  local container_id
  container_id="$("${COMPOSE_CMD[@]}" ps -q headscale 2>/dev/null || true)"

  if [[ -z "$container_id" ]]; then
    echo "Starting headscale container..." >&2
    "${COMPOSE_CMD[@]}" up -d headscale >/dev/null
  fi
}

ensure_user_exists() {
  if compose_headscale users list -o json 2>/dev/null | tr -d '[:space:]' | grep -q "\"name\":\"$USERNAME\""; then
    return
  fi

  echo "Creating user '$USERNAME'..." >&2
  compose_headscale users create "$USERNAME" >/dev/null
}

get_user_id() {
  local users_json
  local compact_json
  local id

  users_json="$(compose_headscale users list -o json)"
  compact_json="$(printf '%s' "$users_json" | tr -d '[:space:]')"
  id="$(printf '%s' "$compact_json" | sed -n "s/.*{\"id\":\([0-9][0-9]*\),\"name\":\"$USERNAME\".*/\1/p")"

  if [[ -z "$id" ]]; then
    echo "Failed to resolve user id for '$USERNAME'" >&2
    exit 1
  fi

  USER_ID="$id"
}

create_auth_key() {
  local json_output
  local key

  json_output="$(compose_headscale preauthkeys create --user "$USER_ID" --reusable --expiration "$EXPIRATION" -o json)"

  key="$(printf '%s' "$json_output" | tr -d '\n' | sed -n 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

  if [[ -z "$key" ]]; then
    key="$(printf '%s' "$json_output" | tr -d '\n' | sed -n 's/.*"Key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  fi

  if [[ -z "$key" ]]; then
    echo "Failed to parse auth key from headscale output" >&2
    exit 1
  fi

  AUTH_KEY="$key"
}

save_auth_key() {
  local generated_at

  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$SECRET_FILE")"

  cat >"$SECRET_FILE" <<EOF
HEADSCALE_URL="$HEADSCALE_URL"
HEADSCALE_USERNAME="$USERNAME"
HEADSCALE_AUTH_KEY="$AUTH_KEY"
HEADSCALE_EXPIRATION="$EXPIRATION"
GENERATED_AT="$generated_at"
EOF

  chmod 600 "$SECRET_FILE"
}

main() {
  detect_compose
  ensure_headscale_running
  ensure_user_exists
  get_user_id
  create_auth_key
  save_auth_key

  # Print a single line command for client side connection.
  printf 'sudo ./connect-tailscale.sh "%s" "%s" <client-hostname>\n' "$HEADSCALE_URL" "$AUTH_KEY"
}

main
