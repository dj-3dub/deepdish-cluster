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
	dot -Tpng docs/architecture.dot -o docs/architecture.png
	dot -Tsvg docs/architecture.dot -o docs/architecture.svg

TF_DIR := infra/terraform/homelab

preflight:
	@./$(TF_DIR)/preflight.sh

tf-init:
	@terraform -chdir=$(TF_DIR) init

tf-plan:
	@terraform -chdir=$(TF_DIR) plan

tf-apply:
	@terraform -chdir=$(TF_DIR) apply -auto-approve

tf-destroy:
	@terraform -chdir=$(TF_DIR) destroy -auto-approve
