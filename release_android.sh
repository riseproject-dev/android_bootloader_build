#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_all.sh"
source "${SRC}/commit-binaries.sh"

# TI K3 projects
PROJECTS_AIOT_TI=("arm-trusted-firmware" "build" "optee-os" "ti-linux-firmware" "u-boot" "optee-ta/kmgk" "optee-ta/optee_test")
PROJECTS_REMOTES_TI="baylibre ti github tf-a"

# Spacemit K1 projects
PROJECTS_AIOT_SPACEMIT=("pi-opensbi" "pi-u-boot" "build-bootloaders")
PROJECTS_REMOTES_SPACEMIT="spacemit github"

# Default to TI (will be overridden based on config)
PROJECTS_AIOT=("${PROJECTS_AIOT_TI[@]}")
PROJECTS_REMOTES="${PROJECTS_REMOTES_TI}"

function add_commit_msg {
    local -n commits_msg_ref="$1"
    local title_prefix="$2"
    local ti_android_out="$3"
    local toplevel=""
    local commits_msg_value=""

    pushd "${ti_android_out}"
    toplevel=$(git rev-parse --sq --show-toplevel)
    if [[ -v "commits_msg_ref[${toplevel}]" ]]; then
        commits_msg_value="${commits_msg_ref[${toplevel}]}"
        if ! [[ ${commits_msg_value} =~ ${title_prefix} ]]; then
            unset commits_msg_ref["${toplevel}"]
            commits_msg_ref+=(["${toplevel}"]="${commits_msg_value}/${title_prefix}")
        fi
    else
        commits_msg_ref+=(["${toplevel}"]="${title_prefix}")
    fi
    popd
}

