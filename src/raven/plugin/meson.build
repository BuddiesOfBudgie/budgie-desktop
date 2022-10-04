# Provides the core API for budgie 10 plugins
gnome = import('gnome')
pkgconfig = import('pkgconfig')

# Generate enums for gobject typing
plugin_enums = gnome.mkenums(
    'budgie-raven-enums',
    sources: [],
    c_template: 'budgie-raven-enums.c.template',
    h_template: 'budgie-raven-enums.h.template',
    install_header: true,
    install_dir: join_paths(get_option('includedir'), 'budgie-desktop'),
)

# Fight meson race conditions..
libenum = static_library(
    'enum',
    plugin_enums,
    dependencies: dep_gtk3,
)

link_libenum = declare_dependency(
    sources: plugin_enums,
    include_directories: include_directories('.'),
)

# install headers
plugin_headers = []

plugin_sources = []

plugin_deps = [
    dep_gtk3,
    dep_peas,
]

# build plugin
libplugin = shared_library(
    'budgie-raven-plugin',
    plugin_sources,
    dependencies: [
        plugin_deps,
        link_libenum,
    ],
    version: '0.0.0',
    install: true,
)

install_headers(plugin_headers, subdir: 'budgie-desktop')

# Install pkgconfig file to enable building against budgie-plugin
pkgconfig.generate(
    name: 'budgie-raven',
    description: 'Budgie Raven Plugin Library',
    version: '2',
    filebase: 'budgie-1.0',
    subdirs: 'budgie-desktop',
    libraries: ['-L${libdir}', '-lbudgie-raven-plugin'],
    requires: [
        'gtk+-3.0 >= 3.22.0',
        'libpeas-1.0 >= 1.8.0',
        'glib-2.0 >= 2.46.0',
        'gio-unix-2.0 >= 2.46.0',
    ],
)


link_libravenplugin = declare_dependency(
    link_with: libplugin,
    dependencies: plugin_deps,
    include_directories: [
        include_directories('.'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libravenplugin = meson.current_source_dir()
