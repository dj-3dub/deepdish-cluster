.PHONY: diagram
diagram:
	 bash docs/render-diagram.sh

.PHONY: smoke
smoke:
	 kubectl get nodes -o wide
	 kubectl get pods -A | head -20
