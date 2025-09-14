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
