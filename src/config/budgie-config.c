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
#include <stdlib.h>
#include <string.h>

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

/**
 * Return the value of the environment variable @name, or @fallback if it is unset or empty.
 */
static const char* budgie_config_env_or(const char* name, const char* fallback) {
	const char* value = getenv(name);

	if (value == NULL || value[0] == '\0') {
		return fallback;
	}

	return value;
}

/**
 * Point the plugin directories at the build tree when running under `meson devenv`.
 *
 * Runs at load time so every target that links libconfig gets the override.
 */
__attribute__((constructor)) static void budgie_config_apply_devenv(void) {
	const char* devenv = getenv("MESON_DEVENV");

	if (devenv == NULL || strcmp(devenv, "1") != 0) {
		return;
	}

	BUDGIE_MODULE_DIRECTORY = budgie_config_env_or("BUDGIE_MODULE_DIRECTORY", BUDGIE_MODULE_DIRECTORY);
	BUDGIE_MODULE_DATA_DIRECTORY = budgie_config_env_or("BUDGIE_MODULE_DATA_DIRECTORY", BUDGIE_MODULE_DATA_DIRECTORY);
	BUDGIE_RAVEN_PLUGIN_LIBDIR = budgie_config_env_or("BUDGIE_RAVEN_PLUGIN_LIBDIR", BUDGIE_RAVEN_PLUGIN_LIBDIR);
	BUDGIE_RAVEN_PLUGIN_DATADIR = budgie_config_env_or("BUDGIE_RAVEN_PLUGIN_DATADIR", BUDGIE_RAVEN_PLUGIN_DATADIR);
}

#else
#error config.h missing!
#endif
