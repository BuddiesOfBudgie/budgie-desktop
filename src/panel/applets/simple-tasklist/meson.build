# SimpleTasklist Applet build

applet_simpletasklist_dir = applets_dir + '.simple-tasklist'

custom_target('plugin-file-simpletasklist',
    input : 'SimpleTasklistApplet.plugin.in',
    output : 'SimpleTasklistApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_simpletasklist_dir)

applet_simpletasklist_sources = [
    'SimpleTasklistApplet.vala',
    'Button.vala',
    'ButtonPopover.vala',
]

applet_simpletasklist_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_xfce4windowing,
    link_libpanelplugin,
    meson.get_compiler('c').find_library('m', required: false)
]

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_simpletasklist_resources = gnome.compile_resources(
    'simpletasklist-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_simpletasklist',
)

lib_applet_simpletasklist_resources = static_library(
    'simpletasklist-applet-resources',
    applet_simpletasklist_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

shared_library(
    'simpletasklistapplet',
    applet_simpletasklist_sources,
    dependencies: applet_simpletasklist_deps,
    link_whole: [
        lib_applet_simpletasklist_resources,
    ],
    vala_args: [
        '--vapidir', top_vapidir,
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_simpletasklist_dir,
)

install_data(
    'com.solus-project.simple-tasklist.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
