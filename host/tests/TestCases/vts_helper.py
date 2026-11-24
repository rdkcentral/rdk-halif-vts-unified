#!/usr/bin/env python3
#******************************************************************************
#
# If not stated otherwise in this file or this component's LICENSE file the
# following copyright and licenses apply:
#
# Copyright 2026 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#******************************************************************************

import os
import sys

dir_path = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(dir_path, "../"))

from raft.framework.plugins.ut_raft.configRead import ConfigRead
from raft.framework.plugins.ut_raft import utHelperClass
from raft.framework.core.logModule import logModule
from raft.framework.plugins.ut_raft.utSuiteNavigator import UTSuiteNavigatorClass
from raft.framework.plugins.ut_raft.utBaseUtils import utBaseUtils
from raft.framework.plugins.ut_raft.utUserResponse import utUserResponse


class VTSTestHelperClass(utHelperClass):
    """
    Generic helper class for Unified HALIF L1/L2 execution.

    Handles:
      - Configuration loading
      - DUT session setup
      - Binary deployment
      - UT menu navigation
      - Test execution
      - Cleanup
    """

    def __init__(self, module_name: str, test_name: str, qc_id: str, test_suites: list = None, setup_file_name: str = None, test_config_file_name: str = None, log: logModule = None):
        super().__init__(test_name, qc_id, log)

        self.log = log or logModule(self.__class__.__name__, level=logModule.INFO)

        self.module_name = module_name
        self.test_name = test_name
        self.qc_id = qc_id
        self.test_suites = test_suites or []

        self.test_setup_path = os.path.join(dir_path, setup_file_name)
        self.test_config_local_path = os.path.join(dir_path, test_config_file_name)

        self.test_setup = ConfigRead(self.test_setup_path, self.module_name)
        self.test_config = ConfigRead(self.test_config_local_path, self.module_name)

        device_test_setup = self.cpe.get("test")

        self.target_workspace = self.cpe.get("target_directory")
        self.prompt = self.cpe.get("prompt")
        self.wait_time = self.cpe.get("wait_time")
        self.all_wait_time = self.cpe.get("all_wait_time")

        self.instance_list = self.test_setup.fields.get("num_of_instances", 1)

        self.hal_sessions = [
            self.dut.getConsoleSession(f"ssh_hal_test_{i}")
            for i in range(self.instance_list)
        ]

        for session in self.hal_sessions:
            session.prompt = self.prompt

        self.bin_path = "bin/"
        self.profile_path = "profiles/"

        self.target_workspace = os.path.join(
            self.target_workspace,
            self.module_name
        ).replace("\\", "/")

        self.run_path = os.path.join(
            self.target_workspace,
            self.bin_path
        ).replace("\\", "/")

        profile_type = self.cpe.get("profile_type")
        profile = device_test_setup.get("profile")
        profile = profile.format(profile_type=profile_type)

        self.module_config_profile_files = []
        self.ut_menu = []
        self.copied_binaries = []

        for i in range(self.instance_list):

            profile_file_path = profile.replace("\\", "/").removeprefix("bin/")

            self.module_config_profile_files.append(profile_file_path)
            self.test_config.test.execute += f" -p {profile_file_path}"

            ut_menu = UTSuiteNavigatorClass(
                self.test_config,
                None,
                self.hal_sessions[i]
            )

            self.ut_menu.append(ut_menu)

        self.utilities = utBaseUtils()
        self.testUserResponse = utUserResponse()

    def copy_binaries(self) -> bool:
        """
        Copy build artifacts to DUT.
        """
        try:
            artifacts = self.test_config.test.artifacts

            if not artifacts:
                self.log.warning("No artifacts specified in configuration.")
                return True

            self.log.info(
                f"Copying {len(artifacts)} artifact(s) to {self.target_workspace}"
            )

            for artifact in artifacts:

                artifact_path = os.path.normpath(
                    os.path.join(dir_path, artifact)
                )

                if not os.path.exists(artifact_path):
                    self.log.error(
                        f"Artifact file does not exist: {artifact_path}"
                    )
                    return False

                self.utilities.sftpCopy(
                    self.hal_sessions[0],
                    artifact_path,
                    self.target_workspace
                )

                self.copied_binaries.append(
                    os.path.join(
                        self.target_workspace,
                        os.path.basename(artifact_path)
                    )
                )

                self.log.info(
                    f"Copied {artifact_path} to {self.target_workspace}"
                )

                self.utilities.change_directory(
                    self.hal_sessions[0],
                    self.target_workspace
                )

                self.utilities.untar(
                    self.hal_sessions[0],
                    os.path.basename(artifact_path),
                    self.target_workspace
                )

                self.log.info(f"Extracted {artifact_path}")

            return True

        except Exception as e:
            self.log.error(f"Failed to copy binaries: {e}")
            return False

    def clean_binaries(self) -> bool:
        """
        Remove copied artifacts from DUT.
        """
        try:
            if not self.copied_binaries:
                self.log.info("No binaries to clean")
                return True

            self.log.info("Cleaning copied binaries from DUT...")

            self.deleteFromDevice(
                self.copied_binaries,
                "dut",
                False
            )

            self.copied_binaries = []
            self.log.info("Binary cleanup completed")
            return True

        except Exception as e:
            self.log.error(f"Failed to clean binaries: {e}")
            return False

    def test_prepare_function(self) -> bool:
        """
        Deploy artifacts and move to run directory.
        """

        self.log.testStart(self.test_name, self.qc_id)

        if not self.copy_binaries():
            self.log.error("Failed to copy binaries to DUT")
            return False

        for session in self.hal_sessions:
            self.utilities.change_directory(session, self.run_path)

        return True

    def runTest(self, test_suite: str, test_case: str, use_all_wait_time: bool = False):
        outputs = []
        results = []

        wait_time = (
            self.all_wait_time
            if use_all_wait_time
            else self.wait_time
        )

        for i, ut_menu in enumerate(self.ut_menu):

            self.log.info(
                f"[Instance {i}] Running {test_suite} : {test_case}"
            )

            prompt = None
            output = ut_menu.select(
                test_suite,
                test_case,
                prompt,
                wait_time,
                False
            )

            if (
                "Run Summary:" not in output
                or "Segmentation fault" in output
            ):

                self.log.error(
                    f"[Instance {i}] Execution failed"
                )

                ut_menu.stop()
                ut_menu.start()

                results.append(False)
                continue

            outputs.append(output)
            result = ut_menu.collect_results(output, True)
            result = result if result is not None else False
            results.append(result)

            self.log.info(
                f"[Instance {i}] Result = {result}"
            )

        if not results:
            return False

        if any(r is False for r in results):
            return False

        if all(r == "SKIPPED" for r in results):
            return "SKIPPED"

        return True

    def run_all(self, test_suite: str, use_all_wait_time: bool = False):
        return self.runTest(
            test_suite,
            None,
            use_all_wait_time
        )

    def test_cleanup(self) -> bool:
        """
        Cleanup after execution.
        """

        self.clean_binaries()
        return True