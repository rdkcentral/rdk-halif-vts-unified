#!/bin/bash

set -e

##############################################################################
# Defaults
##############################################################################

TARGET="linux"
VARIANT="C"

SUPPORTED_TARGETS="linux arm"

UT_CORE_DEFAULT_VERSION="5.0.0"

PROFILE_TYPE="sink"

##############################################################################
# Argument Functions
##############################################################################

parse_arguments()
{
    for arg in "$@"
    do
        case $arg in
            TARGET=*|target=*)
                TARGET="${arg#*=}"
                ;;
            VARIANT=*|variant=*)
                VARIANT="${arg#*=}"
                ;;
            PROFILE=*|profile=*)
                PROFILE_TYPE="${arg#*=}"
                ;;
        esac
    done
}

validate_target()
{
    case "${TARGET}" in
        linux|arm)
            ;;
        *)
            echo "ERROR: Unsupported TARGET=${TARGET}"
            exit 1
            ;;
    esac

    case "${PROFILE_TYPE}" in
        sink|source)
            ;;
        *)
            echo "ERROR: Unsupported PROFILE=${PROFILE_TYPE}"
            echo "Valid values: sink source"
            exit 1
            ;;
    esac
}

##############################################################################
# Initialization
##############################################################################

initialize_paths()
{
    ROOT_DIR=$(pwd)

    MANIFEST_FILE="${ROOT_DIR}/manifest.xml"

    WORKSPACE_DIR="${ROOT_DIR}/vts_hal_test_components"
    UT_CORE_DIR="${ROOT_DIR}/ut-core"

    UNIFIED_SRC_DIR="${ROOT_DIR}/src"
    BUILD_DIR="${ROOT_DIR}/build"

    PROFILE_DIR="${ROOT_DIR}/profiles"
    UNIFIED_PROFILE="${PROFILE_DIR}/unified_hal_profile.yaml"

    mkdir -p "${PROFILE_DIR}"

    mkdir -p "${WORKSPACE_DIR}"
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${UNIFIED_SRC_DIR}"
}

validate_inputs()
{
    if [ ! -f "${MANIFEST_FILE}" ]; then
        echo "ERROR: manifest.xml not found"
        exit 1
    fi
}

##############################################################################
# Banner
##############################################################################

print_banner()
{
    echo "========================================="
    echo "Unified HALIF Build"
    echo "TARGET     : ${TARGET}"
    echo "VARIANT    : ${VARIANT}"
    echo "UT-Core    : ${UT_CORE_DEFAULT_VERSION}"

    if [ "${TARGET}" = "arm" ]; then
        echo "Build Mode : ARM"
    else
        echo "Build Mode : Linux Host"
    fi

    echo "========================================="
}

##############################################################################
# Manifest Parsing
##############################################################################

parse_manifest()
{
    declare -gA PROJECT_PATHS
    declare -gA PROJECT_REVISIONS

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
}

##############################################################################
# Repository Synchronization
##############################################################################

sync_repository()
{
    local project="$1"
    local repo_path="$2"
    local revision="$3"

    local repo_dir="${WORKSPACE_DIR}/${repo_path}"

    echo
    echo "-----------------------------------------"
    echo "Repository : ${project}"
    echo "Path       : ${repo_path}"
    echo "Revision   : ${revision}"
    echo "-----------------------------------------"

    if [ ! -d "${repo_dir}" ]; then

        git clone \
            "https://github.com/rdkcentral/${project}.git" \
            "${repo_dir}"
    fi

    (
        cd "${repo_dir}"

        git fetch --all --tags

        if [ -n "${revision}" ]; then
            git checkout -f "${revision}"
        else
            git pull --ff-only || true
        fi
    )
}

sync_repositories()
{
    echo
    echo "========================================="
    echo "Repository Synchronization"
    echo "========================================="

    for PROJECT in "${!PROJECT_PATHS[@]}"
    do
        sync_repository \
            "${PROJECT}" \
            "${PROJECT_PATHS[$PROJECT]}" \
            "${PROJECT_REVISIONS[$PROJECT]}"
    done
}

##############################################################################
# UT-Core Setup
##############################################################################

setup_ut_core()
{
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
}

##############################################################################
# Repository Processing
##############################################################################

remove_standalone_main()
{
    local repo_path="$1"

    rm -f "${repo_path}/src/main.c"
}

register_test_suite()
{
    local repo="$1"
    local repo_path="$2"

    if [ ! -f "${repo_path}/src/test_register.c" ]; then
        return
    fi

    local unique_func

    unique_func=$(basename "${repo}" | tr '-' '_')_register_tests

    sed -i \
        "s/\<UT_register_tests\>/${unique_func}/g" \
        "${repo_path}/src/test_register.c"

    REGISTER_DECLS="${REGISTER_DECLS}
extern int ${unique_func}(void);"

    REGISTER_CALLS="${REGISTER_CALLS}
    ${unique_func}();"

    echo "Register Function : ${unique_func}"
}

