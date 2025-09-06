#!/usr/bin/env bash
set -euo pipefail
curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644
sudo kubectl get nodes
echo "==== K3s node token ===="
sudo cat /var/lib/rancher/k3s/server/node-token
