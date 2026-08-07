#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")
if ! type -t config_value &>/dev/null; then
    source "${SRC}/utils.sh"
fi
source "${SRC}/secure.sh"
source "${SRC}/prepare_android_img.sh"
source "${SRC}/build_opensbi.sh"
source "${SRC}/build_uboot.sh"

function build_all {
    local config="$1"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "${config}" "${mode}")
    local plat=$(config_value "$1" plat)

    if [[ "${clean}" == true ]] && [ -d "${out_dir}" ]; then
        rm -rf "${out_dir}"
    fi

    # build firmware
    build_opensbi "${config}" "${clean}" "${mode}"
    build_uboot "${config}" "${clean}" "${mode}"

    # extract boot binaries from zhihesdk
    tar xzf "${SRC}/downloads/zhihesdk-local-a210_evb.tar.gz" \
        --strip-components=2 -C "${out_dir}" \
        --wildcards "rootfs/boot/*.bin"

    # copy kernel dtb to out
    cp "${SRC}"/downloads/*.dtb "${out_dir}"

    # create fit image
    ITS_FILE="${UBOOT_DIR}/board/zhihe/${plat}/riscv-boot.its"
    GENDISK="${UBOOT_DIR}/board/zhihe/common/script/gendisk.sh"
    PATH="$PATH:${UBOOT_DIR}/tools/"
    ${GENDISK} --fit "${ITS_FILE}" "${out_dir}" "${out_dir}/riscv-boot.itb"

    # generate loader image
    BOOTZERO=bootzero2.bin # (a210)
    ${GENDISK} --image "${out_dir}/${BOOTZERO}" "${out_dir}/u-boot-spl.bin" \
               "${out_dir}/riscv-boot.itb" "${out_dir}"
    cp "${out_dir}/btz-with-uboot-rvbl.bin" "${out_dir}/emmc_boot-loader.img"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
