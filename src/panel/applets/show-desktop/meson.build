# Show Desktop Applet build

applet_showdesktop_dir = applets_dir + '.show-desktop'

budgie_pot_templates += files('ShowDesktopApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'ShowDesktopApplet.plugin.desktop.in',
    output : 'ShowDesktopApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_showdesktop_dir)

applet_showdesktop_sources = [
    'ShowDesktopApplet.vala',
]

applet_showdesktop_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_giounix,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'showdesktopapplet',
    applet_showdesktop_sources,
    dependencies: applet_showdesktop_deps,
    vala_args: [
        '--vapidir', top_vapidir,
    ],
    install: true,
    install_dir: applet_showdesktop_dir,
)
