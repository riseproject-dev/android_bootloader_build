#!/bin/bash
# Generate the eMMC GPT primary-table image (protective MBR + primary GPT
# header + partition entry array) from a sfdisk-format partition table.

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")
if ! type -t config_value &>/dev/null; then
    source "${SRC}/utils.sh"
fi

SFDISK="${SFDISK:-sfdisk}"

function check_gpt_tools {
    local tool
    for tool in "${SFDISK}" numfmt bc dd truncate; do
        command -v "${tool}" &> /dev/null || error_exit "${tool} not found (required to build the GPT image)"
    done
}

# gen_gpt_image() - write a GPT primary-table image
# $1: sfdisk-format partition table (e.g. config/gpt_emmc_android.txt)
# $2: output image path (e.g. out_dir/emmc-gpt_primary.img)
function gen_gpt_image {
    local gptcfg="$1"
    local gptimg="$2"

    if [ ! -e "${gptcfg}" ]; then
        echo ">>> Ignore create GPT: ${gptcfg} not found"
        return 0
    fi

    check_gpt_tools

    echo ">>> Create GPT image"

    local workdir=$(mktemp -d)
    local diskimg="${workdir}/dev_mmc0blkp"

    # Get disk capacity from partition data
    local disksize=$(grep "last-lba" "${gptcfg}" | awk -F':|i' '{print $2}' | numfmt --from=iec)

    # To expand disk capacity, sufficient space must be available to store the backup partition table.
    disksize=$(echo "${disksize} + 32768" | bc)

    echo "    Create disk(${disksize})"
    truncate -s "${disksize}" "${diskimg}"

    echo "    Write gpt to disk"
    if ! "${SFDISK}" "${diskimg}" < "${gptcfg}" > /dev/null; then
        echo "    Write gpt error"
        rm -rf "${workdir}"
        return 1
    fi

    echo "    Dump gpt.img"
    mkdir -p "$(dirname "${gptimg}")"
    dd if="${diskimg}" of="${gptimg}" bs=1024 count=32 2> /dev/null

    # Show info
    "${SFDISK}" "${diskimg}" -l

    rm -rf "${workdir}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    gen_gpt_image "$@"
fi
