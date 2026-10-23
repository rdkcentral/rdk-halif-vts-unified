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

GEN_DIR="${ROOT_DIR}/generated"
UNIFIED_SRC_DIR="${GEN_DIR}/unified_sources"

BUILD_DIR="${ROOT_DIR}/build"

##############################################################################
# UT-Core Version
##############################################################################

UT_CORE_DEFAULT_VERSION="4.0.0"

##############################################################################
# Validation
##############################################################################

if [ ! -f "${MANIFEST_FILE}" ]; then
    echo "ERROR: manifest.xml not found"
    exit 1
fi

mkdir -p "${WORKSPACE_DIR}"
mkdir -p "${GEN_DIR}"
mkdir -p "${BUILD_DIR}"

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

PROJECTS=$(
grep "<project" "${MANIFEST_FILE}" \
| sed -n 's/.*name="\([^"]*\)".*/\1/p'
)

HAL_REPOS=$(
grep 'groups="hal"' "${MANIFEST_FILE}" \
| sed -n 's/.*path="\([^"]*\)".*/\1/p'
)

TEST_REPOS=$(
grep 'groups="test"' "${MANIFEST_FILE}" \
| sed -n 's/.*path="\([^"]*\)".*/\1/p'
)

##############################################################################
# Repository Sync
##############################################################################

echo ""
echo "========================================="
echo "Repository Synchronization"
echo "========================================="

mkdir -p "${WORKSPACE_DIR}"

for repo in ${PROJECTS}
do
    REPO_DIR="${WORKSPACE_DIR}/${repo}"

    if [ ! -d "${REPO_DIR}" ]; then

        echo "Cloning ${repo}"

        git clone \
            "https://github.com/rdkcentral/${repo}.git" \
            "${REPO_DIR}"

    else

        echo "Updating ${repo}"

        git -C "${REPO_DIR}" pull --ff-only || true

    fi
done

##############################################################################
# UT-Core
##############################################################################

echo ""
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

echo ""
echo "UT-Core Version:"
git -C "${UT_CORE_DIR}" describe --tags

##############################################################################
# Prepare Unified Workspace
##############################################################################

rm -rf "${UNIFIED_SRC_DIR}"
mkdir -p "${UNIFIED_SRC_DIR}"

SRC_DIRS=""
INC_DIRS=""

##############################################################################
# Test Repositories
##############################################################################

for repo in ${TEST_REPOS}
do
    REPO_PATH="${WORKSPACE_DIR}/${repo}"

    echo "Processing ${repo}"

    #
    # Add source folder as include path
    #
    if [ -d "${REPO_PATH}/src" ]; then

        INC_DIRS="${INC_DIRS} ${REPO_PATH}/src"

        #
        # Copy source files except main.c/test_register.c
        #
        find "${REPO_PATH}/src" \
            -name "*.c" \
            ! -name "main.c" \
            ! -name "test_register.c" \
            -exec cp {} "${UNIFIED_SRC_DIR}" \;

        #
        # Copy local headers
        #
        find "${REPO_PATH}/src" \
            -name "*.h" \
            -exec cp {} "${UNIFIED_SRC_DIR}" \;
    fi

    if [ -d "${REPO_PATH}/skeletons/src" ]; then

        find "${REPO_PATH}/skeletons/src" \
            -name "*.c" \
            -exec cp {} "${UNIFIED_SRC_DIR}" \;

        find "${REPO_PATH}/skeletons/src" \
            -name "*.h" \
            -exec cp {} "${UNIFIED_SRC_DIR}" \;
    fi

    if [ -d "${REPO_PATH}/include" ]; then
        INC_DIRS="${INC_DIRS} ${REPO_PATH}/include"
    fi

    if [ -d "${REPO_PATH}/ut-core/test_include" ]; then
        INC_DIRS="${INC_DIRS} ${REPO_PATH}/ut-core/test_include"
    fi
