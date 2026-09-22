# Lock Keys Applet build

applet_lockkeys_dir = applets_dir + '.lock-keys'

budgie_pot_templates += files('LockKeysApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'LockKeysApplet.plugin.desktop.in',
    output : 'LockKeysApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_lockkeys_dir)

applet_lockkeys_sources = [
    'LockKeysApplet.vala',
]

applet_lockkeys_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'lockkeysapplet',
    applet_lockkeys_sources,
    dependencies: applet_lockkeys_deps,
    vala_args: [
        '--vapidir', dir_libpanelplugin,
    ],
    install: true,
    install_dir: applet_lockkeys_dir,
)
