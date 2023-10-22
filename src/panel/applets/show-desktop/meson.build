# Show Desktop Applet build

applet_showdesktop_dir = applets_dir + '.show-desktop'

custom_target('plugin-file-showdesktop',
    input : 'ShowDesktopApplet.plugin.in',
    output : 'ShowDesktopApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_showdesktop_dir)

applet_showdesktop_sources = [
    'ShowDesktopApplet.vala',
]

applet_showdesktop_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_xfce4windowing,
    link_libpanelplugin,
]

shared_library(
    'showdesktopapplet',
    applet_showdesktop_sources,
    dependencies: applet_showdesktop_deps,
    vala_args: [
        '--vapidir', top_vapidir,
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'libxfce4windowing-0',
    ],
    install: true,
    install_dir: applet_showdesktop_dir,
)
