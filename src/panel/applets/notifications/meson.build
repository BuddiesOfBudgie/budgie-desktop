# Notifications Applet build

applet_notifications_dir = applets_dir + '.notifications'

custom_target('plugin-file-notifications',
    input : 'NotificationsApplet.plugin.in',
    output : 'NotificationsApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
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

shared_library(
    'notificationsapplet',
    applet_notifications_sources,
    dependencies: applet_notifications_deps,
    install: true,
    install_dir: applet_notifications_dir,
)
