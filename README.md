# 🍕 DeepDish Cluster (Debian 13)

A Chicago-style, pizza-themed **K3s** cluster on **Debian 13** — using Terraform to provision, configure, and pull back a ready-to-use `kubeconfig`.  
K3s ships with **Traefik** as the ingress controller. **MetalLB** will be added in a future revision (not included yet).  
(Optional next step: add **cert-manager** for automated TLS.)

---

## 🧩 Components

- **K3s Control Plane** — lightweight Kubernetes distribution
- **Traefik** — ingress controller bundled with K3s
- **Terraform** — declarative provisioning and configuration
- **Makefile** — simple workflow (`make preflight`, `make tf-apply`, `make tf-destroy`)
- **Graphviz** — architecture diagrams

---

## 🚀 Quick Start

1. Run **preflight checks** (SSH, sudo, disk space, port 6443, etc.):

   ```bash
   make preflight
Provision the K3s control plane and fetch kubeconfig:

bash
Copy code
make tf-apply
Verify the cluster:

bash
Copy code
KUBECONFIG=infra/terraform/homelab/kubeconfig kubectl get nodes -o wide
kubectl get pods -A
Tear it down when finished:

bash
Copy code
make tf-destroy
## 🏗️ Architecture

![Architecture](docs/architecture.svg)

Render the diagram (requires Graphviz):

bash
Copy code
make diagram
Outputs:

docs/architecture.svg (ideal for GitHub README)

docs/architecture.png (handy for docs/slides)

📌 Why it matters
This project demonstrates:

Infrastructure as Code with Terraform (reproducible K3s cluster provisioning)

Ingress management with Traefik (bundled in K3s)

Automation-first workflow with Make targets (preflight, apply, destroy, diagram)

Clean documentation with Graphviz architecture diagrams

A foundation for adding MetalLB and cert-manager in future revisions
