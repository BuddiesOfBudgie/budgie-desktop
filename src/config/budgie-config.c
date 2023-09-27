/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#ifndef CONFIG_H_INCLUDED
#include "config.h"
#include <stdbool.h>
#include <stddef.h>

/**
 * All this is to keep Vala happy & configured..
 */
const char* BUDGIE_MODULE_DIRECTORY = MODULEDIR;
const char* BUDGIE_MODULE_DATA_DIRECTORY = MODULE_DATA_DIR;
const char* BUDGIE_RAVEN_PLUGIN_LIBDIR = RAVEN_PLUGIN_LIBDIR;
const char* BUDGIE_RAVEN_PLUGIN_DATADIR = RAVEN_PLUGIN_DATADIR;

#ifdef HAS_SECONDARY_PLUGIN_DIRS
const bool BUDGIE_HAS_SECONDARY_PLUGIN_DIRS = true;
const char* BUDGIE_MODULE_DIRECTORY_SECONDARY = MODULEDIR_SECONDARY;
const char* BUDGIE_MODULE_DATA_DIRECTORY_SECONDARY = MODULE_DATA_DIR_SECONDARY;
const char* BUDGIE_RAVEN_PLUGIN_LIBDIR_SECONDARY = RAVEN_PLUGIN_LIBDIR_SECONDARY;
const char* BUDGIE_RAVEN_PLUGIN_DATADIR_SECONDARY = RAVEN_PLUGIN_DATADIR_SECONDARY;
#else
const bool BUDGIE_HAS_SECONDARY_PLUGIN_DIRS = false;
const char* BUDGIE_MODULE_DIRECTORY_SECONDARY = NULL;
const char* BUDGIE_MODULE_DATA_DIRECTORY_SECONDARY = NULL;
const char* BUDGIE_RAVEN_PLUGIN_LIBDIR_SECONDARY = NULL;
const char* BUDGIE_RAVEN_PLUGIN_DATADIR_SECONDARY = NULL;
#endif

const char* BUDGIE_DATADIR = DATADIR;
const char* BUDGIE_VERSION = PACKAGE_VERSION;
const char* BUDGIE_WEBSITE = PACKAGE_URL;
const char* BUDGIE_LOCALEDIR = LOCALEDIR;
const char* BUDGIE_GETTEXT_PACKAGE = GETTEXT_PACKAGE;
const char* BUDGIE_CONFDIR = SYSCONFDIR;

#else
#error config.h missing!
#endif
