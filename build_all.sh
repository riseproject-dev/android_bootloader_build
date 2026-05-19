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

# Detect platform and source appropriate build scripts
function source_platform_scripts {
    local config="$1"
    local plat=$(config_value "${config}" plat)

    case "${plat}" in
        spacemit|k1)
            source "${SRC}/build_opensbi.sh"
            source "${SRC}/build_uboot.sh"
            ;;
        k3|am62*|am64*|am67*)
            source "${SRC}/build_bl31.sh"
            source "${SRC}/build_tispl.sh"
            source "${SRC}/build_optee.sh"
            source "${SRC}/build_tiboot.sh"
            ;;
        *)
            error_exit "Unknown platform: ${plat}"
            ;;
    esac
}

function build_all {
    local config="$1"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "${config}" "${mode}")
    local plat=$(config_value "${config}" plat)

    # Source platform-specific build scripts
    source_platform_scripts "${config}"

    if [[ "${clean}" == true ]] && [ -d "${out_dir}" ]; then
        rm -rf "${out_dir}"
    fi

    case "${plat}" in
        spacemit|k1)
            # Spacemit K1 boot chain: OpenSBI -> U-Boot
            build_opensbi "${config}" "${clean}" "${mode}"
            build_uboot "${config}" "${clean}" "${mode}"
            # Prepare Android flash images
            prepare_android_images "${config}" "${mode}" "${out_dir}" "false"
            ;;
        k3|am62*|am64*|am67*)
            # TI K3 boot chain: BL31 -> tiboot3 -> OP-TEE -> tispl
            build_bl31 "$@"
            build_tiboot "${config}" "${clean}" "${mode}"
            build_optee "$@"
            build_tispl "$@"
            ;;
    esac

    # secure package
    if [[ "${mode}" == "factory" ]]; then
        generate_secure_package "${config}" "${out_dir}"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
