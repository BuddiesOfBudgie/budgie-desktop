raven_plugin_mediacontrols_dir = raven_plugin_dir + '.MediaControls'

budgie_pot_templates += files('MediaControls.plugin.desktop.in')

i18n.merge_file(
    input : 'MediaControls.plugin.desktop.in',
    output : 'MediaControls.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
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
    link_libravenplugin,
    link_libbudgiempris,
]

budgie_pot_targets += shared_library(
    'org.buddiesofbudgie.budgie-desktop.raven.widget.MediaControls',
    raven_plugin_mediacontrols_sources,
    dependencies: raven_plugin_mediacontrols_deps,
    install: true,
    install_dir: raven_plugin_mediacontrols_dir,
)
