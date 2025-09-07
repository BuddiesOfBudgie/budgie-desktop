sources = files(
  'gnome-settings-bus.c',
  'gnome-settings-profile.c'
)

dbus_ifaces = [
  ['SessionManager', 'gsd-session-manager-glue', 'SessionManager'],
  ['ScreenSaver', 'gsd-screen-saver-glue', 'ScreenSaver'],
  ['Shell', 'gsd-shell-glue', 'Shell'],
  ['Mutter.DisplayConfig', 'gsd-display-config-glue', 'DisplayConfig'],
]

dbus_headers = []

foreach iface: dbus_ifaces
  name = 'org.gnome.' + iface[0]
  c_name = iface[2]

  dbus_sources = gnome.gdbus_codegen(
    iface[1],
    name + '.xml',
    interface_prefix: name + '.',
    namespace: 'Gsd',
    annotations: [name, 'org.gtk.GDBus.C.Name', iface[2]]
  )

  sources += dbus_sources[0]
  dbus_headers += dbus_sources[1]
endforeach

deps = [gio_unix_dep]

if enable_wayland
  deps += wayland_client_dep
endif

libgsd = shared_library(
  'bsd',
  sources: sources + dbus_headers,
  include_directories: top_inc,
  dependencies: deps,
  install: true,
  install_dir: gsd_pkglibdir
)

libgsd_dep = declare_dependency(
  sources: dbus_headers,
  include_directories: include_directories('.'),
  link_with: libgsd
)
