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
source "${SRC}/gen_gpt_image.sh"

# Generate the eMMC GPT primary-table image
function generate_gpt_image {
    local config="$1"
    local out_dir="$2"
    local emmc_size=$(config_value "${config}" android.emmc_size)

    if [ -z "${emmc_size}" ]; then
        return 0
    fi

    local gptcfg="${SRC}/config/gpt_emmc_android.txt"
    if [ "${emmc_size}" = "32G" ]; then
        gptcfg="${SRC}/config/gpt_emmc_android_32g.txt"
    elif [ "${emmc_size}" != "8G" ]; then
        error_exit "Unsupported android.emmc_size: ${emmc_size} (expected 8G or 32G)"
    fi

    echo "Generating GPT primary-table image (${emmc_size})..."
    gen_gpt_image "${gptcfg}" "${out_dir}/emmc-gpt_primary.img"
}

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

    # generate GPT primary-table image
    generate_gpt_image "${config}" "${out_dir}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
