# Notifications Applet build

applet_notifications_dir = applets_dir + '.notifications'

budgie_pot_templates += files('NotificationsApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'NotificationsApplet.plugin.desktop.in',
    output : 'NotificationsApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_notifications_dir)

applet_notifications_sources = [
    'NotificationsApplet.vala',
]

applet_notifications_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'notificationsapplet',
    applet_notifications_sources,
    dependencies: applet_notifications_deps,
    install: true,
    install_dir: applet_notifications_dir,
)
