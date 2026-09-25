applet_trash_dir = applets_dir + '.trash'

budgie_pot_templates += files('TrashApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'TrashApplet.plugin.desktop.in',
    output : 'TrashApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_trash_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

applet_trash_resources = gnome.compile_resources(
    'trash-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_trash',
)

applet_trash_sources = [
    'trash_applet.c',
    'trash_button_bar.c',
    'trash_enum_types.c',
    'trash_info.c',
    'trash_item_row.c',
    'trash_manager.c',
    'trash_notify.c',
    'trash_popover.c',
    'trash_plugin.c',
    'trash_settings.c',
    applet_trash_resources,
]

applet_trash_deps = [
    dep_gtk3,
    dep_notify,
    dep_peas,
    link_libpanelenum,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'trashapplet',
    applet_trash_sources,
    dependencies: applet_trash_deps,
    install: true,
    install_dir: applet_trash_dir,
)

install_data(
    'com.solus-project.trash.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
