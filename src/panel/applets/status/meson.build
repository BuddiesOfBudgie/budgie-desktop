# Status Applet build

applet_status_dir = applets_dir + '.status'

custom_target('plugin-file-status',
    input : 'StatusApplet.plugin.in',
    output : 'StatusApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_status_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

applet_status_resources = gnome.compile_resources(
    'status-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_status',
)

applet_status_sources = [
    'StatusApplet.vala',
    'PowerIndicator.vala',
    'SoundIndicator.vala',
    applet_status_resources
]

if with_bluetooth == true
    applet_status_sources += [
        'BluetoothClient.vala',
        'BluetoothDBus.vala',
        'BluetoothEnums.vala',
        'BluetoothIndicator.vala',
        'BluetoothObexManager.vala'
    ]
endif

applet_status_deps = [
    libpanelplugin_vapi,
    dep_giounix,
    dep_gtk3,
    dep_peas,
    dep_accountsservice,
    link_libpanelplugin,
    dependency('upower-glib', version: '>= 0.99.14'),
    gvc.get_variable('libgvc_dep'),
    meson.get_compiler('c').find_library('m', required: false),
]

shared_library(
    'statusapplet',
    sources: applet_status_sources,
    dependencies: applet_status_deps,
    c_args: [
        '-lm'
    ],
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'accountsservice',
        '--pkg', 'gvc-1.0',
        '--pkg', 'gio-unix-2.0',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
    ],
    install: true,
    install_dir: applet_status_dir,
    install_rpath: rpath_libdir,
)

install_data(
    'com.solus-project.status.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
