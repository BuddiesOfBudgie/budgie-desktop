raven_plugin_mediacontrols_dir = raven_plugin_dir + '.MediaControls'

custom_target('raven-plugin-mediacontrols-file',
    input : 'MediaControls.plugin.in',
    output : 'MediaControls.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : raven_plugin_mediacontrols_dir)

raven_plugin_mediacontrols_sources = [
    'media_controls.vala',
    'mpris_client.vala',
    'mpris_gui.vala',
]

raven_plugin_mediacontrols_deps = [
    libravenplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libravenplugin
]

shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.MediaControls',
    raven_plugin_mediacontrols_sources,
    dependencies: raven_plugin_mediacontrols_deps,
    install: true,
    install_dir: raven_plugin_mediacontrols_dir,
)
