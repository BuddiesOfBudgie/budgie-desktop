# Separator Applet build

applet_separator_dir = applets_dir + '.separator'

custom_target('plugin-file-separator',
    input : 'SeparatorApplet.plugin.in',
    output : 'SeparatorApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_separator_dir)

applet_separator_sources = [
    'SeparatorApplet.vala',
]

applet_separator_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

shared_library(
    'separatorapplet',
    applet_separator_sources,
    dependencies: applet_separator_deps,
    install: true,
    install_dir: applet_separator_dir,
)
