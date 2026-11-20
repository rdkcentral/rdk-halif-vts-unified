#!/usr/bin/env bash
#** *****************************************************************************
# *
# * If not stated otherwise in this file or this component's LICENSE file the
# * following copyright and licenses apply:
# *
# * Copyright 2026 RDK Management
# *
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
# * You may obtain a copy of the License at
# *
# *
# * http://www.apache.org/licenses/LICENSE-2.0
# *
# * Unless required by applicable law or agreed to in writing, software
# * distributed under the License is distributed on an "AS IS" BASIS,
# * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# * See the License for the specific language governing permissions and
# * limitations under the License.
# *
#* ******************************************************************************

MY_PATH="$(realpath "${BASH_SOURCE[0]}")"
MY_DIR="$(dirname "${MY_PATH}")"
TESTS_DIR="${MY_DIR}/tests"
RAFT_DIR="${TESTS_DIR}/raft"
RDK_RAFT_DIR="${TESTS_DIR}/rdk_raft"
PLUGINS_FRAMEWORK_DIR="${RAFT_DIR}/framework/plugins"
VENV_NAME="python_venv"
VENV_DIR="${MY_DIR}/${VENV_NAME}"

set -e

NO_COLOR="\e[0m"
RED="\e[0;31m"
CYAN="\e[0;36m"
YELLOW="\e[1;33m"
GREEN="\e[0;32m"
RED_BOLD="\e[1;31m"
BLUE_BOLD="\e[1;34m"
YELLOW_BOLD="\e[1;33m"

function ECHO() { echo -e "$*"; }
function INFO() { ECHO "${GREEN}$*${NO_COLOR}"; }
function WARNING() { ECHO "${YELLOW_BOLD}Warning: ${YELLOW}$*${NO_COLOR}" > /dev/stderr; }
function ERROR() { ECHO "${RED_BOLD}ERROR: ${RED}$*${NO_COLOR}"; exit 1; }

function install_pip_requirements() {
    local requirements_file="$1"
    local pip_cmd="${VENV_DIR}/bin/pip"

    if [ ! -f "${requirements_file}" ]; then
        WARNING "No ${requirements_file} found"
        return
    fi
    if [ ! -x "${pip_cmd}" ]; then
        pip_cmd="$(command -v pip3 || command -v pip || true)"
    fi

    INFO "install_pip_requirements(${requirements_file}):"
    if "${pip_cmd}" install -r "${requirements_file}" >/dev/null 2>&1; then
        INFO "pip install completed"
    else
        ERROR "pip install failed for ${requirements_file}"
    fi
}

function clone_repo() {
    local repo_url="$1"
    local path="$2"
    local version="$3"
    local message="$4"

    if [[ -z "${repo_url}" ]]; then
        ERROR "clone_repo: repository URL required"
    fi
    if [[ -z "${version}" ]]; then
        ERROR "clone_repo: version required"
    fi
    if [[ -n "${path}" ]] && [[ ! -d "${path}" ]]; then
        INFO "git clone ${repo_url} @ ${version} ${CYAN}${message}${NO_COLOR}"
        git clone "${repo_url}" "${path}" >/dev/null 2>&1
        cd "${path}"
        git checkout "${version}" >/dev/null 2>&1
        cd - >/dev/null
    fi
}

function setup_and_enable_venv() {
    # Check if virtual environment directory exists, create if not
    if [[ ! -d "${VENV_DIR}" ]]; then
        ECHO "Creating Virtual environment ${YELLOW}'${VENV_NAME}'${NO_COLOR}"
        python3 -m venv "${VENV_DIR}"
        ECHO "Virtual environment created."
    fi

    # Request that the user re-run this script from the vendor
    # Check if already inside a virtual environment
    if [[ ! -n "$VIRTUAL_ENV" ]]; then
        # Activate virtual environment
        ECHO "please source & re-run ${YELLOW}install.sh${NO_COLOR} to ensure setup:"
        ECHO ${YELLOW}"source ./activate_venv.sh"${NO_COLOR}
        exit 1  # Exit the function if already in a venv
    fi

    if [ -f "${VENV_DIR}/.installed" ]; then
        return
    fi   
    touch "${VENV_DIR}/.installed"
}

mkdir -p "${TESTS_DIR}"
setup_and_enable_venv

clone_repo "git@github.com:rdkcentral/python_raft.git" "${RAFT_DIR}" "1.11.0" "in ./raft"
install_pip_requirements "${RAFT_DIR}/requirements.txt"

clone_repo "git@github.com:rdkcentral/ut-raft.git" "${PLUGINS_FRAMEWORK_DIR}/ut_raft" "2.2.1" "in ./raft/framework/plugins"
install_pip_requirements "${PLUGINS_FRAMEWORK_DIR}/ut_raft/requirements.txt"

INFO "RAFT installation complete for rdk-halif-vts-unified automation"
