libfuzzer_deps = [
    dep_glib,
]

libfuzzer_sources = [
    'fuzzer.c',
]

libfuzzer = static_library(
    'fuzzer',
    libfuzzer_sources,
    dependencies: libfuzzer_deps,
    include_directories: [
        include_directories('.'),
    ]
)

link_libfuzzer = declare_dependency(
    link_with: libfuzzer,
    include_directories: include_directories('.'),
)
