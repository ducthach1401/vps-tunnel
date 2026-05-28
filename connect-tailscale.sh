#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo ./connect-tailscale.sh <HEADSCALE_URL> <AUTH_KEY> [HOSTNAME]
# Example:
#   sudo ./connect-tailscale.sh https://headscale.example.com tskey-client-xxxxx my-laptop

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ ${EUID} -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

HEADSCALE_URL="${1:-${HEADSCALE_URL:-}}"
AUTH_KEY="${2:-}"
CUSTOM_HOSTNAME="${3:-}"

if [[ -z "$HEADSCALE_URL" || -z "$AUTH_KEY" ]]; then
  echo "Usage: sudo $0 [HEADSCALE_URL] <AUTH_KEY> [HOSTNAME]"
  echo "Or set HEADSCALE_URL in .env"
  exit 1
fi

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale is already installed"
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install tailscale
  elif command -v yum >/dev/null 2>&1; then
    yum -y install tailscale
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm tailscale
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install tailscale
  else
    echo "Unsupported package manager. Install tailscale manually first."
    exit 1
  fi
}

start_tailscaled() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now tailscaled
  else
    echo "systemd not found. Please start tailscaled manually."
    exit 1
  fi
}

connect_tailscale() {
  local -a up_cmd
  up_cmd=(tailscale up --login-server "$HEADSCALE_URL" --authkey "$AUTH_KEY" --accept-routes)

  if [[ -n "$CUSTOM_HOSTNAME" ]]; then
    up_cmd+=(--hostname "$CUSTOM_HOSTNAME")
  fi

  "${up_cmd[@]}"
}

install_tailscale
start_tailscaled
connect_tailscale

echo
printf "Connected. Current status:\n"
tailscale status
