#include <ut.h>
#include <ut_log.h>

extern void UT_register_all_tests(void);

int main(int argc, char **argv)
{
    UT_init(argc, argv);

    UT_LOG("================================================");
    UT_LOG("         Unified HALIF Test Framework");
    UT_LOG("================================================");

    UT_register_all_tests();

    UT_run_tests();

    UT_exit();

    return 0;
}
