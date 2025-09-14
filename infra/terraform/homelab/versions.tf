terraform {
  required_version = ">= 1.5.0"
  required_providers {
    null  = { source = "hashicorp/null", version = "~> 3.2" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}
