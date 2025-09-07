/*
 * Copyright (C) 2012      Przemo Firszt <przemo@firszt.eu>
 *
 * The code is derived from gsd-wacom-led-helper.c
 * written by:
 * Copyright (C) 2010-2011 Richard Hughes <richard@hughsie.com>
 * Copyright (C) 2012      Bastien Nocera <hadess@hadess.net>
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
#include <unistd.h>

#include <stdlib.h>
#include "config.h"

#include <glib.h>
#include <locale.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <gudev/gudev.h>

#include "gsd-wacom-oled-constants.h"

#define USB_PIXELS_PER_BYTE 2
#define BT_PIXELS_PER_BYTE 8
#define USB_BUF_LEN OLED_HEIGHT * OLED_WIDTH / USB_PIXELS_PER_BYTE
#define BT_BUF_LEN OLED_WIDTH * OLED_HEIGHT / BT_PIXELS_PER_BYTE

static void
oled_scramble_icon (guchar *image)
{
	guchar buf[USB_BUF_LEN];
	int x, y, i;
	guchar l1, l2, h1, h2;

	for (i = 0; i < USB_BUF_LEN; i++)
		buf[i] = image[i];

	for (y = 0; y < (OLED_HEIGHT / 2); y++) {
		for (x = 0; x < (OLED_WIDTH / 2); x++) {
			l1 = (0x0F & (buf[OLED_HEIGHT - 1 - x + OLED_WIDTH * y]));
			l2 = (0x0F & (buf[OLED_HEIGHT - 1 - x + OLED_WIDTH * y] >> 4));
			h1 = (0xF0 & (buf[OLED_WIDTH - 1 - x + OLED_WIDTH * y] << 4));
			h2 = (0xF0 & (buf[OLED_WIDTH - 1 - x + OLED_WIDTH * y]));

			image[2 * x + OLED_WIDTH * y] = h1 | l1;
			image[2 * x + 1 + OLED_WIDTH * y] = h2 | l2;
		}
	}
}

static void
oled_bt_scramble_icon (guchar *input_image)
{
	unsigned char image[BT_BUF_LEN];
	unsigned mask;
	unsigned s1;
	unsigned s2;
	unsigned r1 ;
	unsigned r2 ;
	unsigned r;
	unsigned char buf[256];
	int i, w, x, y, z;

	for (i = 0; i < BT_BUF_LEN; i++)
		image[i] = input_image[i];

	for (x = 0; x < 32; x++) {
		for (y = 0; y < 8; y++)
			buf[(8 * x) + (7 - y)] = image[(8 * x) + y];
	}

	/* Change 76543210 into GECA6420 as required by Intuos4 WL
	 *        HGFEDCBA      HFDB7531
	 */
	for (x = 0; x < 4; x++) {
		for (y = 0; y < 4; y++) {
			for (z = 0; z < 8; z++) {
				mask = 0x0001;
				r1 = 0;
				r2 = 0;
				i = (x << 6) + (y << 4) + z;
				s1 = buf[i];
				s2 = buf[i+8];
				for (w = 0; w < 8; w++) {
					r1 |= (s1 & mask);
					r2 |= (s2 & mask);
					s1 <<= 1;
					s2 <<= 1;
					mask <<= 2;
				}
				r = r1 | (r2 << 1);
				i = (x << 6) + (y << 4) + (z << 1);
				image[i] = 0xFF & r;
				image[i+1] = (0xFF00 & r) >> 8;
			}
		}
	}
	for (i = 0; i < BT_BUF_LEN; i++)
		input_image[i] = image[i];
}

static void
gsd_wacom_oled_convert_1_bit (guchar *image)
{
	guchar buf[BT_BUF_LEN];
	guchar b0, b1, b2, b3, b4, b5, b6, b7;
	int i;

	for (i = 0; i < BT_BUF_LEN; i++) {
		b0 = 0b10000000 & (image[(4 * i) + 0] >> 0);
		b1 = 0b01000000 & (image[(4 * i) + 0] << 3);
		b2 = 0b00100000 & (image[(4 * i) + 1] >> 2);
		b3 = 0b00010000 & (image[(4 * i) + 1] << 1);
		b4 = 0b00001000 & (image[(4 * i) + 2] >> 4);
		b5 = 0b00000100 & (image[(4 * i) + 2] >> 1);
		b6 = 0b00000010 & (image[(4 * i) + 3] >> 6);
		b7 = 0b00000001 & (image[(4 * i) + 3] >> 3);
		buf[i] = b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7;
	}
	for (i = 0; i < BT_BUF_LEN; i++)
		image[i] = buf[i];
}

