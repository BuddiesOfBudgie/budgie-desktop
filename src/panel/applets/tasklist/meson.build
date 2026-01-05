# Tasklist Applet build

applet_tasklist_dir = applets_dir + '.tasklist'

custom_target('plugin-file-tasklist',
    input : 'TasklistApplet.plugin.in',
    output : 'TasklistApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_tasklist_dir)

applet_tasklist_sources = [
    'TasklistApplet.vala',
    'TasklistButton.vala',
    'TasklistButtonPopover.vala',
]

applet_tasklist_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_xfce4windowing,
    link_libpanelplugin,
    meson.get_compiler('c').find_library('m', required: false)
]

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_tasklist_resources = gnome.compile_resources(
    'tasklist-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_tasklist',
)

lib_applet_tasklist_resources = static_library(
    'tasklist-applet-resources',
    applet_tasklist_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

shared_library(
    'tasklistapplet',
    applet_tasklist_sources,
    dependencies: applet_tasklist_deps,
    link_whole: [
        lib_applet_tasklist_resources,
    ],
    vala_args: [
        '--vapidir', top_vapidir,
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_tasklist_dir,
)

install_data(
    'com.solus-project.tasklist.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
