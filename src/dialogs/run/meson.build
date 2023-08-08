# Provides budgie-run-dialog binary
rundialog_sources = [
    'LauncherButton.vala',
    'RunDialog.vala'
]

rundialog_deps = [
    dep_gee,
    dep_giounix,
    dep_gtk3,
    libpanelplugin_vapi,
    link_libpanelplugin,
    link_libbudgieprivate,
    link_libappindexer,
    link_libconfig,
    link_libtheme,
]

executable(
    'budgie-run-dialog', rundialog_sources,
    dependencies: rundialog_deps,
    vala_args: [
        '--vapidir', dir_libtheme,
        '--vapidir', dir_libconfig,
        '--pkg', 'theme',
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'budgie-config',
    ],
    install: true,
)
