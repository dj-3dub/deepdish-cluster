output "kubeconfig" { value = "${path.module}/kubeconfig" }
output "api_server" { value = "https://${var.master}:6443" }
