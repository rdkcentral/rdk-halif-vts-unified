#!/bin/bash

set -e

##############################################################################
# Arguments
##############################################################################

TARGET="linux"
VARIANT="C"

for arg in "$@"
do
    case $arg in
        TARGET=*|target=*)
            TARGET="${arg#*=}"
            ;;
        VARIANT=*|variant=*)
            VARIANT="${arg#*=}"
            ;;
    esac
done

##############################################################################
# Paths
##############################################################################

ROOT_DIR=$(pwd)

MANIFEST_FILE="${ROOT_DIR}/manifest.xml"
WORKSPACE_DIR="${ROOT_DIR}/vts_hal_test_components"
UT_CORE_DIR="${ROOT_DIR}/ut-core"

UNIFIED_SRC_DIR="${ROOT_DIR}/src"
BUILD_DIR="${ROOT_DIR}/build"

##############################################################################
# UT-Core Version
##############################################################################

UT_CORE_DEFAULT_VERSION="5.0.0"

##############################################################################
# Validation
##############################################################################

if [ ! -f "${MANIFEST_FILE}" ]; then
    echo "ERROR: manifest.xml not found"
    exit 1
fi

mkdir -p "${WORKSPACE_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${UNIFIED_SRC_DIR}"

##############################################################################
# Banner
##############################################################################

echo "========================================="
echo "Unified HALIF Build"
echo "TARGET  : ${TARGET}"
echo "VARIANT : ${VARIANT}"
echo "UT-Core : ${UT_CORE_DEFAULT_VERSION}"
echo "========================================="

##############################################################################
# Parse Manifest
##############################################################################

declare -A PROJECT_PATHS
declare -A PROJECT_REVISIONS

HAL_REPOS=$(
grep 'groups="hal"' "${MANIFEST_FILE}" |
sed -n 's/.*path="\([^"]*\)".*/\1/p'
)

TEST_REPOS=$(
grep 'groups="test"' "${MANIFEST_FILE}" |
sed -n 's/.*path="\([^"]*\)".*/\1/p'
)

