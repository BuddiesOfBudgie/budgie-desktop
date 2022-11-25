raven_plugin_usage_monitor_dir = raven_plugin_dir + '.UsageMonitor'

custom_target('raven-plugin-usage-monitor-file',
    input : 'UsageMonitor.plugin.in',
    output : 'UsageMonitor.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_usage_monitor_dir)

# raven_plugin_usage_monitor_gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
# raven_plugin_usage_monitor_resources = gnome.compile_resources(
#     'raven-plugin-usage-monitor-resources',
#     raven_plugin_usage_monitor_gresource,
#     source_dir: meson.current_source_dir(),
#     c_name: 'budgie_raven_plugin_usage_monitor',
# )

raven_plugin_usage_monitor_sources = [
    'UsageMonitor.vala',
    # raven_plugin_usage_monitor_resources,
]

raven_plugin_usage_monitor_deps = [
    libravenplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libravenplugin
]

shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.UsageMonitor',
    raven_plugin_usage_monitor_sources,
    dependencies: raven_plugin_usage_monitor_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
    ],
    install: true,
    install_dir: raven_plugin_usage_monitor_dir,
)

# install_data(
#     'org.buddiesofbudgie.budgie-desktop.raven.widget.UsageMonitor.gschema.xml',
#     install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
# )
