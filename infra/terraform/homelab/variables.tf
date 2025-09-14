variable "master" {
  description = "Debian VM IP/hostname for the K3s server"
  type        = string
  default     = "192.168.2.71"
}
variable "ssh_user" {
  description = "SSH user with sudo (NOPASSWD recommended)"
  type        = string
  default     = "tim"
}

variable "ssh_private_key" {
  description = "Path to your private SSH key (on local machine)"
  type        = string
  default     = "~/.ssh/id_ed25519_github"
}

variable "tls_sans" {
  description = "Additional TLS SANs for the API server"
  type        = list(string)
  default     = ["192.168.2.71"]
}

variable "k3s_channel" {
  description = "K3s channel or explicit version (stable, latest, vX.Y.Z+k3sN)"
  type        = string
  default     = "stable"
}
