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
]

applet_simpletasklist_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_wnck, # via Abomination
    dep_gdkx11, # via Abomination
    dep_xfce4windowing,
    link_libpanelplugin,
]

shared_library(
    'simpletasklistapplet',
    applet_simpletasklist_sources,
    dependencies: applet_simpletasklist_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gdk-x11-3.0',
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'libwnck-3.0',
        '--pkg', 'libxfce4windowing-0',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
    ],
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
    ],
    install: true,
    install_dir: applet_simpletasklist_dir,
)
