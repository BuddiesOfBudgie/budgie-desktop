# User Indicator Applet build

applet_userindicator_dir = applets_dir + '.user-indicator'

custom_target('plugin-file-userindicator',
    input : 'UserIndicator.plugin.in',
    output : 'UserIndicator.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_userindicator_dir)

applet_userindicator_sources = [
    'DBusInterfaces.vala',
    'UserIndicator.vala',
]

applet_userindicator_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

shared_library(
    'userindicator',
    applet_userindicator_sources,
    dependencies: applet_userindicator_deps,
    vala_args: [
        '--vapidir', join_paths(meson.project_source_root(), 'vapi'),
    ],
    install: true,
    install_dir: applet_userindicator_dir,
)