add_source_directories()
{
    local repo_path="$1"

    if [ -d "${repo_path}/src" ]; then
        SRC_DIRS="${SRC_DIRS} ${repo_path}/src"
    fi

    if [ -d "${repo_path}/skeletons/src" ]; then
        SRC_DIRS="${SRC_DIRS} ${repo_path}/skeletons/src"
    fi
}

process_single_repository()
{
    local repo="$1"

    local repo_path="${WORKSPACE_DIR}/${repo}"

    echo
    echo "Processing ${repo}"

    remove_standalone_main "${repo_path}"

    register_test_suite \
        "${repo}" \
        "${repo_path}"

    add_source_directories \
        "${repo_path}"
}

process_test_repositories()
{
    REGISTER_DECLS=""
    REGISTER_CALLS=""

    SRC_DIRS="${UNIFIED_SRC_DIR}"
    INC_DIRS=""

    for repo in ${TEST_REPOS}
    do
        process_single_repository "${repo}"
    done
}

##############################################################################
# Include Discovery
##############################################################################

add_include_directory()
{
    local path="$1"

    if [ -d "${path}" ]; then

        INC_DIRS="${INC_DIRS} ${path}"

        echo "Include Path Added: ${path}"
    fi
}

discover_include_paths()
{
    for repo in ${HAL_REPOS} ${TEST_REPOS}
    do
        REPO_PATH="${WORKSPACE_DIR}/${repo}"

        add_include_directory "${REPO_PATH}/include"
        add_include_directory "${REPO_PATH}/src"
        add_include_directory "${REPO_PATH}/skeletons/src"
    done
}

add_utcore_include_paths()
{
    INC_DIRS="${INC_DIRS} ${UT_CORE_DIR}/include"

    if [ -d "${UT_CORE_DIR}/framework/CUnit-2.1-3/CUnit/Headers" ]; then
        INC_DIRS="${INC_DIRS} ${UT_CORE_DIR}/framework/CUnit-2.1-3/CUnit/Headers"
    fi

    if [ -d "${UT_CORE_DIR}/framework/ut-control/include" ]; then
        INC_DIRS="${INC_DIRS} ${UT_CORE_DIR}/framework/ut-control/include"
    fi

    INC_DIRS="${INC_DIRS} ${UNIFIED_SRC_DIR}"
}

##############################################################################
# Profile Generation
##############################################################################

validate_component_profile()
{
    local yaml_file="$1"

    if [ ! -f "${yaml_file}" ]; then
        echo "ERROR: Missing profile: ${yaml_file}"
        return 1
    fi

    if ! grep -Eq '^[A-Za-z_][A-Za-z0-9_-]*:' "${yaml_file}"; then
        echo "WARN: Profile does not look like a valid YAML root: ${yaml_file}"
        return 1
    fi

    return 0
}

generate_unified_profile()
{
    echo
    echo "========================================="
    echo "Generating Unified HALIF Profile"
    echo "PROFILE_TYPE : ${PROFILE_TYPE}"
    echo "========================================="

    mkdir -p "${PROFILE_DIR}"
    : > "${UNIFIED_PROFILE}"

    declare -A SEEN_ROOT_KEYS

    for repo in ${TEST_REPOS}
    do
        REPO_PATH="${WORKSPACE_DIR}/${repo}"
        PROFILE_PATH="${REPO_PATH}/profiles/${PROFILE_TYPE}"

        [ ! -d "${PROFILE_PATH}" ] && continue

        while read -r yaml
        do
            validate_component_profile "${yaml}" || continue

            ROOT_KEY=$(
                grep -E '^[A-Za-z_][A-Za-z0-9_-]*:' "${yaml}" \
                | head -n 1 \
                | cut -d: -f1
            )

            if [ -n "${ROOT_KEY}" ] && [ -n "${SEEN_ROOT_KEYS[$ROOT_KEY]+x}" ]; then
                echo
                echo "Skipping duplicate root key:"
                echo "  Key  : ${ROOT_KEY}"
                echo "  File : ${yaml}"
                continue
            fi

            if [ -n "${ROOT_KEY}" ]; then
                SEEN_ROOT_KEYS["${ROOT_KEY}"]="${yaml}"
            fi

            echo "# ===================================================" \
                >> "${UNIFIED_PROFILE}"

            echo "# ${yaml}" \
                >> "${UNIFIED_PROFILE}"

            echo "# ===================================================" \
                >> "${UNIFIED_PROFILE}"

            cat "${yaml}" \
                >> "${UNIFIED_PROFILE}"

            echo "" \
                >> "${UNIFIED_PROFILE}"

        done < <(
            find "${PROFILE_PATH}" \
                -type f \
                -name "*.yaml" \
                | sort
        )
    done

    if [ ! -s "${UNIFIED_PROFILE}" ]; then
        echo "WARN: no valid component profiles found for PROFILE=${PROFILE_TYPE}"
    fi

    echo
    echo "Generated Profile:"
    echo "  ${UNIFIED_PROFILE}"
}

