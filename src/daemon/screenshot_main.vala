using Gtk;

/*
 * This file is part of budgie-desktop
 *
 * Author: Jacob Vlijm, David Mohammed
 * Copyright © 2022 Budgie Desktop Developers
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
*/

namespace Budgie {

    [DBus (name = "org.buddiesofbudgie.ScreenshotControl")]
    interface ScreenshotControl : GLib.Object {
        public async abstract void StartMainWindow() throws GLib.Error;
        public async abstract void StartAreaSelect() throws GLib.Error;
        public async abstract void StartWindowScreenshot() throws GLib.Error;
        public async abstract void StartFullScreenshot() throws GLib.Error;
    }

    static bool interactive = false;
    static bool window = false;
    static bool area = false;

    const OptionEntry[] options = {
        { "interactive", 'i', 0, OptionArg.NONE, ref interactive, "Interactively set options" },
        { "window", 'w', 0, OptionArg.NONE, ref window, "Grab a window instead of the entire display" },
        { "area", 'a', 0, OptionArg.NONE, ref area, "Grab an area of the display instead of the entire display" },
        { null }
    };

    public static int main(string[] args) {
        ScreenshotControl control;
        OptionContext ctx;
        ctx = new OptionContext("- Budgie Screenshot");
        ctx.set_help_enabled(true);
        ctx.add_main_entries(options, null);

        try {
            ctx.parse(ref args);
        } catch (Error e) {
            stderr.printf("Error: %s\n", e.message);
            return 0;
        }
        try {
            control = GLib.Bus.get_proxy_sync (
                BusType.SESSION, "org.buddiesofbudgie.ScreenshotControl",
                ("/org/buddiesofbudgie/ScreenshotControl")
            );

            if (interactive) {
                control.StartMainWindow.begin((obj,res) => {
                    try {
                        control.StartMainWindow.end(res);
                    } catch (Error e) {
                        message("Failed to StartMainWindow: %s", e.message);
                    }
                });
                return 0;
            }
            if (area) {
                control.StartAreaSelect.begin((obj,res) => {
                    try {
                        control.StartAreaSelect.end(res);
                    } catch (Error e) {
                        message("Failed to StartAreaSelect: %s", e.message);
                    }
                });
                return 0;
            }
            if (window){
                control.StartWindowScreenshot.begin((obj,res) => {
                    try {
                        control.StartWindowScreenshot.end(res);
                    } catch (Error e) {
                        message("Failed to StartWindowScreenshot: %s", e.message);
                    }
                });
                return 0;
            }

            control.StartFullScreenshot.begin((obj,res) => {
                try {
                    control.StartFullScreenshot.end(res);
                } catch (Error e) {
                    message("Failed to StartFullScreenshot: %s", e.message);
                }
            });
            return 0;
        }
        catch (Error e) {
            stderr.printf ("%s\n", e.message);
            return 1;
        }
    }
}
