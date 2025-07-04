# Workspaces Applet build

applet_workspaces_dir = applets_dir + '.workspaces'

custom_target('plugin-file-workspaces',
    input : 'WorkspacesApplet.plugin.in',
    output : 'WorkspacesApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_workspaces_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_workspaces_resources = gnome.compile_resources(
    'workspaces-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_workspaces',
)

applet_workspaces_sources = [
    'WorkspacesApplet.vala',
    'WorkspaceItem.vala',
    'WindowIcon.vala',
    applet_workspaces_resources,
]

applet_workspaces_deps = [
    libpanelplugin_vapi,
    dep_giounix,
    dep_gtk3,
    dep_xfce4windowing,
    dep_peas,
    link_libappsys,
    link_libpanelplugin,
]

shared_library(
    'workspacesapplet',
    applet_workspaces_sources,
    dependencies: applet_workspaces_deps,
    vala_args: [
        '--vapidir', top_vapidir,
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_workspaces_dir,
)

install_data(
    'com.solus-project.workspaces.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
