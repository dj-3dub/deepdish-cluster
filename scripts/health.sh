#!/usr/bin/env bash
set -euo pipefail
echo "===== SYSTEM HEALTH CHECK (lean) ====="
echo "Host: $(hostname) | IP: $(hostname -I | awk '{print $1}') | Uptime: $(uptime -p)"
echo
echo "== CPU & Memory =="
uptime | awk -F'load average:' '{print "Load avg:" $2}' | xargs
free -h | awk 'NR==1 || /Mem:/ {print}'
echo
echo "== Disk (/) =="
df -h / | awk 'NR==1 || NR==2 {print}'
echo
echo "== Top processes by Mem =="
ps -eo pid,cmd,%mem,%cpu --sort=-%mem | head -5
echo
echo "== Listening ports (top 10) =="
ss -tuln | awk 'NR==1 || NR<=11 {print}'
echo
echo "== Enabled services (top 15) =="
systemctl list-unit-files --type=service | grep enabled | head -15
echo
if command -v kubectl >/dev/null 2>&1; then
  echo "== K3s snapshot =="
  kubectl get nodes -o wide || true
  kubectl get pods -A --field-selector=status.phase!=Succeeded --no-headers 2>/dev/null | wc -l | xargs echo "Non-succeeded pods:"
  kubectl get pods -A | head -10 || true
fi
echo "===== END ====="
