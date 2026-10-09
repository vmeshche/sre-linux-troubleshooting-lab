#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )) || [[ ! -f /etc/lk7-lab/service.conf ]]; then
  printf 'Run as root after scripts/setup.sh in the Ubuntu lab VM.\n' >&2
  exit 1
fi
LAB_UNITS=(lk7-config lk7-port-owner lk7-web lk7-wait lk7-deleted lk7-cpu)
systemctl stop "${LAB_UNITS[@]}"
for LAB_UNIT in "${LAB_UNITS[@]}"; do
  if systemctl is-failed --quiet "$LAB_UNIT"; then
    systemctl reset-failed "$LAB_UNIT"
  fi
done
rm -f /etc/lk7-lab/app.conf /var/lib/lk7-lab/work/inbox /var/lib/lk7-lab/log/demo.log
printf 'Lab reset. Example services stopped; missing-config case restored.\n'
printf 'Trace files are retained in /var/lib/lk7-lab/traces for your review.\n'
