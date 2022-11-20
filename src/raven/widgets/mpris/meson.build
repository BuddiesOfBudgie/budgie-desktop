raven_plugin_mpris_dir = raven_plugin_dir + '.Mpris'

custom_target('raven-plugin-mpris-file',
    input : 'Mpris.plugin.in',
    output : 'Mpris.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_mpris_dir)

raven_plugin_mpris_sources = [
    'Mpris.vala',
    'MprisClient.vala',
    'MprisGui.vala',
]

raven_plugin_mpris_deps = [
    libravenplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libravenplugin
]

shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.Mpris',
    raven_plugin_mpris_sources,
    dependencies: raven_plugin_mpris_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
    ],
    install: true,
    install_dir: raven_plugin_mpris_dir,
)
