#!/usr/bin/env bash
set -euo pipefail

ROOT="infrastructure-as-code-terraform"

echo "=> Creating folders..."
mkdir -p "$ROOT"/infra/envs/homelab/caddy
mkdir -p "$ROOT"/docs "$ROOT"/decisions

echo "=> Writing .gitignore..."
cat > "$ROOT/.gitignore" <<'GIT'
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
*.lock.hcl

# Local files
infra/envs/homelab/caddy/Caddyfile
GIT

echo "=> Writing Makefile..."
cat > "$ROOT/Makefile" <<'MK'
.PHONY: init plan apply destroy fmt validate diagram

init:
	cd infra/envs/homelab && terraform init

plan:
	cd infra/envs/homelab && terraform plan

apply:
	cd infra/envs/homelab && terraform apply -auto-approve

destroy:
	cd infra/envs/homelab && terraform destroy -auto-approve

fmt:
	terraform fmt -recursive

validate:
	cd infra/envs/homelab && terraform validate

diagram:
	dot -Tpng docs/architecture.dot -o docs/architecture.png && dot -Tsvg docs/architecture.dot -o docs/architecture.svg
MK

echo "=> Writing Graphviz diagram..."
cat > "$ROOT/docs/architecture.dot" <<'DOT'
digraph PizzaStack {
  rankdir=LR;
  node [shape=box, style=rounded];

  Users [shape=oval, label="Users"];
  Caddy [label="Caddy Reverse Proxy\n(oven.pizza)"];
  API [label="pizza-api\n(api.pizza)"];
  Kuma [label="Uptime-Kuma\n(status.pizza)"];
  DB [label="PostgreSQL\n(toppings)"];

  subgraph cluster_net {
    label="docker network: pizza_net";
    style=dashed;
    Caddy; API; Kuma; DB;
  }

  Users -> Caddy [label="HTTP(S)"];
  Caddy -> API [label="reverse_proxy"];
  Caddy -> Kuma [label="reverse_proxy"];
  API -> DB [label="5432"];
}
DOT

echo "=> Writing providers.tf (docker + pihole)..."
cat > "$ROOT/infra/envs/homelab/providers.tf" <<'TF'
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    pihole = {
      source  = "ryanwholey/pihole"
      version = ">= 1.0.0"
    }
  }
}

provider "docker" {}

# Recommended: configure Pi-hole via environment variables
#   export PIHOLE_URL="http://192.168.2.51"
#   export PIHOLE_PASSWORD="your-admin-password"
provider "pihole" {}
TF

echo "=> Writing variables.tf..."
cat > "$ROOT/infra/envs/homelab/variables.tf" <<'TF'
variable "pizza_domain" {
  type    = string
  default = "pizza"
}

variable "vm_host_ip" {
  type    = string
  default = "192.168.2.71"
}

variable "postgres_user" {
  type    = string
  default = "pizza"
}

variable "postgres_db" {
  type    = string
  default = "toppings"
}

variable "caddy_http_port" {
  type    = number
  default = 80
}

variable "caddy_https_port" {
  type    = number
  default = 443
}
TF

echo "=> Writing outputs.tf..."
cat > "$ROOT/infra/envs/homelab/outputs.tf" <<'TF'
output "pizza_endpoints" {
  value = {
    oven   = "http://oven.${var.pizza_domain}"
    api    = "http://api.${var.pizza_domain}"
    status = "http://status.${var.pizza_domain}"
  }
}
TF

echo "=> Writing main.tf..."
cat > "$ROOT/infra/envs/homelab/main.tf" <<'TF'
# Network
resource "docker_network" "pizza_net" {
  name = "pizza_net"
}

# Volumes
resource "docker_volume" "pg_data"    { name = "pizza_pg_data" }
resource "docker_volume" "kuma_data"  { name = "pizza_kuma_data" }
resource "docker_volume" "caddy_data" { name = "caddy_data" }
resource "docker_volume" "caddy_cfg"  { name = "caddy_config" }

# Secrets
resource "random_password" "postgres_password" {
  length  = 16
  special = false
}

# Postgres (toppings)
resource "docker_container" "postgres" {
  name    = "toppings-db"
  image   = "postgres:16"
  restart = "unless-stopped"

  networks_advanced { name = docker_network.pizza_net.name }

  mounts {
    target = "/var/lib/postgresql/data"
    source = docker_volume.pg_data.name
    type   = "volume"
  }

  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${random_password.postgres_password.result}",
    "POSTGRES_DB=${var.postgres_db}",
    "PGDATA=/var/lib/postgresql/data/pgdata"
  ]
}

