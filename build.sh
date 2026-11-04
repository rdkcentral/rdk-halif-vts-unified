#!/bin/bash
#* ******************************************************************************
#*  If not stated otherwise in this file or this component's LICENSE
#*  file the following copyright and licenses apply:
#*
#*  Copyright 2026 RDK Management
#*
#*  Licensed under the Apache License, Version 2.0 (the License);
#*  you may not use this file except in compliance with the License.
#*  You may obtain a copy of the License at
#*
#*  http://www.apache.org/licenses/LICENSE-2.0
#*
#*  Unless required by applicable law or agreed to in writing, software
#*  distributed under the License is distributed on an AS IS BASIS,
#*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#*  See the License for the specific language governing permissions and
#*  limitations under the License.
#*
#* 

set -e

##############################################################################
# Defaults
##############################################################################

TARGET=""
VARIANT="C"

SUPPORTED_TARGETS="linux arm"

UT_CORE_DEFAULT_VERSION="${UT_CORE_DEFAULT_VERSION:-5.0.0}"
export UT_CORE_DEFAULT_VERSION


##############################################################################
# Argument Functions
##############################################################################

# Parse command-line options and route build actions like build, clean, dist_clean, and help.
parse_arguments()
{
    for arg in "$@"
    do
        case "$arg" in
            clean)
                ACTION="clean"
                ;;
            dist_clean)
                ACTION="dist_clean"
                ;;
            TARGET=*|target=*|Target=*)
                TARGET="${arg#*=}"
                ;;
            help)
                echo "Build Script Help"
                print_usage
                exit 0
                ;;
        esac
    done
}

# Remove generated build artifacts while keeping the project source tree intact.
clean_project()
{
    echo "Cleaning build artifacts..."
    rm -rf "${ROOT_DIR:-$(pwd)}/build"
    if [ -d "${ROOT_DIR:-$(pwd)}/ut-core" ]; then
        make -C "${ROOT_DIR:-$(pwd)}/ut-core" cleanall >/dev/null 2>&1 || true
    fi
}

# Remove all generated build outputs and local dependency checkouts for a full clean slate.
dist_clean_project()
{
    clean_project
    echo "Removing framework and checked-out repositories..."
    rm -rf "${ROOT_DIR:-$(pwd)}/ut-core"
    rm -rf "${ROOT_DIR:-$(pwd)}/vts_hal_test_components"
}

# Display the supported command-line usage patterns for the build wrapper.
print_usage()
{
    echo "======================================================================================"
    echo " ./build.sh TARGET=<target>   - Builds the test for specified target (arm, linux) "
    echo " ./build.sh clean             - Cleans the build folder"
    echo " ./build.sh dist_clean        - Deletes all build and checkout folders"
    echo " ./build.sh help              - Displays this help message"
    echo "======================================================================================"
}

# Ensure the selected target is valid before continuing the build flow.
validate_target()
{
    if [ -z "${TARGET}" ]; then
        echo "Invalid Arguments"
        print_usage
        exit 1
    fi

    case "${TARGET}" in
        linux|arm)
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
}

##############################################################################
# Initialization
##############################################################################

# Initialize project directories and workspace paths used by the unified build process.
initialize_paths()
{
    ROOT_DIR=$(pwd)

    MANIFEST_FILE="${ROOT_DIR}/manifest.xml"

    WORKSPACE_DIR="${ROOT_DIR}/vts_hal_test_components"
    UT_CORE_DIR="${ROOT_DIR}/ut-core"

    UNIFIED_SRC_DIR="${ROOT_DIR}/src"
    BUILD_DIR="${ROOT_DIR}/build"

    PROFILE_DIR="${ROOT_DIR}/profiles"

    # Do not create repo-local profile directories under the project root.
    # Runtime profiles are generated only under build/bin/profiles and are used
    # as the source of truth during execution.
    mkdir -p "${WORKSPACE_DIR}"
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${UNIFIED_SRC_DIR}"
}

