#!/bin/bash
set -euo pipefail
set -x

mkdir -p /var/log/ci/{pass,fail}
pushd /orders
while true; do
  # deliberately do not list any hidden files or dirs
  oldest_job=$(ls -rt | head -n1)
  if [[ "$oldest_job" == '' ]]; then sleep 1; continue; fi
  if ! [[ -x "$oldest_job" ]]; then echo "Quitting"; rm -f "$oldest_job"; exit 0; fi
  # execute the file
  set +e
  "$PWD"/"$oldest_job" &> /var/log/ci/"$oldest_job".log
  RC=$?
  set -e
  if [[ "$RC" == 0 ]]; then
    outcome=pass
  else
    outcome=fail
  fi
  mv "$oldest_job" /var/log/ci/$outcome/
done
