raven_plugin_calendar_dir = raven_plugin_dir + '.Calendar'

custom_target('raven-plugin-calendar-file',
    input : 'Calendar.plugin.in',
    output : 'Calendar.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_calendar_dir)

raven_plugin_calendar_gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
raven_plugin_calendar_resources = gnome.compile_resources(
    'raven-plugin-calendar-resources',
    raven_plugin_calendar_gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_raven_plugin_calendar',
)

raven_plugin_calendar_sources = [
    'Calendar.vala',
    raven_plugin_calendar_resources,
]

raven_plugin_calendar_deps = [
    libravenplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libravenplugin
]

shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.Calendar',
    raven_plugin_calendar_sources,
    dependencies: raven_plugin_calendar_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
    ],
    install: true,
    install_dir: raven_plugin_calendar_dir,
)

install_data(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.Calendar.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
