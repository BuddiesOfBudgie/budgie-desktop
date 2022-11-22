raven_plugin_mediacontrols_dir = raven_plugin_dir + '.Mpris'

custom_target('raven-plugin-mediacontrols-file',
    input : 'MediaControls.plugin.in',
    output : 'MediaControls.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_mediacontrols_dir)

raven_plugin_mediacontrols_sources = [
    'MediaControls.vala',
    'MprisClient.vala',
    'MprisGui.vala',
]

raven_plugin_mediacontrols_deps = [
    libravenplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libravenplugin
]

shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.MediaControls',
    raven_plugin_mediacontrols_sources,
    dependencies: raven_plugin_mediacontrols_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
    ],
    install: true,
    install_dir: raven_plugin_mediacontrols_dir,
)
