/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/*
 * All MPRIS DBus interface definitions and MprisClient/MprisManager types
 * live in src/lib/mpris.vala.
 *
 * This file keeps the module-local async helper that the media-controls
 * Raven widget uses, forwarding to the shared mpris_new_client() function.
 */

/**
 * Module-local alias so existing widget code can call new_iface() unchanged.
 */
public async MprisClient? new_iface(string busname) {
	return yield mpris_new_client(busname);
}
