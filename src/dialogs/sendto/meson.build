sendto_sources = [
    'Application.vala',
    'Dialog/DeviceRow.vala',
    'Dialog/FileReceiver.vala',
    'Dialog/FileSender.vala',
    'Dialog/ScanDialog.vala',
    'Services/Adapter.vala',
    'Services/Device.vala',
    'Services/Manager.vala',
    'Services/ObexAgent.vala',
    'Services/Session.vala',
    'Services/Transfer.vala',
]

sendto_deps = [
    dep_gee,
    dep_glib,
    dep_gtk3,
    link_libconfig,
    link_libtheme,
]

executable(
    'org.buddiesofbudgie.sendto',
    sendto_sources,
    dependencies: sendto_deps,
    vala_args: [
        '--vapidir', dir_libtheme,
        '--vapidir', dir_libconfig,
        '--pkg', 'budgie-config',
        '--pkg', 'theme'
    ],
    install: true,
)

install_data(
    'org.buddiesofbudgie.sendto-daemon.desktop',
    install_dir: join_paths(confdir, 'xdg', 'autostart')
)

install_data(
    'org.buddiesofbudgie.sendto.desktop',
    install_dir: join_paths(datadir, 'applications')
)
