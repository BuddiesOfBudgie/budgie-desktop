subdir('fuzzer')

appindexer_sources = [
    'AppIndex.vala',
    'Category.vala',
    'RelevancyService.vala',
]

libappindexer = shared_library(
    'budgie-appindexer',
    appindexer_sources,
    dependencies: [
        dep_gee,
        dep_giounix,
        dep_gtk3,
        link_libfuzzer,
        libpanelplugin_vapi,
        link_libpanelplugin,
        link_libbudgieprivate,
    ],
    vala_args: [
        '--vapidir', join_paths(meson.project_source_root(), 'vapi'),
        join_paths(meson.project_source_root(), 'src', 'appindexer', 'fuzzer', 'fuzzer-1.0.vapi'),
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
