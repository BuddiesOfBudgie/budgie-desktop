raven_plugin_sound_dir = raven_plugin_dir + '.Sound'

custom_target('raven-plugin-sound-file',
    input : 'Sound.plugin.in',
    output : 'Sound.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_sound_dir)

raven_plugin_sound_sources = [
    'Sound.vala',
]

raven_plugin_sound_deps = [
    libravenplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libravenplugin
]

shared_library(
    'org.buddiesofbudgie.Sound',
    raven_plugin_sound_sources,
    dependencies: raven_plugin_sound_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
    ],
    install: true,
    install_dir: raven_plugin_sound_dir,
)
