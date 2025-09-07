/* -*- Mode: C; tab-width: 8; indent-tabs-mode: t; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2018 Benjamin Berg <bberg@redhat.com>
 *
 * Licensed under the GNU General Public License Version 2
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include "config.h"

#include <stdlib.h>
#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <libgen.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#define GSD_BACKLIGHT_HELPER_EXIT_CODE_SUCCESS			0
#define GSD_BACKLIGHT_HELPER_EXIT_CODE_FAILED			1
#define GSD_BACKLIGHT_HELPER_EXIT_CODE_ARGUMENTS_INVALID	3
#define GSD_BACKLIGHT_HELPER_EXIT_CODE_INVALID_USER		4

#ifndef __linux__
#error "gsd-backlight-helper does not work on non-Linux"
#endif

static void
usage(int argc, char *argv[])
{
	fprintf (stderr, "Usage: %s device brightness\n", argv[0]);
	fprintf (stderr, "  device:      The backlight directory starting with \"/sys/class/backlight/\"\n");
	fprintf (stderr, "  brightness:  The new brightness to write\n");
}

int
main (int argc, char *argv[])
{
	char tmp[512];
	const char *device = NULL;
	int fd, len, res;
	int uid, euid;
	int brightness;
	int result = GSD_BACKLIGHT_HELPER_EXIT_CODE_FAILED;
	DIR *dp = NULL;
	struct dirent *ep;

	/* check calling UID */
	uid = getuid ();
	euid = geteuid ();
	if (uid != 0 || euid != 0) {
		fprintf (stderr, "This program can only be used by the root user\n");
		result = GSD_BACKLIGHT_HELPER_EXIT_CODE_INVALID_USER;
		goto done;
	}

	if (argc != 3) {
		fprintf (stderr, "Error: Need to be called with exactly two arguments\n");
		usage (argc, argv);
		result = GSD_BACKLIGHT_HELPER_EXIT_CODE_ARGUMENTS_INVALID;
		goto done;
	}

	errno = 0;
	brightness = strtol (argv[2], NULL, 0);
	if (errno) {
		fprintf (stderr, "Error: Invalid brightness argument (%d: %s)\n", errno, strerror (errno));
		usage (argc, argv);
		goto done;
	}

	dp = opendir ("/sys/class/backlight");
	if (dp == NULL) {
		fprintf (stderr, "Error: Could not open /sys/class/backlight (%d: %s)\n", errno, strerror (errno));
		result = GSD_BACKLIGHT_HELPER_EXIT_CODE_FAILED;
		goto done;
	}

	device = argv[1];

	while ((ep = readdir (dp))) {
		char *path;

		if (ep->d_name[0] == '.')
			continue;

		/* Leave room for "/brightness" */
		snprintf (tmp, sizeof(tmp) - 11, "/sys/class/backlight/%s", ep->d_name);
		path = (char*)realpath (tmp, NULL);
		if (path && device && strcmp (path, device) == 0) {
			free (path);
			strcat (tmp, "/brightness");

			fd = open (tmp, O_WRONLY);
			if (fd < 0) {
				fprintf (stderr, "Error: Could not open brightness sysfs file (%d: %s)\n", errno, strerror(errno));
				result = GSD_BACKLIGHT_HELPER_EXIT_CODE_FAILED;
				goto done;
			}

			len = snprintf (tmp, sizeof(tmp), "%d", brightness);
			if ((res = write (fd, tmp, len)) != len) {
				if (res == -1)
					fprintf (stderr, "Error: Writing to file (%d: %s)\n", errno, strerror(errno));
				else
					fprintf (stderr, "Error: Wrote the wrong length (%d of %d bytes)!\n", res, len);

				close (fd);
				result = GSD_BACKLIGHT_HELPER_EXIT_CODE_FAILED;
				goto done;
			}
			close (fd);

			result = GSD_BACKLIGHT_HELPER_EXIT_CODE_SUCCESS;
			goto done;
		} else {
			free (path);
		}
	}

	result = GSD_BACKLIGHT_HELPER_EXIT_CODE_FAILED;
	fprintf (stderr, "Error: Could not find the specified backlight \"%s\"\n", argv[1]);

done:
	if (dp)
		closedir (dp);

	return result;
}

