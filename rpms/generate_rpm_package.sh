#!/bin/bash

# Wazuh package generator
# Copyright (C) 2015-2019, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.
CURRENT_PATH="$( cd $(dirname $0) ; pwd -P )"
ARCHITECTURE="x86_64"
LEGACY="no"
OUTDIR="${CURRENT_PATH}/output/"
LOCAL_SPECS="${CURRENT_PATH}/SPECS/"
BRANCH="master"
REVISION="1"
TARGET=""
JOBS="2"
DEBUG="no"
USER_PATH="no"
SRC="no"
RPM_X86_BUILDER="rpm_builder_x86"
RPM_I386_BUILDER="rpm_builder_i386"
RPM_BUILDER_DOCKERFILE="${CURRENT_PATH}/CentOS/6"
LEGACY_RPM_X86_BUILDER="rpm_legacy_builder_x86"
LEGACY_RPM_I386_BUILDER="rpm_legacy_builder_i386"
LEGACY_RPM_BUILDER_DOCKERFILE="${CURRENT_PATH}/CentOS/5"
LEGACY_TAR_FILE="${LEGACY_RPM_BUILDER_DOCKERFILE}/i386/centos-5-i386.tar.gz"
TAR_URL="https://packages-dev.wazuh.com/utils/centos-5-i386-build/centos-5-i386.tar.gz"
INSTALLATION_PATH="/var"
PACKAGES_BRANCH="master"
CHECKSUMDIR=""
CHECKSUM="no"
USE_LOCAL_SPECS="no"

trap ctrl_c INT

if command -v curl > /dev/null 2>&1 ; then
    DOWNLOAD_TAR="curl ${TAR_URL} -o ${LEGACY_TAR_FILE} -s"
elif command -v wget > /dev/null 2>&1 ; then
    DOWNLOAD_TAR="wget ${TAR_URL} -o ${LEGACY_TAR_FILE} -q"
fi

