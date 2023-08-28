raven_plugin_sound_input_dir = raven_plugin_dir + '.SoundInput'

custom_target('raven-plugin-sound-input-file',
    input : 'SoundInput.plugin.in',
    output : 'SoundInput.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_sound_input_dir)

raven_plugin_sound_input_gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
raven_plugin_sound_input_resources = gnome.compile_resources(
    'raven-plugin-sound-input-resources',
    raven_plugin_sound_input_gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_raven_plugin_sound_input',
)

raven_plugin_sound_input_sources = [
    'sound_input.vala',
    raven_plugin_sound_input_resources,
]

raven_plugin_sound_input_deps = [
    libravenplugin_vapi,
    dep_giounix,
    dep_gtk3,
    dep_peas,
    link_libravenplugin,
    gvc.get_variable('libgvc_dep'),
    meson.get_compiler('c').find_library('m', required: true),
]

top_vapidir = join_paths(meson.source_root(), 'vapi')

shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.SoundInput',
    raven_plugin_sound_input_sources,
    dependencies: raven_plugin_sound_input_deps,
    vala_args: [
        '--vapidir', top_vapidir,
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gvc-1.0',
    ],
    install: true,
    install_dir: raven_plugin_sound_input_dir,
    install_rpath: rpath_libdir,
)

install_data(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.SoundInput.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
