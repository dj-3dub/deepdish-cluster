locals {
  # Expands "~" to your real home directory on the machine running Terraform
  key_path  = pathexpand(var.ssh_private_key)
  sans_flag = join(" ", [for s in var.tls_sans : "--tls-san ${s}"])
}

# 1) Install K3s server on the Debian VM
resource "null_resource" "install_master" {
  triggers = {
    master      = var.master
    ssh_user    = var.ssh_user
    k3s_channel = var.k3s_channel
    sans_hash   = sha1(local.sans_flag)
  }

  connection {
    type        = "ssh"
    host        = var.master
    user        = var.ssh_user
    private_key = file(local.key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "sudo apt-get update -y",
      "sudo apt-get install -y curl ca-certificates",
      # Uninstall if present (safe to run)
      "if [ -x /usr/local/bin/k3s-uninstall.sh ]; then sudo /usr/local/bin/k3s-uninstall.sh || true; fi",
      # Install K3s server; write kubeconfig world-readable so we can scp it
      "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL=${var.k3s_channel} sh -s - server --write-kubeconfig-mode 644 ${local.sans_flag}",
      # Wait for kubeconfig and API to be ready
      "timeout 180 bash -c 'until [ -f /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done'",
      "sudo /usr/local/bin/kubectl get nodes -o wide || true"
    ]
  }
}

# 2) Pull kubeconfig to local machine and rewrite server IP
resource "null_resource" "pull_kubeconfig" {
  triggers = {
    installed = null_resource.install_master.id
    master    = var.master
    ssh_user  = var.ssh_user
    key_path  = local.key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
scp -o StrictHostKeyChecking=no -i "${local.key_path}" \
  ${var.ssh_user}@${var.master}:/etc/rancher/k3s/k3s.yaml \
  "${path.module}/kubeconfig"

sed -i 's/127.0.0.1/${var.master}/g' "${path.module}/kubeconfig"
chmod 600 "${path.module}/kubeconfig"
echo "KUBECONFIG=${path.module}/kubeconfig"
EOT
  }
}