done

##############################################################################
# HAL Repositories
##############################################################################

for repo in ${HAL_REPOS}
do
    REPO_PATH="${WORKSPACE_DIR}/${repo}"

    if [ -d "${REPO_PATH}/include" ]; then
        INC_DIRS="${INC_DIRS} ${REPO_PATH}/include"
    fi

    if [ -d "${REPO_PATH}/src" ]; then
        INC_DIRS="${INC_DIRS} ${REPO_PATH}/src"
    fi
done

##############################################################################
# Generate Unified Main
##############################################################################

cat > "${UNIFIED_SRC_DIR}/unified_main.c" << 'EOF'
#include <ut.h>

extern void UT_register_tests(void);

int main(int argc, char **argv)
{
    UT_init(argc, argv);

    UT_register_tests();

    UT_run_tests();

    UT_exit();

    return 0;
}
EOF

##############################################################################
# Generate Unified Registration
##############################################################################

REGISTER_FILE="${UNIFIED_SRC_DIR}/unified_test_register.c"

echo '#include <ut.h>' > "${REGISTER_FILE}"
echo "" >> "${REGISTER_FILE}"

REG_FUNCS=""
REG_CALLS=""

echo ""
echo "========================================="
echo "Generating Unified Registration"
echo "========================================="

for repo in ${TEST_REPOS}
do
    REPO_PATH="${WORKSPACE_DIR}/${repo}"

    while IFS= read -r src
    do

        FUNC=$(grep -hoE \
            'void[[:space:]]+[A-Za-z0-9_]+[[:space:]]*\(' \
            "${src}" 2>/dev/null \
            | grep "_register" \
            | sed -E 's/void[[:space:]]+//' \
            | sed 's/[[:space:]]*(//' \
            | head -1)

        if [ -n "${FUNC}" ]; then

            REG_FUNCS="${REG_FUNCS}extern void ${FUNC}(void);\n"
            REG_CALLS="${REG_CALLS}    ${FUNC}();\n"

            echo "Found ${FUNC}"
        fi

    done < <(
        find "${REPO_PATH}/src" \
            -name "*.c" \
            ! -name "main.c" \
            ! -name "test_register.c"
    )

done

printf "%b\n" "${REG_FUNCS}" >> "${REGISTER_FILE}"

cat >> "${REGISTER_FILE}" << 'EOF'

void UT_register_tests(void)
{
EOF

printf "%b" "${REG_CALLS}" >> "${REGISTER_FILE}"

cat >> "${REGISTER_FILE}" << 'EOF'
}
EOF

##############################################################################
# Final Source/Include Directories
##############################################################################

SRC_DIRS="${UNIFIED_SRC_DIR}"
INC_DIRS="${INC_DIRS} ${UNIFIED_SRC_DIR}"

##############################################################################
# Debug
##############################################################################

echo ""
echo "========================================="
echo "Unified Sources"
echo "========================================="

find "${UNIFIED_SRC_DIR}" -name "*.c"

echo ""
echo "========================================="
echo "SRC_DIRS"
echo "========================================="

printf "%s\n" ${SRC_DIRS}

echo ""
echo "========================================="
echo "INC_DIRS"
echo "========================================="

printf "%s\n" ${INC_DIRS}

##############################################################################
# Export For UT-Core
##############################################################################

export SRC_DIRS
export INC_DIRS

export TARGET
export TOP_DIR="${ROOT_DIR}"

export BIN_DIR="${BUILD_DIR}/bin"

export KCFLAGS="-DHALIF_UNIFIED"

##############################################################################
# Build
##############################################################################

echo ""
echo "========================================="
echo "Building Unified HALIF"
echo "========================================="

make TARGET=${TARGET} VARIANT=${VARIANT}

##############################################################################
# Complete
##############################################################################

echo ""
echo "========================================="
echo "Build Complete"
echo "========================================="