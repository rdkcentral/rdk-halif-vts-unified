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
#* *****************************************************************************
 
import os
import sys
 
dir_path = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(dir_path, "../"))
 
from vts_helper import VTSTestHelperClass
from raft.framework.core.logModule import logModule
 
 
class L1L2TestClass(VTSTestHelperClass):
    """Runs all L1 and L2 VTS test suites in a single entrypoint."""
 
    def __init__(self, log: logModule = None):
        super().__init__(
            module_name="VTS",
            test_name="L1L2Test",
            qc_id="L1L2_001",
            setup_file_name="vts_l1l2_test_setup.yaml",
            test_config_file_name="vts_l1l2_test_setup.yaml",
            log=log,
        )
 
    def testFunction(self) -> bool:
        """Main executor filtering only L1/L2 suites from setup and running them."""
        if not self.test_prepare_function():
            self.log.error("Test preparation failed")
            return False
 
        final_result = True
 
        # Start UT menu once
        for i, ut_menu in enumerate(self.ut_menu):
            self.log.info(f"[Instance {i}] Starting test case...")
            ut_menu.start()
 
        test_suites = self.test_setup.fields.get("test", {}).get("suites", {})
 
        for suite_key, suite in test_suites.items():
            suite_name = suite.get("name", "")
            if not (suite_name.startswith("[L1 ") or suite_name.startswith("[L2 ")):
                continue
 
            test_cases = suite.get("tests")
            # If no test_cases listed in setup, default to run ALL from catalog
            if not test_cases:
                self.log.info(f"No test_cases in setup for {suite_name}; defaulting to ALL from catalog")
                test_cases = ["all"]
 
            if len(test_cases) == 1 and test_cases[0] == "all":
                self.log.stepStart(f"Test Suite: {suite_name} Run all Test cases")
                result = self.run_all(suite_name, use_all_wait_time=False)
                final_result = final_result and bool(result)
                self.log.stepResult(result, f"Test Suite: {suite_name} Run all Test cases")
            else:
                for tc in test_cases:
                    self.log.testStart(suite_name, tc)
                    self.log.stepStart(f"Test Suite: {suite_name} Test Case: {tc}")
                    result = self.runTest(suite_name, tc, use_all_wait_time=False)
                    final_result = final_result and bool(result)
                    self.log.stepResult(result, f"Test Suite: {suite_name} Test Case: {tc}")
                    self.log.testResult(f'{suite_name} Finished')
 
        # Stop UT menu
        for i, ut_menu in enumerate(self.ut_menu):
            self.log.info(f"[Instance {i}] Stopping test case...")
            ut_menu.stop()
 
        self.test_cleanup()
        return final_result
 
 
if __name__ == "__main__":
    summaryLogName = os.path.splitext(os.path.basename(__file__))[0] + "_summary"
    summaryLog = logModule("L1L2Test", level=logModule.INFO)
    test = L1L2TestClass(summaryLog)
    test.run(False)