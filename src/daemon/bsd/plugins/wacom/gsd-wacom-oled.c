/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2013 Przemo Firszt <przemo@firszt.eu>
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
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "config.h"

#include <unistd.h>
#include <math.h>
#include <pango/pango.h>
#include <pango/pangocairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gsd-wacom-oled.h"

#define MAGIC_BASE64		"base64:"		/*Label starting with base64: is treated as already encoded*/
#define MAGIC_BASE64_LEN	strlen(MAGIC_BASE64)

static void
oled_surface_to_image (guchar          *image,
		       cairo_surface_t *surface)
{
	unsigned char *csurf;
	int i, x, y;
	unsigned char lo, hi;

	cairo_surface_flush (surface);
	csurf = cairo_image_surface_get_data (surface);
	i = 0;
	for (y = 0; y < OLED_HEIGHT; y++) {
		for (x = 0; x < (OLED_WIDTH / 2); x++) {
			hi = 0xf0 & csurf[4 * OLED_WIDTH * y + 8 * x + 1];
			lo = 0x0f & (csurf[4 * OLED_WIDTH * y + 8 * x + 5] >> 4);
			image[i] = hi | lo;
			i++;
		}
	}
}

static void
oled_split_text (char *label,
		 char *line1,
		 char *line2)
{
	char delimiters[5] = "+-_ ";
	char **token;
	int token_len[MAX_TOKEN];
	gsize length;
	int i;

	if (g_utf8_strlen (label, LABEL_SIZE) <= MAX_1ST_LINE_LEN) {
		g_utf8_strncpy (line1, label, MAX_1ST_LINE_LEN);
		return;
	}

	token = g_strsplit_set (label, delimiters, -1);

	if (g_utf8_strlen (token[0], LABEL_SIZE) > MAX_1ST_LINE_LEN) {
		g_utf8_strncpy (line1, label, MAX_1ST_LINE_LEN);
		g_utf8_strncpy (line2, label + MAX_1ST_LINE_LEN, LABEL_SIZE - MAX_1ST_LINE_LEN);
		return;
	}

	for (i = 0; token[i] != NULL; i++)
		token_len[i] = g_utf8_strlen (token[i], LABEL_SIZE);

	length = token_len[0];
	i = 0;
	while ((length + token_len[i + 1] + 1) <= MAX_1ST_LINE_LEN) {
		i++;
		length = length + token_len[i] + 1;
	}

	g_utf8_strncpy (line1, label, length);
	g_utf8_strncpy (line2, label + length + 1, LABEL_SIZE - length);

	return;
}

static void
oled_render_text (char             *label,
		  guchar	   *image,
                  gboolean          left_handed)
{
	cairo_t *cr;
	cairo_surface_t *surface;
	PangoFontDescription *desc;
	PangoLayout *layout;
	int width, height;
	double dx, dy;
	char line1[LABEL_SIZE + 1] = "";
	char line2[LABEL_SIZE + 1] = "";
	char *buf;

	oled_split_text (label ,line1, line2);

	buf = g_strdup_printf ("%s\n%s", line1, line2);

	surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, OLED_WIDTH, OLED_HEIGHT);
	cr = cairo_create (surface);

        /* Rotate text so it's seen correctly on the device, or at
         * least from top to bottom for LTR text in vertical modes.
         */
        if (left_handed) {
		cairo_translate (cr, OLED_WIDTH, OLED_HEIGHT);
		cairo_scale (cr, -1, -1);
        }

	cairo_set_source_rgba (cr, 0.0, 0.0, 0.0, 0.99);
	cairo_paint (cr);

	layout = pango_cairo_create_layout (cr);
	pango_layout_set_alignment (layout, PANGO_ALIGN_CENTER);
	pango_layout_set_text (layout, buf, - 1);
	g_free (buf);
	desc = pango_font_description_new ();

	pango_font_description_set_family (desc, "Terminal");
	pango_font_description_set_absolute_size (desc, PANGO_SCALE * 11);
	pango_layout_set_font_description (layout, desc);
	pango_font_description_free (desc);
	pango_layout_get_size (layout, &width, &height);
	width = width/PANGO_SCALE;
	cairo_new_path (cr);

	dx = trunc (((double)OLED_WIDTH - width) / 2);

	if (*line2 == '\0')
		dy = 10;
	else
		dy = 4;

	cairo_move_to (cr, dx, dy);
	cairo_set_source_rgba (cr, 1.0, 1.0, 1.0, 1.0);
	pango_cairo_update_layout (cr, layout);

	pango_cairo_layout_path (cr, layout);
	cairo_fill (cr);

	oled_surface_to_image (image, surface);

	g_object_unref (layout);
	cairo_destroy (cr);

	cairo_surface_destroy (surface);
}

char *
gsd_wacom_oled_gdkpixbuf_to_base64 (GdkPixbuf *pixbuf)
{
	int i, x, y, ch, rs;
	guchar *pix, *p;
	guchar *image;
	guchar lo, hi;
	char *base_string, *base64;

	if (OLED_WIDTH != gdk_pixbuf_get_width (pixbuf))
		return NULL;

	if (OLED_HEIGHT != gdk_pixbuf_get_height (pixbuf))
		return NULL;

	ch = gdk_pixbuf_get_n_channels (pixbuf);
	rs = gdk_pixbuf_get_rowstride (pixbuf);
	pix = gdk_pixbuf_get_pixels (pixbuf);

	image = g_malloc (MAX_IMAGE_SIZE);
	i = 0;
	for (y = 0; y < OLED_HEIGHT; y++) {
		for (x = 0; x < (OLED_WIDTH / 2); x++) {
			p = pix + y * rs + 2 * x * ch;
			hi = 0xf0 & ((p[0] + p[1] + p[2])/ 3 * p[3] / 0xff);
			p = pix + y * rs + ((2 * x) + 1) * ch;
			lo = 0x0f & (((p[0] + p[1] + p[2])/ 3 * p[3] / 0xff) >> 4);
			image[i] = hi | lo;
			i++;
		}
	}

	base_string = g_base64_encode (image, MAX_IMAGE_SIZE);
	base64 = g_strconcat (MAGIC_BASE64, base_string, NULL);
	g_free (base_string);
	g_free (image);

	return base64;
}

static char *
oled_encode_image (char             *label,
                   gboolean          left_handed)
{
	unsigned char *image;

	image = g_malloc (MAX_IMAGE_SIZE);

	/* convert label to image */
	oled_render_text (label, image, left_handed);

	return (g_base64_encode (image, MAX_IMAGE_SIZE));
}

gboolean
set_oled (const gchar  *device_path,
          gboolean      left_handed,
          guint         button,
          char	       *label,
          GError      **error)
{
	char *command;
	gboolean ret;
	char *buffer;
        gint status;

#ifndef HAVE_GUDEV
	/* Not implemented on non-Linux systems */
	return TRUE;
#endif

	if (g_str_has_prefix (label, MAGIC_BASE64)) {
		buffer = g_strdup (label + MAGIC_BASE64_LEN);
        } else {
		buffer = oled_encode_image (label, left_handed);
	}

	g_debug ("Setting OLED label '%s' on button %d (device %s)", label, button, device_path);

	command = g_strdup_printf ("pkexec " LIBEXECDIR "/gsd-wacom-oled-helper --path %s --button %d --buffer %s",
				   device_path, button, buffer);
	ret = g_spawn_command_line_sync (command,
					 NULL,
					 NULL,
					 &status,
					 error);

        if (ret == TRUE && status != 0)
                ret = FALSE;

	g_free (command);

        return ret;
}
