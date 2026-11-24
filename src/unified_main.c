/**
 *  If not stated otherwise in this file or this component's LICENSE
 *  file the following copyright and licenses apply:
 *
 *  Copyright 2026 RDK Management
 *
 *  Licensed under the Apache License, Version 2.0 (the License);
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an AS IS BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#include <ut.h>
#include <ut_log.h>
#include <ut_kvp_profile.h>
#include "test_parse_configuration.h"

extern void UT_register_all_tests(void);

int main(int argc, char **argv)
{
    UT_init(argc, argv);

    UT_LOG("================================================");
    UT_LOG("         Unified HALIF Test Framework");
    UT_LOG("================================================");

    if (test_parse_configuration() == -1)
    {
        UT_FAIL(" Failed to parse the configuration file");
        test_parse_configuration_term();
        return -1;
    }

    UT_register_all_tests();

    UT_run_tests();

    test_parse_configuration_term();

    ut_kvp_profile_close();

    UT_exit();

    return 0;
}
