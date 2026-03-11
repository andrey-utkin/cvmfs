#!/bin/bash
set -euo pipefail
set -x

cd test/common/container
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
podman create --privileged --name cvmfs-dev \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v ../../../:/home/sftnight/cvmfs \
  -v ../../../../ccache:/home/sftnight/.ccache \
  -v ./build-and-client-tests.tmp:/tmp \
  -v ../../../../tmp_cvmfs-build:/tmp/cvmfs-build \
  -v ../../../../tmp_cvmfs-ext:/tmp/cvmfs-ext \
  cvmfs-dev-image:clean-slate
podman start cvmfs-dev

time podman exec -u sftnight -t cvmfs-dev bash -c \
  "cmake -S /home/sftnight/cvmfs -B /tmp/cvmfs-build -D EXTERNALS_PREFIX=/tmp/cvmfs-ext -D BUILD_SHRINKWRAP=ON"

time podman exec -u sftnight -t cvmfs-dev bash -c \
  "cd /tmp/cvmfs-build && make -j$(nproc) && sudo make -j$(nproc) install"

podman commit cvmfs-dev cvmfs-dev-image:build-installed

podman exec -u sftnight -t cvmfs-dev /bin/bash -c "sudo cvmfs_config setup"
podman exec -u sftnight -t cvmfs-dev /bin/bash -c "sudo cvmfs_config chksetup"

podman commit cvmfs-dev cvmfs-dev-image:chksetup
podman stop cvmfs-dev

rm -rf   worker
: ${NB_WORKERS:=4}
for worker_i in $(seq 1 "$NB_WORKERS"); do
  mkdir -p worker/$worker_i/orders
  mkdir -p worker/$worker_i/orders/.wip
  mkdir -p worker/$worker_i/tmp
  chmod -R 777 worker/$worker_i

  # /var/spool/cvmfs should be a bucket (or perhaps a tmpfs),
  # because with a bind-mount dir from host,
  # some overlay features may be unsupported and tests will fail.
  #podman volume rm var_spool_cvmfs-for-server-tests --force
  #  -v var_spool_cvmfs-for-server-tests:/var/spool/cvmfs \
  podman create --privileged --name cvmfs-ci-worker-$worker_i \
    -v /sys/fs/cgroup:/sys/fs/cgroup \
    -v ../../../:/home/sftnight/cvmfs \
    -v ./worker/$worker_i/tmp:/tmp \
    -v ./worker/$worker_i/orders:/orders \
    --tmpfs /var/spool/cvmfs \
    cvmfs-dev-image:chksetup
  podman start cvmfs-ci-worker-$worker_i # launches systemd

  podman exec -u sftnight -t cvmfs-ci-worker-$worker_i bash -c \
    "cd /home/sftnight/cvmfs/test/common/container && nohup ./work.sh &> /tmp/work.log &"

  job_file=$(mktemp --tmpdir=worker/$worker_i/orders/.wip)
  cat > "$job_file" <<-EOF
#!/bin/bash
set -euo pipefail
set -x
cd "/home/sftnight/cvmfs/test"
./run.sh /dev/stdout -- src/000-dummy
EOF
  chmod a+x "$job_file"
  # reveal:
  mv "$job_file" worker/$worker_i/orders
  touch worker/$worker_i/orders/non-executable-for-quit
done
