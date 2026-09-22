# Separator Applet build

applet_separator_dir = applets_dir + '.separator'

budgie_pot_templates += files('SeparatorApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'SeparatorApplet.plugin.desktop.in',
    output : 'SeparatorApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
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

budgie_pot_targets += shared_library(
    'separatorapplet',
    applet_separator_sources,
    dependencies: applet_separator_deps,
    install: true,
    install_dir: applet_separator_dir,
)
