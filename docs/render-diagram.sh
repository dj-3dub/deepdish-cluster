#!/usr/bin/env bash
set -euo pipefail
dot -Tpng docs/architecture.dot -o docs/architecture.png
dot -Tsvg docs/architecture.dot -o docs/architecture.svg
echo "Rendered -> docs/architecture.png and docs/architecture.svg"
