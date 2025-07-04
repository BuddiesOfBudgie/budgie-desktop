# Provides budgie's Raven component

subdir('widgets')

gresource = join_paths(meson.current_source_dir(), 'ui', 'budgie-raven.gresource.xml')

# Compile the assets into the binary
libraven_resources = gnome.compile_resources(
    'budgie-raven-resources',
    gresource,
    source_dir: join_paths(meson.current_source_dir(), 'ui'),
    c_name: 'budgie_raven',
)

lib_libraven_resources = static_library(
    'budgie-raven-resources',
    libraven_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

libraven_sources = [
    'headerwidget.vala',
    'main_view.vala',
    'notification_widget.vala',
    'notifications_group.vala',
    'notifications_view.vala',
    'plugin_manager.vala',
    'raven.vala',
]

libraven_deps = [
    # XXX: Keep this order the same to work around
    # https://github.com/mesonbuild/meson/issues/2096
    link_libbudgieprivate,
    link_libravenplugin,
    link_libpanelplugin,
    libravenplugin_vapi,
    libpanelplugin_vapi,
    dep_giounix,
    dep_gobject_introspection,
    dep_gtk3,
    dep_gtk_layer_shell,
    dep_libuuid,
    dep_peas,
    dep_xfce4windowing,
    link_libconfig,
    link_libtheme,
    gvc.get_variable('libgvc_dep'),
    meson.get_compiler('c').find_library('m', required: false),
]

top_vapidir = join_paths(meson.project_source_root(), 'vapi')

libraven = shared_library(
    'raven', libraven_sources,
    version: '0.0.0',
    dependencies: libraven_deps,
    link_whole: [
        lib_libraven_resources,
    ],
    vala_args: [
        '--vapidir', dir_libtheme,
        '--vapidir', dir_libconfig,
        '--vapidir', top_vapidir,
        '--pkg', 'theme',
        '--pkg', 'budgie-config',
        '--pkg', 'gvc-1.0',
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_rpath: rpath_libdir,
)

link_libraven = declare_dependency(
    link_with: libraven,
    include_directories: include_directories('.'),
)

# gschemas
install_data(
    'com.solus-project.budgie.raven.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
