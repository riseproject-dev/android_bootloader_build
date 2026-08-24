#!/bin/bash

set -e
set -u
set -o pipefail

# Use BASH_SOURCE[0] (not $0) so path resolution works even when sourced
# after a pushd has changed the working directory.
SRC=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")
if ! type -t config_value &>/dev/null; then
    source "${SRC}/utils.sh"
    source "${SRC}/secure.sh"
fi

function build_uboot {
    local config="$1"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "${config}" "${mode}")
    local defconfig=$(config_value "${config}" uboot.defconfig)
    local fragments=$(config_value "${config}" uboot.defconfig_fragments)

    display_current_build "${config}" "uboot" "${mode}"

    if [ -z "${defconfig}" ]; then
        echo "uboot: skip build, defconfig not provided"
        return
    fi

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    pushd "${UBOOT_DIR}"
    if [[ "${clean}" == true ]]; then
        make distclean || true
    fi

    clear_vars
    riscv64_env

    # generate defconfig, merging any configured fragments (uboot.defconfig_fragments
    # in the board yaml) on top of the base defconfig
    if [ -n "${fragments}" ]; then
        local fragment_paths=()
        for frag in ${fragments}; do
            fragment_paths+=("${SRC}/config/defconfig_fragment/${frag}")
        done
        ./scripts/kconfig/merge_config.sh "configs/${defconfig}" "${fragment_paths[@]}"
    else
        make "${defconfig}"
    fi

    # generate u-boot and spl images
    make -j"$(nproc)"
    make u-boot.img
    cp u-boot.bin "${out_dir}/u-boot.bin"
    cp spl/u-boot-spl.bin "${out_dir}/u-boot-spl.bin"

    # generate emmc-uboot_env.img
    make envtools
    UBOOT_ENV_SIZE=$(grep CONFIG_ENV_SIZE .config | cut -d'=' -f2)
    ./tools/mkenvimage -s ${UBOOT_ENV_SIZE} \
                       -o "${out_dir}/emmc-uboot_env.img" \
                       u-boot-initial-env

    unset ARCH
    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
