#!/bin/bash

# It is expected that docker can be used.
# Run docker's service by yourself.
# `rc-service docker start` or `systemctl start docker.service`

gentoo_images=(
  # gentoo/stage3:amd64-hardened-nomultilib-openrc
  # gentoo/stage3:amd64-musl-hardened
  # gentoo/stage3:amd64-hardened-nomultilib-openrc
  # gentoo/stage3:amd64-hardened-openrc
  # gentoo/stage3:amd64-musl
  # gentoo/stage3:amd64-musl-hardened
  # gentoo/stage3:amd64-nomultilib-openrc
  # gentoo/stage3:amd64-nomultilib-systemd
  gentoo/stage3:amd64-openrc # until https://bugs.gentoo.org/937996 fixed, use only this because clang can be then downloaded as binpkg, not compiled.
  # gentoo/stage3:amd64-desktop-openrc
  # gentoo/stage3:amd64-systemd
  # gentoo/stage3:amd64-desktop-systemd
)

crossdev_full_targets=(
  "aarch64-gentoo-linux-musl"
  "aarch64-unknown-linux-gnu"
  "alpha-unknown-linux-gnu"
  "armv5tel-softfloat-linux-gnueabi"
  "armv6zk-unknown-linux-musleabihf"
  "armv7a-unknown-linux-gnueabihf"
  "hppa-unknown-linux-gnu"
  "hppa2.0-unknown-linux-gnu"
  "hppa64-unknown-linux-gnu"
  "i686-pc-gnu"
  "i686-w64-mingw32"
  "ia64-unknown-linux-gnu"
  "loongarch64-unknown-linux-gnu"
  "m68k-unknown-linux-gnu"
  "mips-unknown-linux-gnu"
  "mips64-unknown-linux-gnu"
  "mips64el-unknown-linux-gnu"
  "mipsel-unknown-linux-gnu"
  "nios2-unknown-linux-gnu"
  "or1k-linux-musl"
  "powerpc-unknown-linux-gnu"
  "powerpc64-unknown-linux-gnu"
  "powerpc64le-unknown-linux-gnu"
  "s390-unknown-linux-gnu"
  "s390x-unknown-linux-gnu"
  "sh4-unknown-linux-gnu"
  "sparc-unknown-linux-gnu"
  "sparc64-unknown-linux-gnu"
  "vax-unknown-linux-gnu"
  "x86_64-HEAD-linux-gnu"
  "x86_64-UNREG-linux-gnu"
  "x86_64-pc-linux-gnu"
  "x86_64-w64-mingw32"
)

crossdev_baremetal_targets=(
  "arm-none-eabi"
  "avr"
  "mmix"
  "msp430-elf"
  "xtensa-esp32-elf"
)

# minimal amount of packages that uses C and C++ compilers I could think of
packages_to_build_for_testing_full_targets=(
  "dev-libs/boost"
  "sys-libs/zlib"
)

crossdev_use_llvm_or_empty_string=(
  "--llvm"
  ""
)

template_base='
FROM ${gentoo_image}

RUN echo "Updating Gentoo index registry..."
RUN emerge-webrsync

RUN getuto

RUN emerge -vtg -j 2 eselect-repository

RUN eselect repository create crossdev_repo

WORKDIR crossdev_folder
COPY . .
RUN ls -lahR

RUN make install

RUN crossdev --help

RUN echo \"${crossdev_use_llvm_or_empty_string[@]}\" | grep \"llvm\" && FEATURES=\"-ipc-sandbox -network-sandbox -pid-sandbox\"  emerge -vtg -j2 clang
'

template_crossdev_full_target='
FROM ${gentoo_image_special_char_to_underscore}

RUN crossdev --show-fail-log ${use_llvm} --ov-output /var/db/repos/crossdev_repo -s4 --target ${crossdev_target}

RUN FEATURES=\"-ipc-sandbox -network-sandbox -pid-sandbox\" USE=\"python_targets_python3_12 python_targets_python3_13 pam ssl\" ${crossdev_target}-emerge -vt -j 4 ${packages_to_build_for_testing_full_targets[@]}
'

template_crossdev_baremetal_target='
FROM ${gentoo_image_special_char_to_underscore}

RUN crossdev --show-fail-log ${use_llvm} --ov-output /var/db/repos/crossdev_repo -s4 --target ${crossdev_target}
'

for gentoo_image in "${gentoo_images[@]}"; do
  gentoo_image_special_char_to_underscore=$(echo "${gentoo_image}" | sed -r 's/[/:]/_/g')

  # template substitution
  eval "echo \"${template_base}\" " >"${TMP}./Dockerfile_${gentoo_image_special_char_to_underscore}"

  docker build . -f "${TMP}./Dockerfile_${gentoo_image_special_char_to_underscore}" -t "${gentoo_image_special_char_to_underscore}" || return $?

  full_baremetal=("full" "baremetal")
  for target_type in "${full_baremetal[@]}"; do

    # https://stackoverflow.com/a/61364880
    declare -n crossdev_specific_array=crossdev_${target_type}_targets
    declare -n template_crossdev_specific_template=template_crossdev_${target_type}_target
    for crossdev_target in "${crossdev_specific_array[@]}"; do
      for use_llvm in "${crossdev_use_llvm_or_empty_string[@]}"; do
        if [[ "${use_llvm}" =~ "llvm" ]]; then
          gcc_or_llvm="llvm"
          echo "${crossdev_target}" | grep "gnu" && echo "The ${crossdev_target} is not going to be build with llvm, because clang right now cannot build glibc in a good way." && continue
        else
          gcc_or_llvm="gcc"
        fi
        # template substitution
        eval "echo \"${template_crossdev_specific_template}\" " >"${TMP}./Dockerfile_${gentoo_image_special_char_to_underscore}_crossdev_${crossdev_target}_${gcc_or_llvm}"

        docker build . -f "${TMP}./Dockerfile_${gentoo_image_special_char_to_underscore}_crossdev_${crossdev_target}_${gcc_or_llvm}" -t "${gentoo_image_special_char_to_underscore}_crossdev_${crossdev_target}_${gcc_or_llvm}" || return $?

        # clean if success.
        # docker rmi "${gentoo_image_special_char_to_underscore}_crossdev_${crossdev_full_target}_${gcc_or_llvm}", because clang right now cannot build glibc in a good way.      rm "${TMP}./Dockerfile_${gentoo_image_special_char_to_underscore}_crossdev_${crossdev_full_target}_${gcc_or_llvm}"
      done
    done
  done

  # docker rmi "${gentoo_image_special_char_to_underscore}"
  # rm "${TMP}./Dockerfile_${gentoo_image_special_char_to_underscore}"
done
