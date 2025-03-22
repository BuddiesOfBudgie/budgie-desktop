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
]

applet_tasklist_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_wnck,
    link_libpanelplugin,
]

shared_library(
    'tasklistapplet',
    applet_tasklist_sources,
    dependencies: applet_tasklist_deps,
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
    ],
    install: true,
    install_dir: applet_tasklist_dir,
)
