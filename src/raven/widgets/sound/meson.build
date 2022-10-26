raven_libsound_sources = [
    'AppSoundControl.vala',
    'StartListening.vala',
]

raven_libsound_deps = [
    dep_giounix,
    dep_gtk3,
    gvc.get_variable('libgvc_dep'),
]

top_vapidir = join_paths(meson.source_root(), 'vapi')

raven_libsound = static_library(
    'budgie-raven-libsound',
    raven_libsound_sources,
    dependencies: raven_libsound_deps,
    vala_args: [
        '--vapidir', top_vapidir,
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gvc-1.0',
    ],
)

link_raven_libsound = declare_dependency(
    link_with: raven_libsound,
    include_directories: include_directories('.'),
)

# subdir('input')
subdir('output')
