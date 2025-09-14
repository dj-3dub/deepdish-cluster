#!/usr/bin/env bash
# Preflight checks for deepdish-cluster Terraform K3s install
# - Validates Terraform config
# - Verifies SSH connectivity and sudo
# - Checks remote OS prereqs, disk, ports, and potential conflicts
#
# Usage (from repo root or any dir):
#   ./infra/terraform/homelab/preflight.sh
#
# Optional env overrides:
#   TF_DIR=infra/terraform/homelab MASTER=192.168.2.71 SSH_USER=tim SSH_KEY=~/.ssh/id_ed25519

set -euo pipefail

# -------- configurable defaults --------
TF_DIR="${TF_DIR:-infra/terraform/homelab}"
MASTER="${MASTER:-192.168.2.71}"
SSH_USER="${SSH_USER:-tim}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_ed25519}"
SSH_PORT="${SSH_PORT:-22}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=8 -P ${SSH_PORT} -i $(eval echo ${SSH_KEY})"

# -------- helpers --------
ok()   { printf "✅ %s\n" "$*"; }
bad()  { printf "❌ %s\n" "$*" >&2; }
warn() { printf "⚠️  %s\n" "$*"; }

run()  { echo "+ $*" ; eval "$@"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { bad "Missing required command: $1" ; exit 1; }
}

require_file() {
  [ -f "$1" ] || { bad "Missing file: $1"; exit 1; }
}

# -------- local checks --------
need_cmd terraform
need_cmd ssh
need_cmd scp
need_cmd sed

echo "=== Preflight: local checks ==="
require_file "${TF_DIR}/versions.tf"
require_file "${TF_DIR}/variables.tf"
require_file "${TF_DIR}/main.tf"

# Optional but nice
[ -f "${TF_DIR}/outputs.tf" ] && ok "outputs.tf present" || warn "outputs.tf not found (optional but recommended)"

# Terraform version
TFV=$(terraform version | head -n1 | awk '{print $2}')
ok "Terraform ${TFV} detected"

# fmt / validate
run "terraform -chdir=${TF_DIR} fmt -check"
ok "terraform fmt -check passed"

run "terraform -chdir=${TF_DIR} init -upgrade -input=false"
ok "terraform init completed"

run "terraform -chdir=${TF_DIR} validate"
ok "terraform validate passed"

# tflint (optional)
if command -v tflint >/dev/null 2>&1; then
  run "tflint --chdir ${TF_DIR}"
  ok "tflint passed"
else
  warn "tflint not installed (optional). Install: curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash"
fi

# Read defaults from variables.tf (best effort)
DEF_MASTER=$(awk -F'"' '/variable "master"/{f=1} f && /default/{print $2; f=0}' "${TF_DIR}/variables.tf" 2>/dev/null || true)
[ -n "${DEF_MASTER}" ] && warn "variables.tf default master=${DEF_MASTER} (override with MASTER=${MASTER} if different)"

# -------- SSH checks --------
echo "=== Preflight: SSH to ${SSH_USER}@${MASTER}:${SSH_PORT} ==="
KEY_EXPANDED=$(eval echo ${SSH_KEY})
[ -f "${KEY_EXPANDED}" ] || { bad "SSH key not found: ${KEY_EXPANDED} (set SSH_KEY=...)" ; exit 1; }
ok "Found SSH key: ${KEY_EXPANDED}"

# Fingerprint + connection
run "ssh ${SSH_OPTS} ${SSH_USER}@${MASTER} 'echo ok'"
ok "SSH connectivity OK"

# Passwordless sudo?
if ssh ${SSH_OPTS} ${SSH_USER}@${MASTER} 'sudo -n true' 2>/dev/null; then
  ok "Passwordless sudo available"
else
  bad "Passwordless sudo not available for ${SSH_USER}. Either enable NOPASSWD or tell me and I’ll patch Terraform to use sudo -S."
  exit 1
fi

# -------- remote environment checks --------
echo "=== Preflight: remote host sanity ==="
# OS and basics
ssh ${SSH_OPTS} ${SSH_USER}@${MASTER} '
  set -e
  echo "Remote uname: $(uname -a)"
  if command -v apt >/dev/null 2>&1; then
    echo "APT-based system detected"
    need=()
    for pkg in curl ca-certificates; do
      dpkg -s "$pkg" >/dev/null 2>&1 || need+=("$pkg")
    done
    if [ "${#need[@]}" -gt 0 ]; then
      echo "Installing missing deps: ${need[*]}"
      sudo apt-get update -y && sudo apt-get install -y "${need[@]}"
    else
      echo "Required packages already present"
    fi
  else
    echo "Non-APT system; ensure curl + CA certs are installed"
  fi

  # Disk space check (>= 1GB free)
  FREE=$(df -Pm / | awk "NR==2 {print \$4}")
  echo "Free space on / : ${FREE} MB"
  if [ "$FREE" -lt 1024 ]; then
    echo "LOW DISK SPACE: <1GB free on /" ; exit 12
  fi

  # Port 6443 free?
  if command -v ss >/dev/null 2>&1; then
    INUSE=$(ss -lnt | awk '\''$1=="LISTEN" && $4 ~ /:6443$/ {print $4}'\'')
  else
    INUSE=$(netstat -lnt 2>/dev/null | awk '\''$6=="LISTEN" && $4 ~ /:6443$/ {print $4}'\'')
  fi
  if [ -n "$INUSE" ]; then
    echo "Port 6443 appears in use: $INUSE" ; exit 13
  else
    echo "Port 6443 free"
  fi

  # Existing k3s?
  if [ -x /usr/local/bin/k3s-uninstall.sh ] || systemctl list-units --type=service | grep -q k3s; then
    echo "K3s appears installed already"
    echo "Node token (if present):"
    sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || true
    exit 14
  fi

  # Can we write kubeconfig path and read it later?
  test -d /etc/rancher || sudo mkdir -p /etc/rancher
  sudo test -w /etc/rancher || sudo chown '"${SSH_USER}"':'"${SSH_USER}"' /etc/rancher || true
  echo "Remote write check OK"
' || {
  rc=$?
  case $rc in
    12) bad "Remote disk space < 1GB. Free up space on ${MASTER} and retry." ;;
    13) bad "TCP 6443 already in use on ${MASTER}. Stop whatever is using it (old k3s/another API) and retry." ;;
    14) bad "K3s appears already installed. Uninstall it first: sudo /usr/local/bin/k3s-uninstall.sh" ;;
    *)  bad "Remote sanity checks failed (rc=$rc). See output above." ;;
  esac
  exit 1
}
ok "Remote host sanity OK"

# -------- scp test path (simulated) --------
echo "=== Preflight: scp sanity ==="
TMPTEST="/tmp/preflight_k3s_$$"
ssh ${SSH_OPTS} ${SSH_USER}@${MASTER} "echo test > ${TMPTEST}"
LOCAL_TMP="$(mktemp)"
run "scp ${SSH_OPTS} ${SSH_USER}@${MASTER}:${TMPTEST} ${LOCAL_TMP}"
diff -u <(echo test) "${LOCAL_TMP}" >/dev/null && ok "scp works from remote → local" || { bad "scp content mismatch"; exit 1; }
rm -f "${LOCAL_TMP}"
ssh ${SSH_OPTS} ${SSH_USER}@${MASTER} "rm -f ${TMPTEST}"

echo "========================================="
ok "Preflight checks passed. Safe to run: terraform -chdir=${TF_DIR} apply -auto-approve"
