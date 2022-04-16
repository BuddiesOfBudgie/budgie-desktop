appindexer_sources = [
    'AppIndex.vala',
    'Application.vala',
    'Category.vala',
    'RelevancyService.vala',
    'Switcheroo.vala'
]

libappindexer = shared_library(
    'appindexer',
    appindexer_sources,
    dependencies: [
        dep_gee,
        dep_gtk3,
    ],
    vala_args: [
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gio-unix-2.0',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
    ],
    version: '0.0.0',
    install: true,
)

link_libappindexer = declare_dependency(
    link_with: libappindexer,
    include_directories: [
        include_directories('.'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libappindexer = meson.current_source_dir()