# Check required project files are present before starting the build.
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

# Print the build banner with target, variant, and UT-Core version details.
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

# Read manifest.xml and collect repo names, paths, and revision metadata for synchronization.
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

# Clone or skip a manifest-defined repo based on whether it already exists locally.
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

    if [ -d "${repo_dir}" ] && git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Repository already exists in ${repo_dir}; skipping resync for rebuild."
        return
    fi

    git clone \
        "https://github.com/rdkcentral/${project}.git" \
        "${repo_dir}"

    if [ -n "${revision}" ]; then
        (
            cd "${repo_dir}"
            git checkout -f "${revision}"
        )
    fi
}

# Synchronize all repos listed in manifest.xml into the workspace.
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

# Normalize helper function declarations across cloned test sources to avoid duplicate symbol linkage.
normalize_read_and_discard_helper()
{
    if [ ! -d "${WORKSPACE_DIR}" ]; then
        return
    fi

    while IFS= read -r source_file; do
        [ -n "${source_file}" ] || continue

        if grep -Eq '^[[:space:]]*void[[:space:]]+readAndDiscardRestOfLine[[:space:]]*\([[:space:]]*FILE[[:space:]]*\*[[:space:]]*in[[:space:]]*\)' "${source_file}"; then
            sed -i -E 's/^[[:space:]]*void[[:space:]]+readAndDiscardRestOfLine[[:space:]]*\([[:space:]]*FILE[[:space:]]*\*[[:space:]]*in[[:space:]]*\)/static void readAndDiscardRestOfLine(FILE *in)/' "${source_file}"
            echo "Normalized readAndDiscardRestOfLine in ${source_file}"
        fi
    done < <(find "${WORKSPACE_DIR}" -type f \( -name "*.c" -o -name "*.h" \) -print)
}

##############################################################################
# UT-Core Setup
##############################################################################

# Ensure the UT-Core framework is present and checked out to the configured version.
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

# Remove a standalone main.c from component repos so the unified test binary remains the only entry point.
remove_standalone_main()
{
    local repo_path="$1"

    rm -f "${repo_path}/src/main.c"
}

# Rename and register each repository test suite function in the generated test harness.
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

# Add repo source folders to the final source list for compilation.
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

# Perform repo-specific preparation: remove standalone main and register tests for one repo.
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

# Prepare all manifest test repos for unified compilation by registering source directories.
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

# Add a valid include path to the global compile include list when it exists.
add_include_directory()
{
    local path="$1"

    if [ -d "${path}" ]; then

        INC_DIRS="${INC_DIRS} ${path}"

        echo "Include Path Added: ${path}"
    fi
}

# Discover include directories across HAL and test repos for the unified build.
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

# Add the required UT-Core headers and framework headers to the compiler include path.
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

# Validate a YAML profile file before copying or including it in the runtime profile set.
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

# Copy component profile YAML files into a consolidated repo-local profile directory.
: 'copy_component_profiles()
{
    local profile_type="$1"
    local target_dir="${ROOT_DIR}/profiles/${profile_type}"

    mkdir -p "${target_dir}"

    for repo in ${TEST_REPOS}
    do
        local repo_path="${WORKSPACE_DIR}/${repo}"
        local source_dir="${repo_path}/profiles/${profile_type}"

        [ ! -d "${source_dir}" ] && continue

        while read -r yaml
        do
            validate_component_profile "${yaml}" || continue
            cp -f "${yaml}" "${target_dir}/$(basename "${yaml}")"
        done < <(
            find "${source_dir}" \
                -type f \
                \( -name "*.yaml" -o -name "*.yml" \) \
                | sort
        )
    done
}'

# Declare that unified runtime profiles are generated only under build/bin/profiles.
generate_unified_profile()
{
    echo
    echo "========================================="
    echo "Skipping repo-local unified profile generation"
    echo "Runtime YAMLs are generated only under build/bin/profiles"
    echo "========================================="
}

