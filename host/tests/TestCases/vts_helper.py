#!/usr/bin/env python3
#** *****************************************************************************
# *
# * If not stated otherwise in this file or this component's LICENSE file the
# * following copyright and licenses apply:
# *
# * Copyright 2025 RDK Management
# *
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
# * You may obtain a copy of the License at
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
 
import os
import sys
import yaml
import re
from pathlib import Path
 
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
    Generic VTS helper class for test execution (L1, L2, L3, L4).
    Provides common functionality for environment setup, binary copying, test execution, cleanup,
    and L4 YAML generation. Can be used for any module (VTS,AVModule, DSModule, etc.).
    """
 
    def get_stream_extension(self, stream_name):
        """
        Extracts the file extension from a stream name.
 
        Args:
            stream_name (str): The name of the stream file.
        """
        _, stream_ext = os.path.splitext(stream_name)
        return stream_ext.lstrip('.') if stream_ext else "mp4"
 
 
    def __init__(self, module_name: str, test_name: str, qc_id: str,
                 test_suites: list = None, l4_yaml_path: str = None,
                 setup_file_name: str = None, test_config_file_name: str = None,
                 log: logModule = None):
        """
        Initializes the helper class.
 
        Args:
            module_name (str): Name of the module (e.g., "AVModule").
            test_name (str): Name of the test (e.g., "L4_AVModule").
            qc_id (str): QC ID for the test (e.g., "L4_001").
            test_suites (list, optional): List of test suite names to run. If None, runs all suites.
            l4_yaml_path (str, optional): Path to L4 input YAML file for generating YAML files.
            log (logModule, optional): Parent log class. Defaults to None.
        """
        super().__init__(test_name, qc_id, log)
        self.log = log or logModule(self.__class__.__name__, level=logModule.INFO)
        self.module_name = module_name
        self.test_name = test_name
        self.qc_id = qc_id
        self.test_suites = test_suites or []
        # Default L4 YAML path based on module name
        default_l4_path = f"vts_l4_{module_name.lower()}_test_info.yaml" if module_name else "vts_l4_test_info.yaml"
        self.l4_yaml_path = l4_yaml_path or os.path.join(dir_path, default_l4_path)
        self.rack_device = "dut"
 
        # Load configurations (allow override for L1/L2/L3 runners)
        # Default to module-specific setup file if not provided
        setup_file = setup_file_name
        test_cfg_file = test_config_file_name
        self.test_setup_path = os.path.join(dir_path, setup_file)
        self.test_config_local_path = os.path.join(dir_path, test_cfg_file)
        self.test_setup = ConfigRead(self.test_setup_path, self.module_name)
        self.test_config = ConfigRead(self.test_config_local_path, self.module_name)
 
        # Device settings
        device_test_setup = self.cpe.get("test")
        self.target_workspace = self.cpe.get("target_directory")
        # Target-side relative path to copy test configs (used by L4)
        self.test_config_path = self.cpe.get("test_config_path")
        self.prompt = self.cpe.get("prompt")
        self.wait_time = self.cpe.get("wait_time")
        self.all_wait_time = self.cpe.get("all_wait_time")
        self.stream_download_url = device_test_setup.get("streams_download_url")
        self.download_path = self.cpe.get("download_path")
 
        # Initialize sessions
        self.instance_list = self.test_setup.fields.get("num_of_instances", 1)
        self.hal_sessions = [self.dut.getConsoleSession(f"ssh_hal_test_{i}") for i in range(self.instance_list)]
        for session in self.hal_sessions:
            session.prompt = self.prompt
 
        # Setup test environment
        self.bin_path = "bin/"
        self.profile_path = "profiles/"
        self.target_workspace = os.path.join(self.target_workspace, self.module_name).replace("\\", "/")
        self.run_path = os.path.join(self.target_workspace, self.bin_path).replace("\\", "/")
        self.download_path = os.path.join(self.run_path, self.download_path)
 
        # Profile and test menu setup
        profile = device_test_setup.get("profile")
        directory, filename = os.path.split(profile)
        name, ext = os.path.splitext(filename)
        self.module_config_profile_files = []
        self.ut_menu = []
        self.copied_binaries = []  # Track copied binaries for cleanup
 
        for i in range(self.instance_list):
            if self.instance_list == 1:
                final_profile = os.path.join(directory, filename)
            else:
                final_profile = os.path.join(directory, f"{name}_instance_{i+1}{ext}")
            self.module_config_profile_files.append(final_profile)
 
            profile_file_path = os.path.join(self.profile_path, os.path.basename(final_profile)).replace("\\", "/")
            # Append profile path to execution command
            self.test_config.test.execute = self.test_config.test.execute + f" -p {profile_file_path}"
 
            hal_session = self.hal_sessions[i]
            ut_menu = UTSuiteNavigatorClass(self.test_config, None, hal_session)
            self.ut_menu.append(ut_menu)
 
        self.utilities = utBaseUtils()
        # Create user response Class
        self.testUserResponse = utUserResponse()
        self.test_streams = []
 
    def download_streams_from_list(self, streams: list) -> bool:
        """
        Download the provided list of stream paths to the DUT and record their
        target locations in self.test_streams.
 
        Args:
            streams (list): List of relative stream paths from the server root.
 
        Returns:
            bool: True if successful or list is empty, False otherwise.
        """
        try:
            if not streams:
                return True
 
            if not self.stream_download_url:
                self.log.error("streams_download_url not configured; cannot download streams")
                return False
 
            urls = []
            self.test_streams = []
            for spath in streams:
                full_url = os.path.join(self.stream_download_url, str(spath).lstrip('/'))
                urls.append(full_url)
                self.test_streams.append(os.path.join(self.download_path, os.path.basename(str(spath))))
 
            self.downloadToDevice(urls, self.download_path, self.rack_device, True)
            return True
        except Exception as e:
            self.log.error(f"Failed downloading streams list: {e}")
            return False
 
    def restart_services(self, testsuite_name: str):
        """
        Legacy method - process restart between test cases has been disabled.
        Kept for backward compatibility but does nothing.
        """
        pass
 
    def parse_stream_name(self, stream_name: str, tcid: str) -> dict:
        """
        Parses stream name to extract metadata from the filename pattern.
 
        Args:
            stream_name (str): Stream name (e.g., "vts_h264_1440p_sdr_23f_BT709_YCbCr420_18M_aac_16000_1ch_1024k_a939_v1439_61sec.mp4").
            tcid (str): Test case ID (e.g., "VTS_L4_H264_AAC1001").
 
        Returns:
            dict: Extracted stream information.
        """
 
        # Remove extension for parsing
        base_name = os.path.splitext(stream_name)[0]
        stream_ext = self.get_stream_extension(stream_name)
 
        # Pattern to match: ..._aXXX_vYYY_ZZsec where:
        # aXXX = audio frames (e.g., a939)
        # vYYY = video frames (e.g., v1439)
        # ZZsec = duration in seconds (e.g., 61sec)
        # Optional: aeXXX = audio error frames, veYYY = video error frames
 
        pattern = r'^(.*?)_a(\d+)_v(\d+)_(\d+)sec(_ae(\d+))?(_ve(\d+))?(?:\.[^.]+)?$'
        match = re.match(pattern, base_name)
 
        if not match:
            self.log.info(f"Could not parse stream name pattern: {stream_name}")
            if not stream_ext:
                self.log.info(f"No extension found in stream name: {stream_name}. Defaulting to .mp4")
                stream_ext = "mp4"
            # Return defaults if parsing fails
            input == stream_name
 
            str_name = f"{self.tcid}.{stream_ext}" # Use original extension
 
            return {
            "input": str_name,  # Original stream name
            "duration": 60,
            "audio_frames": 00,
            "video_frames": 00,
            "audio_error_frames": 0,
            "video_error_frames": 0
            }
 
        # Extract groups from regex match
        groups = match.groups()
        audio_frames = int(groups[1])  # aXXX
        video_frames = int(groups[2])  # vYYY
        duration = int(groups[3])       # ZZsec
 
        # Check for error frames (optional groups)
        audio_error_frames = int(groups[5]) if groups[5] else 0  # aeXXX
        video_error_frames = int(groups[7]) if groups[7] else 0  # veYYY
        if not stream_ext:
            stream_ext = "mp4"
        str_name = f"{self.tcid}.{stream_ext}" # Use original extension
 
        stream_info = {
            "input": str_name,  # Original stream name
            "duration": duration,
            "audio_frames": audio_frames,
            "video_frames": video_frames,
            "audio_error_frames": audio_error_frames,
            "video_error_frames": video_error_frames
        }
 
        self.log.debug(f"Parsed stream {stream_name}: duration={duration}s, audio_frames={audio_frames}, video_frames={video_frames}, audio_errors={audio_error_frames}, video_errors={video_error_frames}")
        return stream_info
 
    def generate_l4_yaml_files_for_test_case(self, test_case: dict, test_config_path: str, stream_config_path: str, stream_name: str) -> bool:
        """
        Generates vts_l4_av_test_config.yaml and vts_l4_av_stream_config.yaml for a single test case.
 
        Args:
            test_case (dict): Test case data with tcid, action, and stream_name.
            test_config_path (str): Path to output vts_l4_av_test_config.yaml.
            stream_config_path (str): Path to output vts_l4_av_stream_config.yaml.
 
        Returns:
            bool: True if generation is successful, False otherwise.
        """
        try:
            # Read L4 input YAML to get stream_download_path, input_streams_path, player
            if not os.path.exists(self.l4_yaml_path):
                self.log.error(f"L4 input YAML file {self.l4_yaml_path} does not exist")
                return False
 
            with open(self.l4_yaml_path, 'r') as f:
                data = yaml.safe_load(f)
 
            av_module = data.get("AVModule", {})
            stream_download_path = av_module.get("stream_download_path")
            input_streams_path = av_module.get("input_streams_path")
            player = av_module.get("player")
 
            self.tcid = test_case.get("tcid")
            action = test_case.get("action")
            # Get original stream name with extension
            original_stream_name = test_case.get("stream_name")
 
            # Create stream_name without tcid extension for YAML key
            stream_ext = self.get_stream_extension(stream_name)
            stream_name = [f"{self.tcid}_{stream_ext}"]
            #stream_name = test_case.get("stream_name")
 
 
            # Map action to test case name
            action_to_test_case = {
                "normal_play": "NormalPlay",
                "trick_play": "playBackWithTrickModes",
                "audio_switch": "AudioTrackSwitch",
                "video_switch": "VideoTrackSwitch"
            }
            test_case_name = action_to_test_case.get(action, action)
 
            # Generate vts_l4_av_test_config.yaml
            test_config = {
                "AVModule": {
                    "stream_download_path": stream_download_path,
                    "input_streams_path": input_streams_path,
                    "player": player,
                    "userChoice": self.cpe.get("playback_manual_verification", 1) == 1,  # Convert to boolean: 1->true, 0->false
                    "L4": {
                        test_case_name: {
                            "controls": {
                                "delay_between_play": 100
                            },
                            "streams": stream_name # Use stream_name without tcid extension for YAML key
                        }
                    }
                }
            }
            # Generate vts_l4_av_stream_config.yaml
            stream_info = self.parse_stream_name(original_stream_name, self.tcid)
 
            if test_case_name == "NormalPlay" or test_case_name == "AudioTrackSwitch" or test_case_name == "VideoTrackSwitch":
                test_config["AVModule"]["L4"][test_case_name]["controls"]["trick_modes"] = [
                    {"action": "play", "duration": stream_info["duration"]}
                ]
            elif test_case_name == "playBackWithTrickModes":
                test_config["AVModule"]["L4"][test_case_name]["controls"]["trick_modes"] = [
                    {"action": "play", "duration": 20},
                    {"action": "seek", "duration": 20, "position": 30},
                    {"action": "trick_mode", "duration": 20, "speed": 2.0},
                    {"action": "play", "duration": 20, "speed": 1.0},
                    {"action": "trick_mode", "duration": 20, "speed": 0.5},
                    {"action": "seek", "duration": 20, "position": -60},
                    {"action": "trick_mode", "duration": 20, "speed": 8.0},
                    {"action": "seek", "duration": 20, "position": -120},
                    {"action": "trick_mode", "duration": 20, "speed": 4.0},
                    {"action": "seek", "duration": 20, "position": 200},
                    {"action": "trick_mode", "duration": 20, "speed": 2.0},
                    {"action": "play", "duration": 20, "speed": 1.0},
                    {"action": "seek", "duration": 30, "position": 570},
                    {"action": "play", "duration": 30, "speed": 1.0}
                ]
 
            # Generate vts_l4_av_stream_config.yaml
            stream_config = {
                "AVStreams": {
                    f"{self.tcid}_{stream_ext}": self.parse_stream_name(original_stream_name, self.tcid)
                }
            }
 
            # Add include_0 entry
            test_config["include_0"] = "av_test_configurations/vts_l4_av_stream_config.yaml"
            # Write vts_l4_av_test_config.yaml
            with open(test_config_path, 'w') as f:
                yaml.safe_dump(test_config, f, default_flow_style=False)
 
            # Write vts_l4_av_stream_config.yaml
            with open(stream_config_path, 'w') as f:
                yaml.safe_dump(stream_config, f, default_flow_style=False)
 
            self.log.info(f"Generated {test_config_path} and {stream_config_path} for TCID: {self.tcid}")
            return True
        except Exception as e:
            self.log.error(f"Failed to generate L4 YAML files for TCID {self.tcid}: {str(e)}")
            return False
 
    def copy_yaml_and_stream(self, test_config_path: str, stream_config_path: str, stream_name: str, tcid: str):
        """
        Copies the generated YAML files and the stream file to the DUT.
 
        Args:
            test_config_path (str): Path to vts_l4_av_test_config.yaml.
            stream_config_path (str): Path to vts_l4_av_stream_config.yaml.
            stream_name (str): Original stream name (e.g., "vts_h264_1440p_...").
            tcid (str): Test case ID for the target stream name (e.g., "VTS_L4_H264_AAC1001").
 
        Returns:
            bool: True if copying is successful, False otherwise.
        """
        try:
            # Copy YAML files to target_workspace
            target_test_config = os.path.join(self.target_workspace,self.test_config_path).replace("\\", "/")
            target_stream_config = os.path.join(self.target_workspace,self.test_config_path).replace("\\", "/")
 
            self.utilities.sftpCopy(self.hal_sessions[0], test_config_path, target_test_config)
            self.utilities.sftpCopy(self.hal_sessions[0], stream_config_path, target_stream_config)
            self.log.info(f"Copied {test_config_path} to {target_test_config}")
            self.log.info(f"Copied {stream_config_path} to {target_stream_config}")
 
            # Copy stream file to input_streams_path
            stream_url = os.path.join(self.stream_download_url, stream_name.lstrip("/"))
            stream_ext = self.get_stream_extension(stream_name)
            target_stream_path = os.path.join(self.download_path, f"{self.tcid}.{stream_ext}").replace("\\", "/")
            self.downloadToDevice([stream_url], self.download_path, self.rack_device, True)
            str_name = os.path.basename(stream_name)
            cmd = f"mv {self.download_path}{str_name} {target_stream_path}"
            self.writeCommands(cmd,self.hal_sessions[0])
            self.test_streams.append(target_stream_path)
            self.log.info(f"Copied stream {stream_name} to {target_stream_path}")
 
            return True
        except Exception as e:
            self.log.error(f"Failed to copy YAML files or stream for TCID {tcid}: {str(e)}")
            return False
 
    #TODO: Current version supports only manual verification.
    def testVerifyAVPlayback(self, manual=False):
        """
        Verifies whether video is being AV playback is fine without artifacts or not.
 
        Args:
            manual (bool, optional): Indicates if manual verification is required.
                                     Defaults to False (automatic verification).
 
        Returns:
            bool: Verification result (True if the AV playback is fine without artifacts, False otherwise).
        """
        if manual == True:
            return self.testUserResponse.getUserYN("Is AV playback is fine without artifacts (Y/N):")
        else :
            #TODO: Add automation verification methods
            return False
 
    def copy_binaries(self):
        """
        Copies binaries specified in the test configuration to the DUT.
 
        Returns:
            bool: True if all binaries are copied successfully, False otherwise.
        """
        try:
            artifacts = self.test_config.test.artifacts
            if not artifacts:
                self.log.warning("No artifacts specified in the configuration file.")
                return True
 
            self.log.info(f"Copying {len(artifacts)} binaries to {self.target_workspace}...")
            for artifact in artifacts:
                artifact_path = os.path.normpath(os.path.join(dir_path, artifact))
                if not os.path.exists(artifact_path):
                    self.log.error(f"Artifact file {artifact_path} does not exist")
                    return False
 
                # Copy the artifact to the DUT
                self.utilities.sftpCopy(self.hal_sessions[0], artifact_path, self.target_workspace)
                self.copied_binaries.append(os.path.join(self.target_workspace, os.path.basename(artifact_path)))
                self.log.info(f"Copied {artifact_path} to {self.target_workspace}")
                self.utilities.change_directory(self.hal_sessions[0], self.target_workspace)
 
 
                # Extract if the artifact is a tar.gz file
                self.utilities.untar(self.hal_sessions[0], os.path.basename(artifact_path), self.target_workspace)
                self.log.info(f"Extracted {artifact_path} in {self.target_workspace}")
 
            # Ensure run.sh is executable
                self.utilities.change_directory(self.hal_sessions[0], self.run_path)
            return True
        except Exception as e:
            self.log.error(f"Failed to copy binaries: {str(e)}")
            return False
 
    def clean_binaries(self):
        """
        Removes copied binaries from the DUT.
 
        Returns:
            bool: True if cleanup is successful, False otherwise.
        """
        try:
            if not self.copied_binaries:
                self.log.info("No binaries to clean up.")
                return True
 
            self.log.info("Cleaning up binaries from DUT...")
            self.deleteFromDevice(self.copied_binaries, self.rack_device, False)
            self.copied_binaries = []
            self.log.info("Binary cleanup completed.")
            return True
        except Exception as e:
            self.log.error(f"Failed to clean up binaries: {str(e)}")
            return False
 
    def test_prepare_function(self):
        """
        Prepares the environment by copying binaries and setting up the test.
 
        Returns:
            bool: True if preparation is successful, False otherwise.
        """
        self.log.testStart(self.test_name, self.qc_id)
 
        # Copy binaries to DUT
        if not self.copy_binaries():
            self.log.error("Failed to copy binaries to DUT")
            return False
 
        # Change to run directory
        for session in self.hal_sessions:
            self.utilities.change_directory(session, self.run_path)
 
        return True
 
    def test_download_all_assets(self):
        """
        Placeholder for downloading all assets (not used since streams are copied per test case).
 
        Returns:
            bool: True (no-op).
        """
        self.log.info("Stream downloading handled per test case in L4TestClass")
        return True
 
    def test_clean_all_assets(self):
        """
        Removes all downloaded streams from the DUT.
 
        Returns:
            bool: True if cleanup is successful, False otherwise.
        """
        try:
            if self.test_streams:
                self.log.info("Cleaning up downloaded streams...")
                self.deleteFromDevice(self.test_streams, self.rack_device, False)
                self.test_streams = []
            else:
                self.log.info("No streams to clean up")
            return True
        except Exception as e:
            self.log.error(f"Failed to clean up streams: {str(e)}")
            return False
 
    def runTest(self, test_suite: str, test_case: str, use_all_wait_time: bool = False):
        """
        Runs a specific test case for the given test suite.
 
        Args:
            test_suite (str): Name of the test suite.
            test_case (str): Specific test case to run.
            use_all_wait_time (bool): Use all_wait_time instead of wait_time for L2/L3/L4 tests.
 
        Returns:
            True if the test passes, False if it fails, or the string "SKIPPED"
            if every instance reported the test as skipped.
        """
        outputs = []
        results = []
 
        wait_time = self.all_wait_time if use_all_wait_time else self.wait_time
 
        # Load prompt config only for VTS_L3_PlaneControl test case (once, outside loop)
        prompt = None
        if test_suite == "VTS_L3_PlaneControl":
            self.test_promptPath = os.path.join(dir_path, "vts_avmodule_prompt.yaml")
            self.testPrompt = ConfigRead(self.test_promptPath, self.module_name)
            fields = getattr(self.testPrompt, "fields", {})
            if test_case is not None:
                prompt = fields.get(test_case)
 
        for i, ut_menu in enumerate(self.ut_menu):
            self.log.info(f"[Instance {i}] Running test case: {test_case} in suite {test_suite}...")
            output = ut_menu.select(test_suite, test_case, prompt, wait_time, False)
 
            run_summary_found = "Run Summary:" in output and "Segmentation fault" not in output
            if not run_summary_found:
                self.log.error(f"[Instance {i}] Run Summary not found - test case likely crashed. Marking as FAILED.")
                # Restart the menu to recover the session for next tests
                self.log.info(f"[Instance {i}] Restarting ut_menu to prepare for next test cases...")
                ut_menu.stop()
                ut_menu.start()
                # Mark this test as failed and skip retry (don't run the same crashed test again)
                outputs.append("")  # Empty output for failed case
                results.append(False)  # Explicitly mark as failed
                continue
 
            outputs.append(output)
 
        # Collect results only for tests that actually ran (not already marked as failed)
        for i, (ut_menu, output) in enumerate(zip(self.ut_menu, outputs)):
            # Skip if we already marked this as failed (empty output from crash)
            if not output:
                continue
            result = ut_menu.collect_results(output, True)
            # Replace the placeholder result if we're processing this output
            if i < len(results):
                results[i] = result if result is not None else False
            else:
                results.append(result if result is not None else False)
            self.log.info(f"[Instance {i}] Result: {result}")
 
        # "SKIPPED" is truthy but must not be collapsed into True by all() -
        # a run where anything explicitly failed is still FAILED, a run where
        # every instance was skipped is SKIPPED, otherwise it's a pass.
        if not results:
            return False
        if any(r is False for r in results):
            return False
        if all(r == "SKIPPED" for r in results):
            return "SKIPPED"
        return True
 
    def run_all(self, test_suite: str, use_all_wait_time: bool = False):
        """
        Runs all test cases in the specified test suite.
 
        Args:
            test_suite (str): Name of the test suite.
            use_all_wait_time (bool): Use all_wait_time instead of wait_time for L2/L3/L4 tests.
 
        Returns:
            True if all tests pass, False if any fail, or the string "SKIPPED"
            if every instance reported the suite as skipped.
        """
        return self.runTest(test_suite, None, use_all_wait_time)
 
    def test_cleanup(self):
        """
        Cleans up after test execution.
 
        Returns:
            bool: True if cleanup is successful, False otherwise.
        """
        #self.log.testStart(self.test_name, self.tcid)
        self.test_clean_all_assets()
        self.clean_binaries()
        #self.log.testResult(f'{self.test_name} Finished')
        return True