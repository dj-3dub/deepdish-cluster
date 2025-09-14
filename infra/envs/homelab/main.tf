#############################################
# Pizza IaC (Docker) - homelab main.tf
# Path: infra/envs/homelab/main.tf
#############################################

# ----- Network -----
resource "docker_network" "pizza_net" {
  name = "pizza_net"
}

# ----- Volumes -----
resource "docker_volume" "pg_data" {
  name = "pizza_pg_data"
}
resource "docker_volume" "kuma_data" {
  name = "pizza_kuma_data"
}
resource "docker_volume" "caddy_data" {
  name = "caddy_data"
}
resource "docker_volume" "caddy_cfg" {
  name = "caddy_config"
}

# ----- Secrets -----
resource "random_password" "postgres_password" {
  length  = 16
  special = false
}

# ----- Database: PostgreSQL (toppings) -----
resource "docker_container" "postgres" {
  name    = "toppings-db"
  image   = "postgres:16"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.pizza_net.name
  }

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

# ----- App: Pizza API (placeholder image) -----
resource "docker_container" "pizza_api" {
  name    = "pizza-api"
  image   = "nginxdemos/hello" # swap to your image (e.g., ghcr.io/dj-3dub/pizza-api:latest)
  restart = "unless-stopped"

  depends_on = [docker_container.postgres]

  networks_advanced {
    name = docker_network.pizza_net.name
  }
}

# ----- Observability: Uptime-Kuma -----
resource "docker_container" "uptime_kuma" {
  name    = "uptime-kuma"
  image   = "louislam/uptime-kuma:1"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.pizza_net.name
  }

  mounts {
    target = "/app/data"
    source = docker_volume.kuma_data.name
    type   = "volume"
  }
}

# ============================================
# Caddy config: ensure folder + render file
# ============================================

# Make sure the caddy/ directory exists (so the bind mount path is valid)
resource "null_resource" "ensure_caddy_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${abspath("${path.module}/caddy")}"
  }
}

# Render the Caddyfile from template
data "template_file" "caddyfile" {
  template = file("${path.module}/caddy/Caddyfile.tmpl")
  vars = {
    oven_host   = "oven.${var.pizza_domain}"
    api_host    = "api.${var.pizza_domain}"
    status_host = "status.${var.pizza_domain}"
  }
}

# Write the rendered file to disk (absolute path)
resource "local_file" "caddyfile" {
  content  = data.template_file.caddyfile.rendered
  filename = "${path.module}/caddy/Caddyfile"

  depends_on = [null_resource.ensure_caddy_dir]
}

# ----- Reverse Proxy: Caddy (the Oven) -----
resource "docker_container" "caddy" {
  name    = "caddy-oven"
  image   = "caddy:2.8"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.pizza_net.name
  }

  # Publish HTTP/HTTPS (change ports in variables.tf if needed)
  ports {
    internal = 80
    external = var.caddy_http_port
  }
  ports {
    internal = 443
    external = var.caddy_https_port
  }

  # Bind the rendered Caddyfile with an ABSOLUTE host path
  mounts {
    type   = "bind"
    target = "/etc/caddy/Caddyfile"
    source = abspath("${path.module}/caddy/Caddyfile")
  }

  # Data/config volumes
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

  # Ensure the Caddyfile exists before creating the container
  depends_on = [local_file.caddyfile]
}