# Pizza API (placeholder – swap to your image later)
resource "docker_container" "pizza_api" {
  name    = "pizza-api"
  image   = "nginxdemos/hello" # or ghcr.io/dj-3dub/pizza-api:latest when ready
  restart = "unless-stopped"

  depends_on = [docker_container.postgres]
  networks_advanced { name = docker_network.pizza_net.name }
}

# Uptime-Kuma
resource "docker_container" "uptime_kuma" {
  name    = "uptime-kuma"
  image   = "louislam/uptime-kuma:1"
  restart = "unless-stopped"

  networks_advanced { name = docker_network.pizza_net.name }

  mounts {
    target = "/app/data"
    source = docker_volume.kuma_data.name
    type   = "volume"
  }
}

# Render Caddyfile from template
data "template_file" "caddyfile" {
  template = file("${path.module}/caddy/Caddyfile.tmpl")
  vars = {
    oven_host   = "oven.${var.pizza_domain}"
    api_host    = "api.${var.pizza_domain}"
    status_host = "status.${var.pizza_domain}"
  }
}

resource "local_file" "caddyfile" {
  content  = data.template_file.caddyfile.rendered
  filename = "${path.module}/caddy/Caddyfile"
}

# Caddy reverse proxy (the Oven)
resource "docker_container" "caddy" {
  name    = "caddy-oven"
  image   = "caddy:2.8"
  restart = "unless-stopped"

  networks_advanced { name = docker_network.pizza_net.name }

  # Expose HTTP/HTTPS on the VM (adjust if ports already in use)
  ports {
    internal = 80
    external = var.caddy_http_port
  }
  ports {
    internal = 443
    external = var.caddy_https_port
  }

  # Mount config and data
  mounts {
    type   = "bind"
    target = "/etc/caddy/Caddyfile"
    source = "${path.module}/caddy/Caddyfile"
  }

  mounts {
    type   = "volume"
    target = "/data"
    source = docker_volume.caddy_data.name
  }

  mounts {
    type   = "volume"
    target = "/config"
    source = docker_volume.caddy_cfg.name
  }
}
TF

echo "=> Writing caddy/Caddyfile.tmpl..."
cat > "$ROOT/infra/envs/homelab/caddy/Caddyfile.tmpl" <<'CADDY'
# Oven landing
{{.oven_host}} {
  respond "🍕 Oven is hot! (Caddy running)" 200
}

# API
{{.api_host}} {
  reverse_proxy pizza-api:80
}

# Status
{{.status_host}} {
  reverse_proxy uptime-kuma:3001
}
CADDY

echo "=> Writing pihole.tf (DNS records)..."
cat > "$ROOT/infra/envs/homelab/pihole.tf" <<'TF'
# A records -> Debian VM 192.168.2.71
resource "pihole_dns_record" "oven" {
  domain = "oven.${var.pizza_domain}"
  ip     = var.vm_host_ip
}

resource "pihole_dns_record" "api" {
  domain = "api.${var.pizza_domain}"
  ip     = var.vm_host_ip
}

resource "pihole_dns_record" "status" {
  domain = "status.${var.pizza_domain}"
  ip     = var.vm_host_ip
}

# Optional CNAME (if provider version supports it). Otherwise, create another A record.
# resource "pihole_cname_record" "menu_alias" {
#   domain = "menu.${var.pizza_domain}"
#   target = "status.${var.pizza_domain}"
# }
TF

echo "=> Writing README.md..."
cat > "$ROOT/README.md" <<'MD'
# 🍕 Pizza IaC (Terraform + Docker, Debian Homelab)

Services:
- Oven (Caddy)      → http://oven.pizza
- API (demo)        → http://api.pizza
- Status (Kuma)     → http://status.pizza
- DB (PostgreSQL)   → toppings

## DNS via Pi-hole (Terraform-managed)
Exports to Pi-hole (using provider ryanwholey/pihole):
- A: oven.pizza, api.pizza, status.pizza → 192.168.2.71

## Quickstart
export PIHOLE_URL="http://192.168.2.51"
export PIHOLE_PASSWORD="YOUR_PIHOLE_ADMIN_PASSWORD"

cd infra/envs/homelab
terraform init
terraform plan
terraform apply -auto-approve

## Ports
Caddy binds 80/443. Change in variables.tf if those are taken, or route via your existing proxy and remove the Caddy container.

## Diagram
sudo apt-get install -y graphviz
cd ../..
make diagram  # outputs docs/architecture.png + .svg
MD

echo "✅ Done. Project scaffold created at: $ROOT"
echo "Next:"
echo "  1) export PIHOLE_URL and PIHOLE_PASSWORD"
echo "  2) cd $ROOT/infra/envs/homelab && terraform init && terraform apply -auto-approve"
