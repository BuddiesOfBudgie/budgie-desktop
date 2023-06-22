# Icon Tasklist Applet build

applet_icontasklist_dir = applets_dir + '.icon-tasklist'

custom_target('plugin-file-icontasklist',
    input : 'IconTasklistApplet.plugin.in',
    output : 'IconTasklistApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_icontasklist_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_icontasklist_resources = gnome.compile_resources(
    'icontasklist-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_icontasklist',
)

lib_applet_icontasklist_resources = static_library(
    'icontasklist-applet-resources',
    applet_icontasklist_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

applet_icontasklist_sources = [
    'ButtonWrapper.vala',
    'DesktopHelper.vala',
    'IconTasklistApplet.vala',
    'IconButton.vala',
    'IconPopover.vala',
    'Icon.vala',
    'animation.vala',
]

applet_icontasklist_deps = [
    libpanelplugin_vapi,
    dep_giounix,
    dep_gtk3,
    dep_peas,
    dep_wnck,
    dep_xfce4windowing,
    dep_gdkx11,
    link_libabomination,
    link_libwindowing,
    link_libappsys,
    link_libpanelplugin,
    meson.get_compiler('c').find_library('m', required: false)
]

shared_library(
    'icontasklistapplet',
    applet_icontasklist_sources,
    dependencies: applet_icontasklist_deps,
    link_whole: [
        lib_applet_icontasklist_resources,
    ],
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gdk-x11-3.0',
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'libwnck-3.0',
        '--pkg', 'libxfce4windowing-0',
        '--vapidir', dir_libappsys,
        '--vapidir', dir_libabomination,
        '--vapidir', dir_libwindowing,
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
    ],
    install: true,
    install_dir: applet_icontasklist_dir,
)

install_data(
    'com.solus-project.icon-tasklist.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