# Trigger the runtime profile-generation step for the build configuration.
generate_all_profile_sets()
{
    generate_unified_profile
}

##############################################################################
# Target Configuration
##############################################################################

# Configure compiler and flags for ARM builds using the selected toolchain.
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

# Configure compiler and flags for Linux host builds.
configure_linux_target()
{
    export CC=${CC:-gcc}
    export CXX=${CXX:-g++}
    export AR=${AR:-ar}
    export LD=${LD:-ld}

    export KCFLAGS="${KCFLAGS} -DTARGET_LINUX"
}

# Select the correct target-specific build configuration before compilation.
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

# Export the collected source/include lists and build metadata to the Make build process.
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

# Print build-time source/include and compiler details for debugging validation.
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

# Create a unified runtime profile YAML under build/bin/profiles with include_* file references.
generate_runtime_unified_profile()
{
    local profile_type="$1"
    local runtime_dir="${BIN_DIR}/profiles/${profile_type}"
    local unified_profile="${runtime_dir}/unified_${profile_type}_hal_profile.yaml"

    mkdir -p "${runtime_dir}"

    : > "${unified_profile}"

    cat > "${unified_profile}" << EOF
# Unified HALIF profile generated by pars/build.sh
# This file uses the include_* pattern supported by the UT KVP parser.
# It does not flatten component YAML files into one monolithic file.

Hal_Unified:
  profile: ${profile_type}
EOF

    local include_index=0
    local yaml_count=0

    while read -r yaml
    do
        [ -n "${yaml}" ] || continue

        validate_component_profile "${yaml}" || continue

        if [ "${yaml}" = "${unified_profile}" ]; then
            continue
        fi

        local rel_path
        rel_path=$(realpath --relative-to="${ROOT_DIR}" "${yaml}")

        echo "include_${include_index}: ${rel_path}" >> "${unified_profile}"
        include_index=$((include_index + 1))
        yaml_count=$((yaml_count + 1))
    done < <(
        find "${runtime_dir}" \
            -type f \
            ! -name "$(basename "${unified_profile}")" \
            \( -name "*.yaml" -o -name "*.yml" \) \
            | sort
    )

    echo "Generated runtime profile: ${unified_profile}"
    echo "Includes: ${yaml_count} profile files"
}

# Copy all component profile YAMLs into build/bin/profiles and generate the runtime unified profile files.
copy_profiles_to_bin()
{
    local dst_profiles="${BIN_DIR}/profiles"

    mkdir -p "${dst_profiles}"

    for profile_type in sink source
    do
        local dst_profile_dir="${dst_profiles}/${profile_type}"
        mkdir -p "${dst_profile_dir}"

        for repo in ${TEST_REPOS}
        do
            local repo_path="${WORKSPACE_DIR}/${repo}"
            local source_dir="${repo_path}/profiles/${profile_type}"

            [ ! -d "${source_dir}" ] && continue

            while read -r yaml
            do
                validate_component_profile "${yaml}" || continue
                cp -f "${yaml}" "${dst_profile_dir}/$(basename "${yaml}")"
            done < <(
                find "${source_dir}" \
                    -type f \
                    \( -name "*.yaml" -o -name "*.yml" \) \
                    | sort
            )
        done

        generate_runtime_unified_profile "${profile_type}"
    done

    echo "Copied profiles into: ${dst_profiles}"
}

# Invoke the actual Make-based unified HAL build for the selected target and variant.
build_project()
{
    echo
    echo "========================================="
    echo "Building Unified HALIF"
    echo "========================================="

    make TARGET=${TARGET} VARIANT=${VARIANT}
}

# Package the built runtime bin directory into a unified tarball for distribution.
create_unified_tarball()
{
    local archive_path="${BUILD_DIR}/vts_hal_unified.tar.gz"

    if [ -d "${BUILD_DIR}/bin" ]; then
        rm -f "${archive_path}"
        tar -czf "${archive_path}" -C "${BUILD_DIR}" bin
        echo
        echo "Created Unified Tarball: ${archive_path}"
    else
        echo "WARNING: build/bin not found; skipping tarball creation"
    fi
}