static int
gsd_wacom_oled_prepare_buf (guchar *image, GsdWacomOledType type)
{
	int len = 0;

	switch (type) {
	case GSD_WACOM_OLED_TYPE_USB:
		/* Image has to be scrambled for devices connected over USB ... */
		oled_scramble_icon (image);
		len = USB_BUF_LEN;
		break;
	case GSD_WACOM_OLED_TYPE_BLUETOOTH:
		/* ... but for bluetooth it has to be converted to 1 bit colour instead of scrambling */
		gsd_wacom_oled_convert_1_bit (image);
		len = BT_BUF_LEN;
		break;
	case GSD_WACOM_OLED_TYPE_RAW_BLUETOOTH:
		/* Image has also to be scrambled for devices connected over BT using the raw API ... */
		gsd_wacom_oled_convert_1_bit (image);
		len = BT_BUF_LEN;
		oled_bt_scramble_icon (image);
		break;
	default:
		g_assert_not_reached ();
	}

	return len;
}

static gboolean
gsd_wacom_oled_helper_write (const gchar *filename, gchar *buffer, GsdWacomOledType type, GError **error)
{
	guchar *image;
	gint retval;
	gsize length;
	gint fd = -1;
	gboolean ret = TRUE;

	fd = open (filename, O_WRONLY);
	if (fd < 0) {
		ret = FALSE;
		g_set_error (error, 1, 0, "Failed to open filename: %s", filename);
		goto out;
	}

	image = g_base64_decode (buffer, &length);
	if (length != USB_BUF_LEN) {
		ret = FALSE;
		g_set_error (error, 1, 0, "Base64 buffer has length of %" G_GSIZE_FORMAT " (expected %i)", length, USB_BUF_LEN);
		goto out;
	}
	if (!image) {
		ret = FALSE;
		g_set_error (error, 1, 0, "Decoding base64 buffer failed");
		goto out;
	}

	length = gsd_wacom_oled_prepare_buf (image, type);
	if (!length) {
		ret = FALSE;
		g_set_error (error, 1, 0, "Invalid image buffer length");
		goto out;
	}

	retval = write (fd, image, length);
	if (retval != length) {
		ret = FALSE;
		g_set_error (error, 1, 0, "Writing to %s failed", filename);
	}

	g_free (image);
out:
	if (fd >= 0)
		close (fd);
	return ret;
}

static char *
get_oled_sysfs_path (GUdevDevice *device,
		    int          button_num)
{
	char *status;
	char *filename;

	status = g_strdup_printf ("button%d_rawimg", button_num);
	filename = g_build_filename (g_udev_device_get_sysfs_path (device), "wacom_led", status, NULL);
	g_free (status);

	return filename;
}

static char *
get_bt_oled_sysfs_path (GUdevDevice *device, int button_num)
{
	char *status;
	char *filename;

	status = g_strdup_printf ("/oled%i_img", button_num);
	filename = g_build_filename (g_udev_device_get_sysfs_path (device), status, NULL);
	g_free (status);
	return filename;
}

static char *
get_bt_oled_filename (GUdevClient *client, GUdevDevice *device, int button_num)
{
	GUdevDevice *hid_dev;
	const char *dev_uniq;
	GList *hid_list;
	GList *element;
	const char *dev_hid_uniq;
	char *filename = NULL;

	dev_uniq = g_udev_device_get_property (device, "UNIQ");

	hid_list =  g_udev_client_query_by_subsystem (client, "hid");
	element = g_list_first(hid_list);
	while (element) {
		hid_dev = (GUdevDevice*)element->data;
		dev_hid_uniq = g_udev_device_get_property (hid_dev, "HID_UNIQ");
		if (g_strrstr (dev_uniq, dev_hid_uniq)){
			filename = get_bt_oled_sysfs_path (hid_dev, button_num);
			g_object_unref (hid_dev);
			break;
		}
		g_object_unref (hid_dev);
		element = g_list_next(element);
	}
	g_list_free(hid_list);
	return filename;
}

