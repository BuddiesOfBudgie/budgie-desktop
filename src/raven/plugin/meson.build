# Provides the core API for budgie 10 raven plugins
gnome = import('gnome')
pkgconfig = import('pkgconfig')

# Generate enums for gobject typing
ravenplugin_enums = gnome.mkenums(
    'budgie-raven-enums',
    sources: [],
    c_template: 'budgie-raven-enums.c.template',
    h_template: 'budgie-raven-enums.h.template',
    install_header: true,
    install_dir: join_paths(get_option('includedir'), 'budgie-desktop'),
)

# Fight meson race conditions..
libravenenum = static_library(
    'raven-enum',
    ravenplugin_enums,
    dependencies: dep_gtk3,
)

link_libravenenum = declare_dependency(
    sources: ravenplugin_enums,
    include_directories: include_directories('.'),
)

# install headers
ravenplugin_headers = [
    'raven-plugin.h',
    'raven-widget.h',
]

ravenplugin_sources = [
    'raven-plugin.c',
    'raven-widget.c',
]

ravenplugin_deps = [
    dep_gtk3,
    dep_peas,
]

# build plugin
libravenplugin = shared_library(
    'budgie-raven-plugin',
    ravenplugin_sources,
    dependencies: [
        ravenplugin_deps,
        link_libravenenum,
    ],
    version: '0.0.0',
    install: true,
)

install_headers(ravenplugin_headers, subdir: 'budgie-desktop')

# Generate .gir
libravenplugin_gir = gnome.generate_gir(
    libravenplugin,
    sources: ravenplugin_sources + ravenplugin_headers + ravenplugin_enums,
    namespace: 'BudgieRavenPlugin',
    nsversion: '1.0',
    dependencies: ravenplugin_deps,
    includes: [
        'GObject-2.0',
        'Gio-2.0',
        'Gtk-3.0',
        'Peas-1.0',
    ],
    symbol_prefix: 'budgie',
    identifier_prefix: 'Budgie',
    header: 'raven-plugin.h',
    install: true,
)

libravenplugin_vapi = gnome.generate_vapi(
    'budgie-raven-plugin-1.0',
    sources: [libravenplugin_gir[0]],
    packages: [
        'gtk+-3.0',
        'gio-unix-2.0',
        'libpeas-1.0',
    ],
    install: true,
)

# Install pkgconfig file to enable building against budgie-plugin
pkgconfig.generate(
    name: 'budgie-raven-plugin',
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
    link_with: libravenplugin,
    dependencies: ravenplugin_deps,
    include_directories: [
        include_directories('.'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libravenplugin = meson.current_source_dir()
