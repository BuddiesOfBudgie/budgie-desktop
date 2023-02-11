# Provides the core API for budgie 10 plugins
gnome = import('gnome')
pkgconfig = import('pkgconfig')

# Generate enums for gobject typing
panel_plugin_enums = gnome.mkenums(
    'budgie-enums',
    sources: [
        'applet.h',
        'popover.h',
    ],
    c_template: 'budgie-enums.c.template',
    h_template: 'budgie-enums.h.template',
    install_header: true,
    install_dir: join_paths(get_option('includedir'), 'budgie-desktop'),
)

# Fight meson race conditions..
libpanelenum = static_library(
    'enum',
    panel_plugin_enums,
    dependencies: dep_gtk3,
)

link_libpanelenum = declare_dependency(
    sources: panel_plugin_enums,
    include_directories: include_directories('.'),
)

# install headers
panel_plugin_headers = [
	'plugin.h',
	'applet.h',
	'applet-info.h',
    'popover.h',
	'popover-manager.h',
]

panel_plugin_sources = [
    'applet.c',
    'applet-info.c',
    'plugin.c',
    'popover.c',
    'popover-manager.c',
]

panel_plugin_deps = [
    dep_gtk3,
    dep_peas,
]

# build plugin
libpanelplugin = shared_library(
    'budgie-plugin',
    panel_plugin_sources,
    dependencies: [
        panel_plugin_deps,
        link_libpanelenum,
    ],
    version: '0.0.0',
    install: true,
)

install_headers(panel_plugin_headers, subdir: 'budgie-desktop')

# Generate .gir
libpanelplugin_gir = gnome.generate_gir(
    libpanelplugin,
    sources: panel_plugin_sources + panel_plugin_headers + panel_plugin_enums,
    namespace: 'Budgie',
    nsversion: '1.0',
    dependencies: panel_plugin_deps,
    includes: [
        'GObject-2.0',
        'Gio-2.0',
        'Gtk-3.0',
        'Peas-1.0',
    ],
    symbol_prefix: 'budgie',
    identifier_prefix: 'Budgie',
    install: true,
    extra_args: [
        '--warn-all',
        '--c-include', 'plugin.h',
    ],
)

libpanelplugin_vapi = gnome.generate_vapi(
    'budgie-1.0',
    sources: [libpanelplugin_gir[0]],
    packages: [
        'gtk+-3.0',
        'gio-unix-2.0',
        'libpeas-1.0',
    ],
    install: true,
)

# Install pkgconfig file to enable building against budgie-plugin
pkgconfig.generate(
    name: 'Budgie',
    description: 'Budgie Plugin Library',
    version: '2',
    filebase: 'budgie-1.0',
    subdirs: 'budgie-desktop',
    libraries: ['-L${libdir}', '-lbudgie-plugin'],
    requires: [
        'gtk+-3.0 >= 3.22.0',
        'libpeas-1.0 >= 1.8.0',
        'glib-2.0 >= 2.46.0',
        'gio-unix-2.0 >= 2.46.0',
    ],
)


link_libpanelplugin = declare_dependency(
    link_with: libpanelplugin,
    dependencies: panel_plugin_deps,
    include_directories: [
        include_directories('.'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libpanelplugin = meson.current_source_dir()
