raven_plugin_sound_output_dir = raven_plugin_dir + '.SoundOutput'

custom_target('raven-plugin-sound-output-file',
    input : 'SoundOutput.plugin.in',
    output : 'SoundOutput.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_sound_output_dir)

raven_plugin_sound_output_sources = [
    'SoundOutput.vala',
]

raven_plugin_sound_output_deps = [
    libravenplugin_vapi,
    dep_giounix,
    dep_gtk3,
    dep_peas,
    link_libravenplugin,
    link_raven_libsound,
    gvc.get_variable('libgvc_dep'),
    meson.get_compiler('c').find_library('m', required: true),
]

top_vapidir = join_paths(meson.source_root(), 'vapi')

shared_library(
    'org.buddiesofbudgie.SoundOutput',
    raven_plugin_sound_output_sources,
    dependencies: raven_plugin_sound_output_deps,
    vala_args: [
        '--vapidir', top_vapidir,
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gvc-1.0',
    ],
    install: true,
    install_dir: raven_plugin_sound_output_dir,
)
