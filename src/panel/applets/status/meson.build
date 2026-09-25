# Status Applet build

applet_status_dir = applets_dir + '.status'

budgie_pot_templates += files('StatusApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'StatusApplet.plugin.desktop.in',
    output : 'StatusApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
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

budgie_pot_targets += shared_library(
    'statusapplet',
    sources: applet_status_sources,
    dependencies: applet_status_deps,
    c_args: [
        '-lm'
    ],
    vala_args: [
        '--pkg', 'gvc-1.0',
        '--vapidir', join_paths(meson.project_source_root(), 'vapi'),
    ],
    install: true,
    install_dir: applet_status_dir,
    install_rpath: rpath_libdir,
)

install_data(
    'com.solus-project.status.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
