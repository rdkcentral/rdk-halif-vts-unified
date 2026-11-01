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
