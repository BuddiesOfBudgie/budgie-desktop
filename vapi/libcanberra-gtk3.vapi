/***
  This file is part of libcanberra.

  Copyright 2009 Lennart Poettering

  libcanberra is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as
  published by the Free Software Foundation, either version 2.1 of the
  License, or (at your option) any later version.

  libcanberra is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with libcanberra. If not, see
  <http://www.gnu.org/licenses/>.
***/

using Canberra;
using Gdk;
using Gtk;

[CCode (cprefix = "CA_GTK_", lower_case_cprefix = "ca_gtk_", cheader_filename = "canberra-gtk.h")]
namespace CanberraGtk {

        public unowned Context? context_get();
        public unowned Context? context_get_for_screen(Gdk.Screen? screen);

        public int proplist_set_for_widget(Proplist p, Gtk.Widget w);
        public int play_for_widget(Gtk.Widget w, uint32 id, ...);
        public int proplist_set_for_event(Proplist p, Gdk.Event e);
        public int play_for_event(Gdk.Event e, uint32 id, ...);

        public void widget_disable_sounds(Gtk.Widget w, bool enable = false);
}
