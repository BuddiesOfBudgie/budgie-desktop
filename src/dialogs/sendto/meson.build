sendto_sources = [
    'Application.vala',
]

sendto_deps = [
    dep_giounix,
    dep_gtk3,
    link_libconfig,
    link_libtheme
]

executable(
    'budgie-sendto-dialog',
    sendto_sources,
    dependencies: sendto_deps,
    vala_args: [
    '--vapidir', dir_libtheme,
    '--vapidir', dir_libconfig,
    '--pkg', 'budgie-config',
    '--pkg', 'theme'
    ],
    install: true,
    install_dir: libexecdir,
)
