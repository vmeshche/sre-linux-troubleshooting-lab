#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )) || [[ $(ps -p 1 -o comm=) != systemd ]]; then
  printf 'Run sudo bash scripts/setup.sh inside the Ubuntu VM.\n' >&2
  exit 1
fi
LAB_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for LAB_COMMAND in gcc python3 strace lsof ss; do
  command -v "$LAB_COMMAND" >/dev/null || { printf 'Missing command: %s\n' "$LAB_COMMAND" >&2; exit 1; }
done
if id lk7-demo >/dev/null 2>&1; then
  if (( $(id -u lk7-demo) >= 1000 )) || [[ $(getent passwd lk7-demo | cut -d: -f7) != /usr/sbin/nologin ]]; then
    printf 'An unexpected lk7-demo account already exists. Use a clean lab VM.\n' >&2
    exit 1
  fi
else
  useradd --system --user-group --home-dir /nonexistent --shell /usr/sbin/nologin lk7-demo
fi
for LAB_UNIT in lk7-config lk7-port-owner lk7-web lk7-wait lk7-deleted lk7-cpu; do
  if systemctl is-active --quiet "$LAB_UNIT"; then
    printf 'Stop the previous lab first: sudo bash scripts/reset.sh\n' >&2
    exit 1
  fi
done
install -d -m 0755 /opt/lk7-lab/bin /etc/lk7-lab /srv/lk7-lab/old /srv/lk7-lab/new
install -d -m 0755 -o lk7-demo -g lk7-demo /var/lib/lk7-lab /var/lib/lk7-lab/work /var/lib/lk7-lab/log
install -d -m 0700 -o lk7-demo -g lk7-demo /var/lib/lk7-lab/traces
for LAB_SOURCE in config wait deleted cpu-hot; do
  gcc -O2 -g -fno-omit-frame-pointer -fno-optimize-sibling-calls -Wall -Wextra \
    "$LAB_REPO/examples/$LAB_SOURCE.c" -o "/opt/lk7-lab/bin/$LAB_SOURCE"
  chmod 0755 "/opt/lk7-lab/bin/$LAB_SOURCE"
done
printf 'message=ready\n' > /etc/lk7-lab/service.conf
chmod 0644 /etc/lk7-lab/service.conf
printf 'old application\n' > /srv/lk7-lab/old/index.html
printf 'new application\n' > /srv/lk7-lab/new/index.html
chmod 0644 /srv/lk7-lab/{old,new}/index.html
install -m 0644 "$LAB_REPO"/units/*.service /etc/systemd/system/
systemctl daemon-reload
systemd-analyze verify "$LAB_REPO"/units/*.service
printf 'Prepared. Run sudo bash scripts/reset.sh, then bash scripts/check-environment.sh.\n'