while read -r line
do
    PROJECT_NAME=$(echo "$line" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
    PROJECT_PATH=$(echo "$line" | sed -n 's/.*path="\([^"]*\)".*/\1/p')
    PROJECT_REVISION=$(echo "$line" | sed -n 's/.*revision="\([^"]*\)".*/\1/p')

    PROJECT_PATHS["${PROJECT_NAME}"]="${PROJECT_PATH}"
    PROJECT_REVISIONS["${PROJECT_NAME}"]="${PROJECT_REVISION}"

done < <(grep "<project" "${MANIFEST_FILE}")

##############################################################################
# Repository Synchronization
##############################################################################

echo
echo "========================================="
echo "Repository Synchronization"
echo "========================================="

for PROJECT in "${!PROJECT_PATHS[@]}"
do
    REPO_PATH="${PROJECT_PATHS[$PROJECT]}"
    REPO_REVISION="${PROJECT_REVISIONS[$PROJECT]}"

    REPO_DIR="${WORKSPACE_DIR}/${REPO_PATH}"

    echo
    echo "-----------------------------------------"
    echo "Repository : ${PROJECT}"
    echo "Path       : ${REPO_PATH}"
    echo "Revision   : ${REPO_REVISION}"
    echo "-----------------------------------------"

    if [ ! -d "${REPO_DIR}" ]; then
        git clone \
            "https://github.com/rdkcentral/${PROJECT}.git" \
            "${REPO_DIR}"
    fi

    (
        cd "${REPO_DIR}"

        git fetch --all --tags

        if [ -n "${REPO_REVISION}" ]; then
            git checkout -f "${REPO_REVISION}"
        else
            git pull --ff-only || true
        fi
    )
done

##############################################################################
# UT-Core
##############################################################################

echo
echo "========================================="
echo "UT-Core"
echo "========================================="

if [ ! -d "${UT_CORE_DIR}" ]; then
    git clone \
        https://github.com/rdkcentral/ut-core.git \
        "${UT_CORE_DIR}"
fi

(
    cd "${UT_CORE_DIR}"

    git fetch --all --tags

    git checkout "${UT_CORE_DEFAULT_VERSION}"
)

echo
echo "UT-Core Version:"
git -C "${UT_CORE_DIR}" describe --tags


##############################################################################
# Source Discovery
##############################################################################

SRC_DIRS="${UNIFIED_SRC_DIR}"
INC_DIRS=""

##############################################################################
# Process Test Repositories
##############################################################################

for repo in ${TEST_REPOS}
do
    REPO_PATH="${WORKSPACE_DIR}/${repo}"

    echo
    echo "Processing ${repo}"

    #
    # Remove standalone main
    #
    rm -f "${REPO_PATH}/src/main.c"

    #
    # Rename UT_register_tests()
    #
    if [ -f "${REPO_PATH}/src/test_register.c" ]; then

        UNIQUE_FUNC=$(basename "${repo}" | tr '-' '_')_register_tests

        sed -i \
            "s/\<UT_register_tests\>/${UNIQUE_FUNC}/g" \
            "${REPO_PATH}/src/test_register.c"

        REGISTER_DECLS="${REGISTER_DECLS}
    extern int ${UNIQUE_FUNC}(void);"

        REGISTER_CALLS="${REGISTER_CALLS}
        ${UNIQUE_FUNC}();"

        echo "Register Function: ${UNIQUE_FUNC}"
    fi

    if [ -d "${REPO_PATH}/src" ]; then
        SRC_DIRS="${SRC_DIRS} ${REPO_PATH}/src"
    fi

    if [ -d "${REPO_PATH}/skeletons/src" ]; then
        SRC_DIRS="${SRC_DIRS} ${REPO_PATH}/skeletons/src"
    fi
done


##############################################################################
# Include Discovery
##############################################################################

for repo in ${HAL_REPOS} ${TEST_REPOS}
do
    REPO_PATH="${WORKSPACE_DIR}/${repo}"

    for dir in \
        include \
        src \
        skeletons/src
    do
        if [ -d "${REPO_PATH}/${dir}" ]; then

            INC_DIRS="${INC_DIRS} ${REPO_PATH}/${dir}"

            echo "Include Path Added: ${REPO_PATH}/${dir}"
        fi
    done
done

##############################################################################
# UT-Core Includes
##############################################################################

INC_DIRS="${INC_DIRS} ${UT_CORE_DIR}/include"

if [ -d "${UT_CORE_DIR}/framework/CUnit-2.1-3/CUnit/Headers" ]; then
    INC_DIRS="${INC_DIRS} ${UT_CORE_DIR}/framework/CUnit-2.1-3/CUnit/Headers"
fi

if [ -d "${UT_CORE_DIR}/framework/ut-control/include" ]; then
    INC_DIRS="${INC_DIRS} ${UT_CORE_DIR}/framework/ut-control/include"
fi

INC_DIRS="${INC_DIRS} ${UNIFIED_SRC_DIR}"

##############################################################################
# Export Variables
##############################################################################

export SRC_DIRS
export INC_DIRS

export EXCLUDE_SRCS="main.c"

export TARGET
export TOP_DIR="${ROOT_DIR}"

export BIN_DIR="${BUILD_DIR}/bin"

export KCFLAGS="-DHALIF_UNIFIED"

##############################################################################
# Debug
##############################################################################

echo
echo "========================================="
echo "Generated Sources"
echo "========================================="

find "${UNIFIED_SRC_DIR}" -name "*.c"

echo
echo "========================================="
echo "SRC_DIRS"
echo "========================================="

printf "%s\n" ${SRC_DIRS}

echo
echo "========================================="
echo "INC_DIRS"
echo "========================================="

printf "%s\n" ${INC_DIRS}

##############################################################################
# Build
##############################################################################

echo
echo "========================================="
echo "Building Unified HALIF"
echo "========================================="

make TARGET=${TARGET} VARIANT=${VARIANT}

##############################################################################
# Complete
##############################################################################

echo
echo "========================================="
echo "Build Complete"
echo "========================================="