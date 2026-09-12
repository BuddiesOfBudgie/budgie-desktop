applet_keyboardlayout_dir = applets_dir + '.keyboard-layout'

custom_target('plugin-file-keyboardlayout',
    input : 'KeyboardLayoutApplet.plugin.in',
    output : 'KeyboardLayoutApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_keyboardlayout_dir)

gresource = join_paths(meson.current_source_dir(), 'org.budgie-desktop.keyboard-layout.gresource.xml')

# Compile the assets into the binary
applet_keyboardlayout_resources = gnome.compile_resources(
    'keyboard-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_keyboard',
)

applet_keyboardlayout_sources = [
    'input-row.c',
    'input-source.c',
    'keyboard-applet.c',
    'keyboard-header.c',
    'keyboard-plugin.c',
    'keyboard-popover.c',
    'locale-manager.c',
    applet_keyboardlayout_resources,
]

applet_keyboardlayout_sources += gnome.gdbus_codegen(
    'org.freedesktop.locale1',
    'dbus/org.freedesktop.locale1.xml',
    interface_prefix: 'org.freedesktop.locale1' + '.',
    namespace: 'Keyboard',
    annotations: ['org.freedesktop.locale1', 'org.gtk.GDBus.C.Name', 'Locale1'],
)

applet_keyboardlayout_deps = [
    dep_gtk3,
    dep_peas,
    dep_gnomedesktop,
    link_libpanelplugin,
]

shared_library(
    'keyboardlayoutapplet',
    applet_keyboardlayout_sources,
    dependencies: applet_keyboardlayout_deps,
    c_args: [
        '-DGNOME_DESKTOP_USE_UNSTABLE_API',
    ],
    install: true,
    install_dir: applet_keyboardlayout_dir,
)
