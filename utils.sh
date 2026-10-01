#!/bin/bash
# Spacemit K1 Bootloader Build Utilities
# Adapted from TI build system for RISC-V

BUILD=$(dirname "$(readlink -e "$0")")
ROOT=$(readlink -e "${BUILD}/../")
OUT="${ROOT}/out"
TOOLCHAINS="${SYSTEM_WIDE_TOOLCHAINS:-${ROOT}/toolchains}"
MODES=("release" "debug" "factory")

INIT_PATH=$PATH

# Source directories
OPENSBI_DIR="${ROOT}/opensbi"
UBOOT_DIR="${ROOT}/u-boot"

function pushd {
    command pushd "$@" > /dev/null
}

function popd {
    command popd > /dev/null
}

function find_path {
    local path="$1"
    local real_path=""
    if [ -e "${path}" ]; then
        real_path=$(readlink -e "${path}")
    fi
    echo "${real_path}"
}

function check_local_changes {
    local repo_path="$1" && shift
    local projects=("$@")

    for project in "${projects[@]}"; do
        if [ -d "${repo_path}/${project}" ]; then
            pushd "${repo_path}/${project}"
            git status > /dev/null 2>&1 || { popd; continue; }
            if ! git diff --quiet HEAD 2>/dev/null; then
                warning "Local changes detected in: ${project}"
            fi
            popd
        fi
    done
}

# RISC-V cross-compiler: kernel.org "crosstool" GCC (nolibc).
RISCV_TOOLCHAIN_VERSION="14.2.0"
RISCV_TOOLCHAIN_TARBALL="x86_64-gcc-${RISCV_TOOLCHAIN_VERSION}-nolibc-riscv64-linux.tar.xz"
RISCV_TOOLCHAIN_URL="https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/${RISCV_TOOLCHAIN_VERSION}/${RISCV_TOOLCHAIN_TARBALL}"
RISCV_TOOLCHAIN_DIR="${TOOLCHAINS}/gcc-${RISCV_TOOLCHAIN_VERSION}-nolibc/riscv64-linux"
RISCV_CROSS_COMPILE="riscv64-linux-"

function riscv64_env {
    export PATH="${RISCV_TOOLCHAIN_DIR}/bin:$PATH"
    export CROSS_COMPILE="${RISCV_CROSS_COMPILE}"
    export ARCH=riscv
}

function check_riscv64 {
    if [ ! -x "${RISCV_TOOLCHAIN_DIR}/bin/${RISCV_CROSS_COMPILE}gcc" ]; then
        echo "Downloading RISC-V toolchain ..."
        local tarball="${TOOLCHAINS}/${RISCV_TOOLCHAIN_TARBALL}"
        wget -q --show-progress -O "${tarball}" "${RISCV_TOOLCHAIN_URL}"
        tar -xJf "${tarball}" -C "${TOOLCHAINS}"
        rm -f "${tarball}"
    fi
}

function avbtool_env {
    if [ -d "${ROOT}/prebuilts/build-tools/linux-x86/bin/" ]; then
        export PATH="${ROOT}/prebuilts/build-tools/linux-x86/bin/:$PATH"
    fi
}

function clear_vars {
    export PATH=$INIT_PATH
    unset ARCH
    unset CROSS_COMPILE
}

function check_env {
    # out directory
    ! [ -d "${OUT}" ] && mkdir -p "${OUT}"

    # toolchains directory
    ! [ -d "${TOOLCHAINS}" ] && mkdir -p "${TOOLCHAINS}"

    # check RISC-V toolchain
    check_riscv64
}

function config_value {
    local value=$(cat "$1" | shyaml --quiet get-value "$2" 2>/dev/null)
    echo "${value}"
}

function board_name {
    local yaml_config=$(basename "$1")
    echo "${yaml_config%.yaml}"
}

function out_dir {
    local board=$(board_name "$1")
    local mode="${2:-release}"

    echo "${OUT}/${board}/${mode}"
}

function display_current_build {
    local board=$(board_name "$1")
    local build="$2"
    local mode="$3"

    printf "\n"
    printf "%0.s-" {1..20}
    printf "> Build %s: %s - %s <" "${build}" "${board}" "${mode}"
    printf "%0.s-" {1..20}
    printf "\n"
}

function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --config=config/boards/spacemit-k1.yaml

Options:
  --config   board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
DELIM__
}

function warning {
    local warning="$1"
    printf "\033[0;33mWARNING:\033[0m ${warning}\n"
}

function error {
    local error="$1"
    printf "\033[0;31mERROR:\033[0m ${error}\n\n"
}

function error_exit {
    error "$1"
    exit 1
}

function error_usage_exit {
    error "$1"
    usage
    exit 1
}

function main {
    local script=$(basename "$0")
    local build="${script%.*}"
    local clean=false
    local config=""
    local mode="release"

    local opts_args="clean,config:,help,mode:"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --config) config=$(find_path "$2"); shift 2 ;;
            --clean) clean=true; shift ;;
            --mode) mode="$2"; shift 2 ;;
            --help) usage; exit 0 ;;
            --) shift; break ;;
        esac
    done

    # check arguments
    [ -z "${config}" ] &&  error_usage_exit "Cannot find board config file"
    ! [[ " ${MODES[*]} " =~ " ${mode} " ]] && error_usage_exit "${mode} mode not supported"

    # build
    check_env
    ${build} "${config}" "${clean}" "${mode}"
}
