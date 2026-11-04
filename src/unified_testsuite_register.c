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
#include <ut_kvp.h>
#include <ut_kvp_profile.h>
#include <string.h>

extern int rdk_halif_test_power_manager_register_tests(void);
extern int rdk_halif_test_device_settings_register_tests(void);
extern int rdk_halif_test_deepsleep_manager_register_tests(void);
extern int rdk_halif_test_rmf_audio_capture_register_tests (void);
extern int UT_register_APIDEF_l1_tests(void);

extern int test_hdmidec_hal_l1_register(void);
extern int test_register_hdmicec_hal_source_l2_tests(void);
extern int test_register_hdmicec_hal_sink_l2_tests(void);
extern int test_register_hdmicec_hal_l3_tests(void);


static int hdmi_cec_profile_matches(const char *expected_type)
{
    char device_type[32] = {0};
    ut_kvp_status_t status;

    if (!ut_kvp_fieldPresent(ut_kvp_profile_getInstance(), "hdmicec"))
    {
        return 0;
    }

    status = ut_kvp_getStringField(ut_kvp_profile_getInstance(), "hdmicec/type",
                                  device_type, sizeof(device_type));
    if (status != UT_KVP_STATUS_SUCCESS)
    {
        return 0;
    }

    return (strncmp(device_type, expected_type, sizeof(device_type)) == 0);
}

void UT_register_all_tests(void)
{
    rdk_halif_test_power_manager_register_tests();
    rdk_halif_test_device_settings_register_tests();
    rdk_halif_test_deepsleep_manager_register_tests();
    rdk_halif_test_rmf_audio_capture_register_tests();
    UT_register_APIDEF_l1_tests();

    if (ut_kvp_fieldPresent(ut_kvp_profile_getInstance(), "hdmicec"))
    {
        test_hdmidec_hal_l1_register();

        if (hdmi_cec_profile_matches("source"))
        {
            test_register_hdmicec_hal_source_l2_tests();
        }
        else if (hdmi_cec_profile_matches("sink"))
        {
            test_register_hdmicec_hal_sink_l2_tests();
        }

        test_register_hdmicec_hal_l3_tests();
        
    }
}