static char *
get_oled_sys_path (GUdevClient      *client,
		   GUdevDevice      *device,
		   int               button_num,
		   gboolean          usb,
		   GsdWacomOledType *type)
{
	GUdevDevice *parent;
	char *filename = NULL;

	/* check for new unified hid implementation first */
	parent = g_udev_device_get_parent_with_subsystem (device, "hid", NULL);
	if (parent) {
		filename = get_oled_sysfs_path (parent, button_num);
		g_object_unref (parent);
		if(g_file_test (filename, G_FILE_TEST_EXISTS)) {
			*type = usb ? GSD_WACOM_OLED_TYPE_USB : GSD_WACOM_OLED_TYPE_RAW_BLUETOOTH;
			return filename;
		}
		g_clear_pointer (&filename, g_free);
	}

	/* old kernel */
	if (usb) {
		parent = g_udev_device_get_parent_with_subsystem (device, "usb", "usb_interface");
		if (!parent)
			goto no_parent;

		filename = get_oled_sysfs_path (parent, button_num);
		*type = GSD_WACOM_OLED_TYPE_USB;
	 } else if (g_strrstr (g_udev_device_get_property (device, "DEVPATH"), "bluetooth")) {
		parent = g_udev_device_get_parent_with_subsystem (device, "input", NULL);
		if (!parent)
			goto no_parent;

		filename = get_bt_oled_filename (client, parent, button_num);
		*type = GSD_WACOM_OLED_TYPE_BLUETOOTH;
	} else {
		g_critical ("Not an expected device: '%s'",
			    g_udev_device_get_device_file (device));
		goto out_err;
	}

	g_object_unref (parent);

	return filename;

no_parent:
	g_debug ("Could not find proper parent device for '%s'",
		 g_udev_device_get_device_file (device));

out_err:
	return NULL;
}


int main (int argc, char **argv)
{
	GOptionContext *context;
	GUdevClient *client;
	GUdevDevice *device;
	int uid, euid;
	char *filename;
	GError *error = NULL;
	const char * const subsystems[] = { "input", NULL };
	int ret = 1;
	gboolean usb;
	GsdWacomOledType type;

	char *path = NULL;
	char *buffer = NULL;
	int button_num = -1;

	const GOptionEntry options[] = {
		{ "path", '\0', 0, G_OPTION_ARG_FILENAME, &path, "Device path for the Wacom device", NULL },
		{ "buffer", '\0', 0, G_OPTION_ARG_STRING, &buffer, "Image to set base64 encoded", NULL },
		{ "button", '\0', 0, G_OPTION_ARG_INT, &button_num, "Which button icon to set", NULL },
		{ NULL}
	};

	/* get calling process */
	uid = getuid ();
	euid = geteuid ();
	if (uid != 0 || euid != 0) {
		g_print ("This program can only be used by the root user\n");
		return 1;
	}

	context = g_option_context_new (NULL);
	g_option_context_set_summary (context, "GNOME Settings Daemon Wacom OLED Icon Helper");
	g_option_context_add_main_entries (context, options, NULL);
	g_option_context_parse (context, &argc, &argv, NULL);

	if (path == NULL ||
	    button_num < 0 ||
	    buffer == NULL) {
		char *txt;

		txt = g_option_context_get_help (context, FALSE, NULL);
		g_print ("%s", txt);
		g_free (txt);

		g_option_context_free (context);

		return 1;
	}
	g_option_context_free (context);

	client = g_udev_client_new (subsystems);
	device = g_udev_client_query_by_device_file (client, path);
	if (device == NULL) {
		g_critical ("Could not find device '%s' in udev database", path);
		goto out;
	}

	if (g_udev_device_get_property_as_boolean (device, "ID_INPUT_TABLET") == FALSE &&
	    g_udev_device_get_property_as_boolean (device, "ID_INPUT_TOUCHPAD") == FALSE) {
		g_critical ("Device '%s' is not a Wacom tablet", path);
		goto out;
	}

	if (g_strcmp0 (g_udev_device_get_property (device, "ID_BUS"), "usb") != 0)
		usb = FALSE;
	else
		usb = TRUE;

	filename = get_oled_sys_path (client, device, button_num, usb, &type);
	if (!filename)
		goto out;

	if (gsd_wacom_oled_helper_write (filename, buffer, type, &error) == FALSE) {
		g_critical ("Could not set OLED icon for '%s': %s", path, error->message);
		g_error_free (error);
		g_free (filename);
		goto out;
	}
	g_free (filename);

	g_debug ("Successfully set OLED icon for '%s', button %d", path, button_num);

	ret = 0;

out:
	g_free (path);
	g_free (buffer);

	g_clear_object (&device);
	g_clear_object (&client);

	return ret;
}
