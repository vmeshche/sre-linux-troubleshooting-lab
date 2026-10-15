#!/usr/bin/env bash
set -uo pipefail
LAB_ERRORS=0
if [[ $(uname -s) != Linux ]] || [[ $(ps -p 1 -o comm=) != systemd ]]; then
  printf 'Run inside the Ubuntu VM with systemd as PID 1.\n' >&2
  exit 1
fi
cat /etc/os-release
uname -m
for LAB_COMMAND in strace lsof ss gcc python3 timeout readelf objdump nm strip ar file; do
  if command -v "$LAB_COMMAND" >/dev/null; then
    printf 'OK: %s\n' "$LAB_COMMAND"
  else
    printf 'MISSING: %s\n' "$LAB_COMMAND"; LAB_ERRORS=$((LAB_ERRORS+1))
  fi
done
for LAB_FILE in config wait deleted cpu-hot; do
  if [[ ! -x /opt/lk7-lab/bin/$LAB_FILE ]]; then
    printf 'MISSING: /opt/lk7-lab/bin/%s; run setup.sh\n' "$LAB_FILE"; LAB_ERRORS=$((LAB_ERRORS+1))
  fi
done
if [[ -n $(ss -H -ltn 'sport = :8091') ]]; then
  printf 'BUSY: port 8091; identify its owner before the seminar.\n'; LAB_ERRORS=$((LAB_ERRORS+1))
fi
if [[ -e /etc/lk7-lab/app.conf ]]; then
  printf 'RESET: config case already fixed; run reset.sh before the seminar.\n'; LAB_ERRORS=$((LAB_ERRORS+1))
fi
if command -v perf >/dev/null && perf --version; then
  printf 'INFO: perf exists. Test software events using the README preflight.\n'
else
  printf 'INFO: perf unavailable; use the documented recorded example in case 3.\n'
fi
if (( LAB_ERRORS > 0 )); then exit 1; fi
printf 'Ready for ELF and service cases. Check perf separately.\n'