##############################################################################
# Launcher
##############################################################################

# Generate a launcher script that selects profile files and runs the test binary with the correct arguments.
generate_launcher()
{
cat > "${BIN_DIR}/run_hal_test.sh" << EOF
#!/bin/bash

RUN_DIR=\$(realpath "\$(dirname "\$0")")
PROJECT_ROOT=\$(realpath "\${RUN_DIR}/../..")
PROFILE_PATH=""
PROFILE_FILES=()
EXTRA_ARGS=()

while [ \$# -gt 0 ]; do
    case "\$1" in
        -p|--profile)
            if [ \$# -lt 2 ]; then
                echo "Missing value for -p"
                exit 1
            fi
            PROFILE_PATH="\$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("\$1")
            shift
            ;;
    esac
done

if [ -z "\${PROFILE_PATH}" ]; then
    if [ -d "\${PROJECT_ROOT}/profiles/sink" ]; then
        PROFILE_PATH="\${PROJECT_ROOT}/profiles/sink"
    elif [ -d "\${RUN_DIR}/profiles/sink" ]; then
        PROFILE_PATH="\${RUN_DIR}/profiles/sink"
    else
        PROFILE_PATH="\${PROJECT_ROOT}/profiles/sink"
    fi
fi

PROFILE_PATH="\$(realpath -m "\${PROFILE_PATH}")"

if [ -d "\${PROFILE_PATH}" ]; then
    while read -r profile; do
        [ -n "\${profile}" ] || continue
        PROFILE_FILES+=("\${profile}")
    done < <(find "\${PROFILE_PATH}" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)
elif [ -f "\${PROFILE_PATH}" ]; then
    PROFILE_FILES=("\${PROFILE_PATH}")
else
    echo "Profile path not found: \${PROFILE_PATH}"
    exit 1
fi

if [ \${#PROFILE_FILES[@]} -eq 0 ]; then
    echo "No profile files found under: \${PROFILE_PATH}"
    exit 1
fi

export LD_LIBRARY_PATH="\${RUN_DIR}/lib:\${RUN_DIR}:/usr/lib:/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

echo "Using Profiles:"
printf '%s\n' "\${PROFILE_FILES[@]}"

cd "\${PROJECT_ROOT}"

CMD=("\${RUN_DIR}/hal_test")
for profile in "\${PROFILE_FILES[@]}"; do
    CMD+=("-p" "\${profile}")
done

exec "\${CMD[@]}" "\${EXTRA_ARGS[@]}"
EOF

chmod +x "${BIN_DIR}/run_hal_test.sh"
}

##############################################################################
# Main
##############################################################################

# Entry point: validate arguments, prepare the workspace, sync repos, build, and package the result.
main()
{
    ACTION="build"
    parse_arguments "$@"

    case "${ACTION}" in
        clean)
            ROOT_DIR="$(pwd)"
            clean_project
            echo
            echo "========================================="
            echo "Clean Complete"
            echo "========================================="
            exit 0
            ;;
        dist_clean)
            ROOT_DIR="$(pwd)"
            dist_clean_project
            echo
            echo "========================================="
            echo "Dist Clean Complete"
            echo "========================================="
            exit 0
            ;;
    esac

    validate_target

    initialize_paths
    validate_inputs

    print_banner

    parse_manifest

    sync_repositories
    normalize_read_and_discard_helper

    setup_ut_core

    process_test_repositories

    discover_include_paths
    add_utcore_include_paths

    generate_all_profile_sets

    configure_target

    export_build_variables

    print_debug_information

    copy_profiles_to_bin

    build_project

    generate_launcher

    create_unified_tarball

    echo
    echo "========================================="
    echo "Build Complete"
    echo "========================================="
}

main "$@"