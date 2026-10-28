#include <ut.h>



    extern int rdk_halif_test_power_manager_register_tests(void);
    extern int rdk_halif_test_device_settings_register_tests(void);

void UT_register_all_tests(void)
{

        rdk_halif_test_power_manager_register_tests();
        rdk_halif_test_device_settings_register_tests();
}