clean() {
    exit_code=$1

    # Clean the files
    rm -rf ${DOCKERFILE_PATH}/{*.tar.gz,wazuh*} ${DOCKERFILE_PATH}/build.sh ${SOURCES_DIRECTORY}

    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

build_rpm() {
    CONTAINER_NAME="$1"
    DOCKERFILE_PATH="$2"

    # Copy the necessary files
    cp build.sh ${DOCKERFILE_PATH}

    # Download the legacy tar file if it is needed
    if [ "${CONTAINER_NAME}" = "${LEGACY_RPM_I386_BUILDER}" ] && [ ! -f "${LEGACY_TAR_FILE}" ]; then
        ${DOWNLOAD_TAR}
    fi
    # Build the Docker image
    docker build -t ${CONTAINER_NAME} ${DOCKERFILE_PATH} || return 1

    # Build the RPM package with a Docker container
    docker run -t --rm -v ${OUTDIR}:/var/local/wazuh:Z \
        -v ${CHECKSUMDIR}:/var/local/checksum:Z \
        -v ${LOCAL_SPECS}:/specs:Z \
        ${CONTAINER_NAME} ${TARGET} ${BRANCH} ${ARCHITECTURE} \
        ${JOBS} ${REVISION} ${INSTALLATION_PATH} ${DEBUG} \
        ${CHECKSUM} ${PACKAGES_BRANCH} ${USE_LOCAL_SPECS} ${SRC} || return 1

    echo "Package $(ls ${OUTDIR} -Art | tail -n 1) added to ${OUTDIR}."

    return 0
}

build() {

    if [[ ${ARCHITECTURE} == "amd64" ]] || [[ ${ARCHITECTURE} == "x86_64" ]]; then
        ARCHITECTURE="x86_64"
    fi

    if [[ "${TARGET}" == "api" ]]; then

        build_rpm ${RPM_X86_BUILDER} ${RPM_BUILDER_DOCKERFILE}/x86_64 || return 1

    elif [[ "${TARGET}" == "manager" ]] || [[ "${TARGET}" == "agent" ]]; then

        BUILD_NAME=""
        FILE_PATH=""
        if [[ "${LEGACY}" == "yes" ]] && [[ "${ARCHITECTURE}" == "x86_64" ]]; then
            REVISION="${REVISION}.el5"
            BUILD_NAME="${LEGACY_RPM_X86_BUILDER}"
            FILE_PATH="${LEGACY_RPM_BUILDER_DOCKERFILE}/${ARCHITECTURE}"
        elif [[ "${LEGACY}" == "yes" ]] && [[ "${ARCHITECTURE}" == "i386" ]]; then
            REVISION="${REVISION}.el5"
            BUILD_NAME="${LEGACY_RPM_I386_BUILDER}"
            FILE_PATH="${LEGACY_RPM_BUILDER_DOCKERFILE}/${ARCHITECTURE}"
        elif [[ "${LEGACY}" == "no" ]] && [[ "${ARCHITECTURE}" == "x86_64" ]]; then
            BUILD_NAME="${RPM_X86_BUILDER}"
            FILE_PATH="${RPM_BUILDER_DOCKERFILE}/${ARCHITECTURE}"
        elif [[ "${LEGACY}" == "no" ]] && [[ "${ARCHITECTURE}" == "i386" ]]; then
            BUILD_NAME="${RPM_I386_BUILDER}"
            FILE_PATH="${RPM_BUILDER_DOCKERFILE}/${ARCHITECTURE}"
        else
            echo "Invalid architecture. Choose: x86_64 (amd64 is accepted too) or i386"
            return 1
        fi
        build_rpm ${BUILD_NAME} ${FILE_PATH} || return 1
    else
        echo "Invalid target. Choose: manager, agent or api."
        return 1
    fi

    return 0
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "    -b, --branch <branch>        [Required] Select Git branch or tag e.g. $BRANCH"
    echo "    -t, --target <target>        [Required] Target package to build [manager/api/agent]."
    echo "    -a, --architecture <arch>    [Optional] Target architecture of the package [x86_64/i386]."
    echo "    -r, --revision <rev>         [Optional] Package revision that append to version e.g. x.x.x-rev"
    echo "    -l, --legacy                 [Optional] Build package for CentOS 5."
    echo "    -s, --store <path>           [Optional] Set the destination path of package. By default, an output folder will be created."
    echo "    -j, --jobs <number>          [Optional] Number of parallel jobs when compiling."
    echo "    -p, --path <path>            [Optional] Installation path for the package. By default: /var."
    echo "    -d, --debug                  [Optional] Build the binaries with debug symbols and create debuginfo packages. By default: no."
    echo "    -c, --checksum <path>        [Optional] Generate checksum on the desired path (by default, if no path is specified it will be generated on the same directory than the package)."
    echo "    --packages-branch <branch>   [Optional] Select Git branch or tag from wazuh-packages repository. e.g ${PACKAGES_BRANCH}"
    echo "    --dev                        [Optional] Use the SPECS files stored in the host instead of downloading them from GitHub."
    echo "    --src                        [Optional] Generate the source package in the destination directory."
    echo "    -h, --help                   Show this help."
    echo
    exit $1
}


main() {
    BUILD="no"
    while [ -n "$1" ]
    do
        case "$1" in
        "-b"|"--branch")
            if [ -n "$2" ]; then
                BRANCH="$2"
                BUILD="yes"
                shift 2
            else
                help 1
            fi
            ;;
        "-h"|"--help")
            help 0
            ;;
        "-t"|"--target")
            if [ -n "$2" ]; then
                TARGET="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-a"|"--architecture")
            if [ -n "$2" ]; then
                ARCHITECTURE="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-j"|"--jobs")
            if [ -n "$2" ]; then
                JOBS="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-r"|"--revision")
            if [ -n "$2" ]; then
                REVISION="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-p"|"--path")
            if [ -n "$2" ]; then
                INSTALLATION_PATH="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-l"|"--legacy")
            LEGACY="yes"
            shift 1
            ;;
        "-d"|"--debug")
            DEBUG="yes"
            shift 1
            ;;
        "-c"|"--checksum")
            if [ -n "$2" ]; then
                CHECKSUMDIR="$2"
                CHECKSUM="yes"
                shift 2
            else
                CHECKSUM="yes"
                shift 1
            fi
            ;;
        "-s"|"--store")
            if [ -n "$2" ]; then
                OUTDIR="$2"
                USER_PATH="yes"
                shift 2
            else
                help 1
            fi
            ;;
        "--src")
            SRC="yes"
            shift 1
            ;;
        "--packages-branch")
            if [ -n "$2" ]; then
                PACKAGES_BRANCH="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "--dev")
            USE_LOCAL_SPECS="yes"
            shift 1
            ;;
        *)
            help 1
        esac
    done

    if [[ "${USER_PATH}" == "no" ]] && [[ "${LEGACY}" == "yes" ]]; then
        OUTDIR="${OUTDIR}/5/${ARCHITECTURE}"
    fi

    if [ -z "${CHECKSUMDIR}" ]; then
        CHECKSUMDIR="${OUTDIR}"
    fi

    if [[ "$BUILD" != "no" ]]; then
        build || clean 1
    fi

    clean 0
}
main "$@"
