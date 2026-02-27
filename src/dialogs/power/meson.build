powerdialog_sources = [
    'application.vala',
    'dbus.vala',
    'dialog_button.vala',
    'main.vala',
    'shim.vala',
    'window.vala'
]

powerdialog_deps = [
    dep_giounix,
    dep_gtk3,
    dep_gtk_layer_shell,
    link_libconfig,
    link_libtheme
]

executable(
    'budgie-power-dialog',
    powerdialog_sources,
    dependencies: powerdialog_deps,
    vala_args: [
    '--vapidir', dir_libtheme,
    '--vapidir', dir_libconfig,
    '--pkg', 'budgie-config',
    '--pkg', 'theme'
    ],
    install: true,
    install_dir: libexecdir,
)
