#!/bin/bash
set -euo pipefail
set -x

pushd /orders
while true; do
  # deliberately do not list any hidden files or dirs
  oldest_job=$(ls -rt | head -n1)
  if [[ "$oldest_job" == '' ]]; then sleep 1; continue; fi
  if ! [[ -x "$oldest_job" ]]; then echo "Quitting"; rm -f "$oldest_job"; exit 0; fi
  # execute the file
  time "$PWD"/"$oldest_job" |& tee /tmp/"$oldest_job".log
  mv "$oldest_job" /tmp
done
