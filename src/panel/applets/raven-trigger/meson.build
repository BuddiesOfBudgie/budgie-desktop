# Raven Trigger Applet build

applet_raventrigger_dir = applets_dir + '.raven-trigger'

custom_target('plugin-file-raventrigger',
    input : 'RavenTriggerApplet.plugin.in',
    output : 'RavenTriggerApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
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

shared_library(
    'raventriggerapplet',
    applet_raventrigger_sources,
    dependencies: applet_raventrigger_deps,
    install: true,
    install_dir: applet_raventrigger_dir,
)
