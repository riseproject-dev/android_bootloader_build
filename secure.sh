#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")
if ! type -t config_value &>/dev/null; then
    source "${SRC}/utils.sh"
fi

KEYS="${BUILD}/.keys"

# Android Verified Boot (AVB)
AVB_KEY="avb.key"
AVB_PUB_KEY="avb_pub.key"

# Trusted Applications
TA_KEY="ta.pem"
TA_PUB_KEY="ta_pub.pem"

function get_ta_keys {
    local ta_key_config=$(config_value "$1" secure.ta_key)
    local -n ta_key_ref="$2"
    local ta_pub_key_config=$(config_value "$1" secure.ta_pub_key)
    local -n ta_pub_key_ref="$3"

    # check private/public keys in config
    if [ -n "${ta_key_config}" ]; then
        if [ -a "${ta_key_config}" ]; then
            ta_key_ref="${ta_key_config}"
        else
            error_exit "TA key not found: ${ta_key_config}"
        fi
    fi

    if [ -n "${ta_pub_key_config}" ]; then
        if [ -a "${ta_pub_key_config}" ]; then
            ta_pub_key_ref="${ta_pub_key_config}"
        else
            error_exit "TA public key not found: ${ta_pub_key_config}"
        fi
    fi

    [ -n "${ta_key_ref}" ] && [ -n "${ta_pub_key_ref}" ] && return

    # check private/public keys under ${KEYS}
    if [ -a "${KEYS}/${TA_KEY}" ] && [ -a "${KEYS}/${TA_PUB_KEY}" ]; then
        ta_key_ref="${KEYS}/${TA_KEY}"
        ta_pub_key_ref="${KEYS}/${TA_PUB_KEY}"
    fi
}

function generate_ta_keys {
    local ta_key="${KEYS}/${TA_KEY}"
    local ta_pub_key="${KEYS}/${TA_PUB_KEY}"

    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"

    openssl genrsa -out "${ta_key}" 4096
    openssl rsa -in "${ta_key}" -out "${ta_pub_key}" --pubout

    printf "TA keys generated here:\n%s\n%s\n" "${ta_key}" "${ta_pub_key}"
}

function get_avb_key {
    local avb_key_config=$(config_value "$1" secure.avb_key)
    local -n avb_key_ref="$2"

    if [ -n "${avb_key_config}" ]; then
        if [ -a "${avb_key_config}" ]; then
            avb_key_ref="${avb_key_config}"
        else
            error_exit "AVB key not found: ${avb_key_config}"
        fi
    else
        if [ -a "${KEYS}/${AVB_KEY}" ]; then
            avb_key_ref="${KEYS}/${AVB_KEY}"
        fi
    fi
}

function get_avb_pub_key {
    local avb_pub_key_config=$(config_value "$1" secure.avb_pub_key)
    local -n avb_pub_key_ref="$2"

    if [ -n "${avb_pub_key_config}" ]; then
        if [ -a "${avb_pub_key_config}" ]; then
            avb_pub_key_ref="${avb_pub_key_config}"
        else
            error_exit "AVB public key not found: ${avb_pub_key_config}"
        fi
    else
        if [ -a "${KEYS}/${AVB_PUB_KEY}" ]; then
            avb_pub_key_ref="${KEYS}/${AVB_PUB_KEY}"
        fi
    fi
}

# Helper function to get AVB key path directly (for command substitution)
# Usage: get_avb_key_path <config> [pub|priv]
function get_avb_key_path {
    local config="$1"
    local key_type="${2:-priv}"
    local key_path=""

    if [[ "${key_type}" == "pub" ]]; then
        local avb_pub_key_config=$(config_value "${config}" secure.avb_pub_key)
        if [ -n "${avb_pub_key_config}" ] && [ -f "${avb_pub_key_config}" ]; then
            key_path="${avb_pub_key_config}"
        elif [ -f "${KEYS}/${AVB_PUB_KEY}" ]; then
            key_path="${KEYS}/${AVB_PUB_KEY}"
        fi
    else
        local avb_key_config=$(config_value "${config}" secure.avb_key)
        if [ -n "${avb_key_config}" ] && [ -f "${avb_key_config}" ]; then
            key_path="${avb_key_config}"
        elif [ -f "${KEYS}/${AVB_KEY}" ]; then
            key_path="${KEYS}/${AVB_KEY}"
        fi
    fi

    echo "${key_path}"
}

function generate_avb_keys {
    local avb_key="${KEYS}/${AVB_KEY}"
    local avb_pub_key="${KEYS}/${AVB_PUB_KEY}"

    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"

    avbtool_env
    openssl genrsa -out "${avb_key}" 4096
    avbtool extract_public_key --key "${avb_key}" --output "${avb_pub_key}"

    printf "AVB keys generated here:\n%s\n%s\n" "${avb_key}" "${avb_pub_key}"
}

function generate_secure_package {
    local board=$(board_name "$1")
    local plat=$(config_value "$1" plat)
    local out_dir="$2"
    local package="secure_${board}.zip"

    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"
    pushd "${KEYS}"
    [ -a "${package}" ] && rm "${package}"


    # add Trusted Applications keys
    local ta_key=""
    local ta_pub_key=""
    get_ta_keys "$1" ta_key ta_pub_key
    if [ -n "${ta_key}" ]; then
        zip -ju "${package}" "${ta_key}"
    fi
    if [ -n "${ta_pub_key}" ]; then
        zip -ju "${package}" "${ta_pub_key}"
    fi

    # add Android Verified Boot keys
    local avb_key=""
    local avb_pub_key=""
    get_avb_key "$1" avb_key
    if [ -n "${avb_key}" ]; then
        zip -ju "${package}" "${avb_key}"
    fi
    get_avb_pub_key "$1" avb_pub_key
    if [ -n "${avb_pub_key}" ]; then
        zip -ju "${package}" "${avb_pub_key}"
    fi

    mv "${package}" "${out_dir}/"

    popd
}


# standalone main for secure.sh
function secure_usage {
    cat <<DELIM__
usage: $(basename "$0") function

Functions supported can be found in "$0"
DELIM__
}

function secure_main {
    if ! [ $# -eq 1 ]; then
        secure_usage
    else
        local command="$1"
        "${command}"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    secure_main "$@"
fi
