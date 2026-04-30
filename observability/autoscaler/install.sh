#!/bin/bash
# Installation de l'autoscaler sur l'EC2 backend.
# Pose le script + un timer systemd qui le déclenche toutes les 30s.

set -euo pipefail

sudo dnf install -y python3 cronie >/dev/null 2>&1 || true

sudo install -m 0755 autoscale.sh /usr/local/bin/nexusplay-autoscale

sudo tee /etc/systemd/system/nexusplay-autoscale.service > /dev/null <<'UNIT'
[Unit]
Description=NexusPlay backend autoscaler

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nexusplay-autoscale
StandardOutput=append:/var/log/nexusplay-autoscale.log
StandardError=append:/var/log/nexusplay-autoscale.log
UNIT

sudo tee /etc/systemd/system/nexusplay-autoscale.timer > /dev/null <<'TIMER'
[Unit]
Description=NexusPlay autoscaler tick (30s)

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Unit=nexusplay-autoscale.service

[Install]
WantedBy=timers.target
TIMER

sudo systemctl daemon-reload
sudo systemctl enable --now nexusplay-autoscale.timer
sudo systemctl status nexusplay-autoscale.timer --no-pager | head -10
echo "✅ Autoscaler installé. Logs : sudo tail -f /var/log/nexusplay-autoscale.log"
