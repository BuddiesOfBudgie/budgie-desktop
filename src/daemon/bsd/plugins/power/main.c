#include "gsd-main-helper.h"
#include "gsd-power-manager.h"

int
main (int argc, char **argv)
{
        return gsd_main_helper (GSD_TYPE_POWER_MANAGER, argc, argv);
}
