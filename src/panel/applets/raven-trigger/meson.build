# Raven Trigger Applet build

applet_raventrigger_dir = applets_dir + '.raven-trigger'

budgie_pot_templates += files('RavenTriggerApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'RavenTriggerApplet.plugin.desktop.in',
    output : 'RavenTriggerApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_raventrigger_dir)

applet_raventrigger_sources = [
    'RavenTriggerApplet.vala',
]

applet_raventrigger_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'raventriggerapplet',
    applet_raventrigger_sources,
    dependencies: applet_raventrigger_deps,
    install: true,
    install_dir: applet_raventrigger_dir,
)
