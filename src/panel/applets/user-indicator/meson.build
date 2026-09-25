# User Indicator Applet build

applet_userindicator_dir = applets_dir + '.user-indicator'

budgie_pot_templates += files('UserIndicator.plugin.desktop.in')

i18n.merge_file(
    input : 'UserIndicator.plugin.desktop.in',
    output : 'UserIndicator.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
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

budgie_pot_targets += shared_library(
    'userindicator',
    applet_userindicator_sources,
    dependencies: applet_userindicator_deps,
    vala_args: [
        '--vapidir', join_paths(meson.project_source_root(), 'vapi'),
    ],
    install: true,
    install_dir: applet_userindicator_dir,
)
