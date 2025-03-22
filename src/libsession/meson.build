# libsesion is just a vala .a archive

libsession_sources = [
    'libsession.vala',
]

libsession = static_library(
    'session',
    libsession_sources,
    dependencies: [
        dep_glib,
        dep_giounix
    ],
)

link_libsession = declare_dependency(
    link_with: libsession,
    include_directories: include_directories('.'),
)