##############################################################################
# Target Configuration
##############################################################################

configure_arm_target()
{
    echo
    echo "========================================="
    echo "ARM Build Configuration"
    echo "========================================="

    #
    # Use SDK environment if already sourced
    #
    if [ -n "${CC}" ]; then

        echo "Using SDK compiler configuration"

    else

        #
        # Fallback for standalone toolchain
        #
        export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}

        export CC=${CROSS_COMPILE}gcc
        export CXX=${CROSS_COMPILE}g++
        export AR=${CROSS_COMPILE}ar
        export LD=${CROSS_COMPILE}ld
        export STRIP=${CROSS_COMPILE}strip
    fi

    echo "CC=${CC}"
    echo "CXX=${CXX}"
    echo "AR=${AR}"
    echo "LD=${LD}"

    export KCFLAGS="${KCFLAGS} -DTARGET_ARM"
}

configure_linux_target()
{
    export CC=${CC:-gcc}
    export CXX=${CXX:-g++}
    export AR=${AR:-ar}
    export LD=${LD:-ld}

    export KCFLAGS="${KCFLAGS} -DTARGET_LINUX"
}

configure_target()
{
    export KCFLAGS="-DHALIF_UNIFIED"

    if [ "${TARGET}" = "arm" ]; then
        configure_arm_target
    else
        configure_linux_target
    fi
}

##############################################################################
# Export Environment
##############################################################################

export_build_variables()
{
    export SRC_DIRS
    export INC_DIRS

    export EXCLUDE_SRCS="main.c"

    export TARGET
    export TOP_DIR="${ROOT_DIR}"

    export BIN_DIR="${BUILD_DIR}/bin"
}

##############################################################################
# Debug
##############################################################################

print_debug_information()
{
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

    echo
    echo "========================================="
    echo "Compiler Configuration"
    echo "========================================="

    echo "CC=${CC:-Not Set}"
    echo "CXX=${CXX:-Not Set}"
    echo "AR=${AR:-Not Set}"
    echo "LD=${LD:-Not Set}"
    echo "CROSS_COMPILE=${CROSS_COMPILE:-SDK Managed}"
}

##############################################################################
# Build
##############################################################################

build_project()
{
    echo
    echo "========================================="
    echo "Building Unified HALIF"
    echo "========================================="

    make TARGET=${TARGET} VARIANT=${VARIANT}
}

##############################################################################
# Launcher
##############################################################################

generate_launcher()
{
cat > "${BIN_DIR}/run_hal_test.sh" << EOF
#!/bin/bash

RUN_DIR=\$(realpath "\$(dirname "\$0")")
PROJECT_ROOT=\$(realpath "\${RUN_DIR}/../..")
PROFILE_FILES=()

for profile in "\${PROJECT_ROOT}"/vts_hal_test_components/*/profiles/${PROFILE_TYPE}/*.yaml; do
    [ -f "\${profile}" ] || continue
    PROFILE_FILES+=("\${profile}")
done

if [ \${#PROFILE_FILES[@]} -eq 0 ]; then
    echo "No profile files found for profile type: ${PROFILE_TYPE}"
    echo "Checked path: \${PROJECT_ROOT}/vts_hal_test_components/*/profiles/${PROFILE_TYPE}/*.yaml"
    exit 1
fi

export LD_LIBRARY_PATH="\${RUN_DIR}/lib:\${RUN_DIR}:/usr/lib:/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

echo "Using Profiles:"
printf '%s\n' "\${PROFILE_FILES[@]}"

CMD=("\${RUN_DIR}/hal_test")
for profile in "\${PROFILE_FILES[@]}"; do
    CMD+=("-p" "\${profile}")
done

exec "\${CMD[@]}" "\$@"
EOF

chmod +x "${BIN_DIR}/run_hal_test.sh"
}

##############################################################################
# Main
##############################################################################

main()
{
    parse_arguments "$@"

    validate_target

    initialize_paths
    validate_inputs

    print_banner

    parse_manifest

    sync_repositories

    setup_ut_core

    process_test_repositories

    discover_include_paths
    add_utcore_include_paths

    generate_unified_profile

    configure_target

    export_build_variables

    print_debug_information

    build_project

    generate_launcher

    echo
    echo "========================================="
    echo "Build Complete"
    echo "========================================="
}

main "$@"