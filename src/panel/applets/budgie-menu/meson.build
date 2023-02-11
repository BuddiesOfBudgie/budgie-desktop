# Budgie menu build

applet_budgiemenu_dir = applets_dir + '.budgie-menu'

custom_target('plugin-file-budgiemenuapplet',
    input : 'BudgieMenu.plugin.in',
    output : 'BudgieMenu.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_budgiemenu_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_budgiemenu_resources = gnome.compile_resources(
    'budgiemenuapplet-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_budgiemenuapplet',
)

lib_applet_budgiemenu_resources = static_library(
    'budgiemenu-applet-resources',
    applet_budgiemenu_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

applet_budgiemenu_sources = [
    'BudgieMenu.vala',
    'BudgieMenuButtons.vala',
    'BudgieMenuWindow.vala',
    'IconChooser.vala',
    'DBusInterfaces.vala',
    'OverlayMenus.vala',
    'UserButton.vala',
    'MenuItem.vala',
    'views/ListView.vala',
    'views/View.vala',
]

applet_budgiemenu_deps = [
    libpanelplugin_vapi,
    dep_gee,
    dep_giounix,
    dep_gtk3,
    dep_peas,
    dep_accountsservice,
    dep_cairo,
    link_libappindexer,
    link_libpanelplugin,
]

shared_library(
    'budgiemenuapplet',
    applet_budgiemenu_sources,
    dependencies: applet_budgiemenu_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gio-unix-2.0',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    link_whole: [
        lib_applet_budgiemenu_resources,
    ],
    install: true,
    install_dir: applet_budgiemenu_dir,
)

install_data(
    'com.solus-project.budgie-menu.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