function copy_binaries {
    local out="$1"
    local android_out="$2"
    local config="$3"
    local mode="$4"
    local plat=$(config_value "${config}" plat)

    case "${plat}" in
        spacemit|k1)
            # Spacemit K1 binaries
            if [ -f "${out}/fw_dynamic-${mode}.bin" ]; then
                cp "${out}/fw_dynamic-${mode}.bin" "${android_out}/"
            fi
            if [ -f "${out}/u-boot-${mode}.itb" ]; then
                cp "${out}/u-boot-${mode}.itb" "${android_out}/"
            elif [ -f "${out}/u-boot-${mode}.bin" ]; then
                cp "${out}/u-boot-${mode}.bin" "${android_out}/"
            fi
            if [ -f "${out}/u-boot-spl-${mode}.bin" ]; then
                cp "${out}/u-boot-spl-${mode}.bin" "${android_out}/"
            fi
            if [ -f "${out}/u-boot-${mode}.dtb" ]; then
                cp "${out}/u-boot-${mode}.dtb" "${android_out}/"
            fi
            if [ -f "${out}/env-${mode}.bin" ]; then
                cp "${out}/env-${mode}.bin" "${android_out}/"
            fi
            # Flash-ready files (factory, partition config, prepared images)
            if [ -d "${out}/factory" ]; then
                mkdir -p "${android_out}/factory"
                cp -f "${out}/factory"/* "${android_out}/factory/"
            fi
            if [ -f "${out}/partition_android.json" ]; then
                cp -f "${out}/partition_android.json" "${android_out}/"
            fi
            if [ -f "${out}/fw_dynamic.itb" ]; then
                cp -f "${out}/fw_dynamic.itb" "${android_out}/"
            fi
            ;;
        k3|am62*|am64*|am67*)
            # TI K3 binaries
            local gp=$(config_value "${config}" secure.gp)
            local hsfs=$(config_value "${config}" secure.hsfs)
            if [[ "${gp}" == "True" ]]; then
                cp "${out}/tiboot3-${mode}-gp.bin" "${android_out}/"
            fi
            if [[ "${hsfs}" == "True" ]]; then
                cp "${out}/tiboot3-${mode}-hsfs.bin" "${android_out}/"
            fi
            cp "${out}/tispl-${mode}.bin" "${android_out}/"
            cp "${out}/u-boot-${mode}.img" "${android_out}/"
            ;;
        *)
            error_exit "Unknown platform: ${plat}"
            ;;
    esac
}

function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --aosp=<path-to-android-root>

Options:
  --aosp     Android Root path
  --commit   (OPTIONAL) commit binaries in AOSP
  --config   (OPTIONAL) release ONLY for this board config file
  --help     (OPTIONAL) display usage
  --mode     (OPTIONAL) [release|debug|factory] build only one mode
  --no-build (OPTIONAL) don't rebuild the images
  --silent   (OPTIONAL) silent build commands

DELIM__
}

function main {
    local aosp=""
    local commit=false
    local config=""
    local build=true
    local silent=false
    local mode_list=(debug release)

    local opts_args="aosp:,commit,config:,help,mode:,no-build,silent"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --aosp) aosp=$(find_path "$2"); shift 2 ;;
            --commit) commit=true; shift ;;
            --config)
                config=$(find_path "$2")
                [ -z "${config}" ] && error_usage_exit "Cannot find board config file"
                shift 2 ;;
            --help) usage; exit 0 ;;
            --mode) mode_list=("$2"); shift 2 ;;
            --silent) silent=true; shift ;;
            --no-build) build=false; shift ;;
            --) shift; break ;;
        esac
    done

    # check arguments
    [ -z "${aosp}" ] && error_usage_exit "Cannot find Android Root Path"

    # set configs list
    declare -a configs
    if [ -n "${config}" ]; then
        configs=("${config}")
    else
        configs=("${SRC}"/config/boards/*.yaml)
    fi

    # build configs
    local binaries_path=""
    local out_dir=""
    declare -A commits_msg

    # Check for local changes (check all projects for all platforms)
    #check_local_changes "${ROOT}" "${PROJECTS_AIOT_TI[@]}" || true
    #check_local_changes "${ROOT}" "${PROJECTS_AIOT_SPACEMIT[@]}" || true

    check_env

    pushd "${SRC}"
    for board_config in "${configs[@]}"; do
        local plat=$(config_value "${board_config}" plat)
        binaries_path=$(config_value "${board_config}" android.binaries_path)

        # Set platform-specific projects
        case "${plat}" in
            spacemit|k1)
                PROJECTS_AIOT=("${PROJECTS_AIOT_SPACEMIT[@]}")
                PROJECTS_REMOTES="${PROJECTS_REMOTES_SPACEMIT}"
                ;;
            k3|am62*|am64*|am67*)
                PROJECTS_AIOT=("${PROJECTS_AIOT_TI[@]}")
                PROJECTS_REMOTES="${PROJECTS_REMOTES_TI}"
                ;;
        esac

        for mode in "${mode_list[@]}"; do
            out_dir=$(out_dir "${board_config}" "${mode}")

            if [[ "${build}" == true ]]; then
                if [[ "${silent}" == true ]]; then
                    display_current_build "${board_config}" "all" "${mode}"
                    build_all "${board_config}" "true" "${mode}" &> /dev/null
                else
                    build_all "${board_config}" "true" "${mode}"
                fi
            fi
            ! [ -d "${aosp}/${binaries_path}" ] && mkdir -p "${aosp}/${binaries_path}"
            copy_binaries "${out_dir}" "${aosp}/${binaries_path}" "${board_config}" "${mode}"

            # Build Trusted Applications (TI K3 only)
            case "${plat}" in
                k3|am62*|am64*|am67*)
                    optee_ta_path=$(config_value "${board_config}" optee.optee_ta_path)
                    if [ -n "${optee_ta_path}" ]; then
                        mkdir -p "${aosp}/${optee_ta_path}"
                        if [[ "${silent}" == true ]]; then
                            build_android_ta "${board_config}" "true" "${mode}" &> /dev/null
                        else
                            build_android_ta "${board_config}" "true" "${mode}"
                        fi
                        pushd "${out_dir}/optee-ta/"
                        mkdir -p "${aosp}/${optee_ta_path}/${mode}"
                        cp -r * "${aosp}/${optee_ta_path}/${mode}"
                        popd
                    fi
                    ;;
            esac
        done
        commit_title_prefix=$(board_name ${board_config})
        add_commit_msg commits_msg "${commit_title_prefix}" "${aosp}/${binaries_path}"

    done
    popd

    for abspath in "${!commits_msg[@]}"; do
        commit_title_prefix="${commits_msg[${abspath}]}"
        # we need the project name for commit_binaries(), not the
        # full filepath
        to_project=${abspath#${aosp}/}

        if [ "${commit}" == true ]; then
            commit_binaries --from-repo="${ROOT}" --from-projects="${PROJECTS_AIOT[*]}" \
                            --from-remotes="${PROJECTS_REMOTES}" \
                            --to-repo="${aosp}" --to-project="${to_project}" \
                            --title-prefix="${commit_title_prefix}"
        else
            commit_binaries --from-repo="${ROOT}" --from-projects="${PROJECTS_AIOT[*]}" \
                            --from-remotes="${PROJECTS_REMOTES}" \
                            --to-repo="${aosp}" --to-project="${to_project}" \
                            --title-prefix="${commit_title_prefix}" \
                            --dry-run
        fi
    done
}

main "$@"
