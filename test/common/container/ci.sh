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

time podman exec -u sftnight -t cvmfs-dev bash -c \
  "cd /home/sftnight/cvmfs/test/common/container && CVMFS_TEST_PROXY=DIRECT TEST_CLIENT=1 TEST_SERVER=0 bash test.sh" \
  |& tee ./build-and-client-tests.tmp/cvmfs-client-test.container.log &


mkdir -p     ./server-tests.tmp
chmod -R 777 ./server-tests.tmp
# /var/spool/cvmfs should be a bucket (or perhaps a tmpfs),
# because with a bind-mount dir from host,
# some overlay features may be unsupported and tests will fail.
podman volume rm var_spool_cvmfs-for-server-tests --force
podman create --privileged --name cvmfs-ci-server-test \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v ../../../:/home/sftnight/cvmfs \
  -v ./server-tests.tmp:/tmp \
  -v var_spool_cvmfs-for-server-tests:/var/spool/cvmfs \
  cvmfs-dev-image:chksetup
podman start cvmfs-ci-server-test

time podman exec -u sftnight -t cvmfs-ci-server-test bash -c \
  "cd /home/sftnight/cvmfs/test/common/container && CVMFS_TEST_PROXY=DIRECT TEST_CLIENT=0 TEST_SERVER=1 bash test.sh" \
  |& tee ./server-tests.tmp/cvmfs-server-test.container.log &

wait
