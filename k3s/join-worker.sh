#!/usr/bin/env bash
set -euo pipefail
MASTER_IP="${1:?Usage: $0 <MASTER_IP> <TOKEN_FILE|TOKEN_STRING>}"
TOKEN="${2:?Usage: $0 <MASTER_IP> <TOKEN_FILE|TOKEN_STRING>}"
[[ -f "$TOKEN" ]] && TOKEN="$(cat "$TOKEN")"
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="${TOKEN}" sh -s - agent
