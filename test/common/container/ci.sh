#!/bin/bash
set -euo pipefail
set -x

cd test/common/container

if [[ -v BUILD ]]; then
  #podman compose up --build -d cvmfs-dev
  podman build -f Dockerfile-dev . --tag cvmfs-dev-image:clean-slate
  mkdir -p     ../../../../ccache
  chmod -R 777 ../../../../ccache
  mkdir -p     ./build-and-client-tests.tmp
  chmod -R 777 ./build-and-client-tests.tmp
  mkdir -p     ../../../../tmp_cvmfs-build
  chmod -R 777 ../../../../tmp_cvmfs-build
  mkdir -p     ../../../../tmp_cvmfs-ext
  chmod -R 777 ../../../../tmp_cvmfs-ext
  podman create --privileged --replace --name cvmfs-dev \
    -v /sys/fs/cgroup:/sys/fs/cgroup \
    -v ../../../:/home/sftnight/cvmfs \
    -v ../../../../ccache:/home/sftnight/.ccache \
    -v ./build-and-client-tests.tmp:/tmp \
    -v ../../../../tmp_cvmfs-build:/tmp/cvmfs-build \
    -v ../../../../tmp_cvmfs-ext:/tmp/cvmfs-ext \
    cvmfs-dev-image:clean-slate
  podman start cvmfs-dev

  time podman exec -u sftnight cvmfs-dev bash -c \
    "cmake -S /home/sftnight/cvmfs -B /tmp/cvmfs-build -D EXTERNALS_PREFIX=/tmp/cvmfs-ext -D BUILD_SHRINKWRAP=ON"

  time podman exec -u sftnight cvmfs-dev bash -c \
    "cd /tmp/cvmfs-build && make -j$(nproc) && sudo make -j$(nproc) install"

  podman commit cvmfs-dev cvmfs-dev-image:build-installed

  podman exec -u sftnight cvmfs-dev /bin/bash -c "sudo cvmfs_config setup"
  podman exec -u sftnight cvmfs-dev /bin/bash -c "sudo cvmfs_config chksetup"

  podman commit cvmfs-dev cvmfs-dev-image:chksetup
  podman stop cvmfs-dev
fi

#time podman rm -f $(podman ps -a --format="{{.Names}}" | grep cvmfs-ci-worker- || true) || true
rm -rf   worker

if ! [[ -v NB_WORKERS ]]; then
  NB_WORKERS=$(nproc)
fi
PRIORITIZE=(nice -n19  ionice -c3)
for worker_i in $(seq 1 "$NB_WORKERS"); do
  mkdir -p worker/$worker_i/orders
  mkdir -p worker/$worker_i/orders/.wip
  mkdir -p worker/$worker_i/tmp
  chmod -R 777 worker/$worker_i
done

for worker_i in $(seq 1 "$NB_WORKERS"); do
  # /var/spool/cvmfs should be a bucket (or perhaps a tmpfs),
  # because with a bind-mount dir from host,
  # some overlay features may be unsupported and tests will fail.
  #podman volume rm var_spool_cvmfs-for-server-tests --force
  #  -v var_spool_cvmfs-for-server-tests:/var/spool/cvmfs \
  #  --tmpfs /var/spool/cvmfs \
  "${PRIORITIZE[@]}" podman create --ulimit nice=20 --replace --privileged --name cvmfs-ci-worker-$worker_i \
    -v /sys/fs/cgroup:/sys/fs/cgroup \
    -v ../../../:/home/sftnight/cvmfs \
    -v ./worker/$worker_i/tmp:/tmp \
    -v ./worker/$worker_i/orders:/orders \
    --tmpfs /var/spool/cvmfs \
    cvmfs-dev-image:chksetup \
    && "${PRIORITIZE[@]}" podman start cvmfs-ci-worker-$worker_i \
    && "${PRIORITIZE[@]}" podman exec -u sftnight cvmfs-ci-worker-$worker_i bash -c \
    "while ! systemctl status &>/dev/null; do sleep 1; done; nohup /home/sftnight/cvmfs/test/common/container/work.sh &> /tmp/work.log &" \
    &

#  # examples:
#  job_file=$(mktemp --tmpdir=worker/$worker_i/orders/.wip)
#  cat > "$job_file" <<-EOF
##!/bin/bash
#set -euo pipefail
#set -x
#cd "/home/sftnight/cvmfs/test"
#./run.sh /dev/stdout -- src/000-dummy
#EOF
#  chmod a+rwx "$job_file"
#  # reveal:
#  mv "$job_file" worker/$worker_i/orders

#  touch worker/$worker_i/orders/non-executable-for-quit
done

# inclusions:
# grep -l 'cvmfs_test_suites=.*quick' src/[01567]*/main | sed s:/main::
# exclusions:
# grep 'src/[0-9]\+-' common/container/test.sh | sed -e 's: -x ::' -e 's: ::g' -e 's:[\]::'
TESTS=$(
set -euo pipefail
pushd ../.. &>/dev/null
[[ "$(basename "$PWD")" == test ]]
comm -23 \
  <(grep -l 'cvmfs_test_suites=.*quick' src/[01567]*/main | sed s:/main::) \
  <(grep 'src/[0-9]\+-' common/container/test.sh | sed -e 's: -x ::' -e 's: ::g' -e 's:[\]::')
# FOR TESTING, SOME SERVER TESTS ONLY!
# comm -23 \
#   <(grep -l 'cvmfs_test_suites=.*quick' src/[5]*/main | sed s:/main::) \
#   <(grep 'src/[0-9]\+-' common/container/test.sh | sed -e 's: -x ::' -e 's: ::g' -e 's:[\]::')
)

wait_until_found_idle_worker() {
  while true; do
    for worker_i in $(seq 1 "$NB_WORKERS"); do
      orders_dir=worker/$worker_i/orders
      if [[ "$(ls "$orders_dir")" == "" ]]; then
        echo "$orders_dir"
        return
      fi
    done
    sleep 0.5
  done
}

for test in $TESTS; do
  idle_worker_orders_dir=$(wait_until_found_idle_worker)
  jobname=$(echo $test | sed s:src/::)
  job_file=$(mktemp --tmpdir="$idle_worker_orders_dir"/.wip "$jobname".XXXXXXX.job)
  cat > "$job_file" <<-EOF
#!/bin/bash
set -euo pipefail
set -x
cd /home/sftnight/cvmfs/test
export CVMFS_TEST_PROXY=DIRECT
./run.sh /dev/stdout -- $test || true
EOF
  chmod a+rwx "$job_file"
  # reveal:
  mv "$job_file" $idle_worker_orders_dir/
done

for worker_i in $(seq 1 "$NB_WORKERS"); do
  touch worker/$worker_i/orders/non-executable-for-quit
done
for worker_i in $(seq 1 "$NB_WORKERS"); do
  if ! [[ -f worker/$worker_i/orders/non-executable-for-quit ]]; then
    podman stop -f cvmfs-ci-worker-$worker_i
  fi
done
tar -cf - worker/*/tmp/work.log worker/*/tmp/*.job* | zstd -T0 --ultra -20 > worker.$(date +%F_%T).tar.zst
grep 'Testcase failed' worker/*/tmp/*.job.log
echo 'Tests passed: '
grep 'Test passed' worker/*/tmp/*.job.log | wc -l
