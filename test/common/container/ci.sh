#!/bin/bash
set -euo pipefail
set -x

cd test/common/container
#podman compose up --build -d cvmfs-dev
podman build -f Dockerfile-dev . --tag cvmfs-dev-image:clean-slate
mkdir -p ../../../../ccache
mkdir -p ./build-and-client-tests.tmp
mkdir -p ../../../../tmp_cvmfs-build
mkdir -p ../../../../tmp_cvmfs-ext
podman run --privileged --name cvmfs-dev \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v ../../../:/home/sftnight/cvmfs \
  -v ../../../../ccache:/home/sftnight/.ccache \
  -v ./build-and-client-tests.tmp:/tmp \
  -v ../../../../tmp_cvmfs-build:/tmp/cvmfs-build \
  -v ../../../../tmp_cvmfs-ext:/tmp/cvmfs-ext \
  cvmfs-dev-image:clean-slate

podman exec -u sftnight -t cvmfs-dev bash -c \
  "cmake -S /home/sftnight/cvmfs -B /tmp/cvmfs-build -D EXTERNALS_PREFIX=/tmp/cvmfs-ext -D BUILD_SHRINKWRAP=ON"

podman exec -u sftnight -t cvmfs-dev bash -c \
  "cd /tmp/cvmfs-build && make -j$(nproc) && sudo make -j$(nproc) install"

podman commit cvmfs-dev cvmfs-dev-image:build-installed

podman exec -u sftnight -t cvmfs-dev /bin/bash -c "sudo cvmfs_config setup"
podman exec -u sftnight -t cvmfs-dev /bin/bash -c "sudo cvmfs_config chksetup"

podman commit cvmfs-dev cvmfs-dev-image:chksetup

podman exec -u sftnight -t cvmfs-dev bash -c \
  "cd /home/sftnight/cvmfs/test/common/container && CVMFS_TEST_PROXY=DIRECT TEST_CLIENT=1 TEST_SERVER=0 bash test.sh" \
  |& tee ./build-and-client-tests.tmp/cvmfs-client-test.container.log &


podman run --privileged --name cvmfs-ci-server-test \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v ../../../:/home/sftnight/cvmfs \
  -v ./server-tests.tmp:/tmp \
  cvmfs-dev-image:chksetup

mkdir -p ./server-tests.tmp
podman exec -u sftnight -t cvmfs-ci-server-test bash -c \
  "cd /home/sftnight/cvmfs/test/common/container && CVMFS_TEST_PROXY=DIRECT TEST_CLIENT=0 TEST_SERVER=1 bash test.sh" \
  |& tee ./server-tests.tmp/cvmfs-server-test.container.log &

wait
