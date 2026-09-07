subdir('backgrounds')
subdir('icons')

# Leveraged in budgie-control-center
version_data = configuration_data()
version_data.set('version', meson.project_version())

version_file = configure_file(
    input: 'budgie-version.xml.in',
    output: 'budgie-version.xml',
    configuration: version_data
)

install_data(
    version_file,
    install_dir: join_paths(datadir, 'budgie')
)

# The Secret portal is only routed to oo7 when oo7 support is enabled
portals_data = configuration_data()

if oo7 == true
    portals_data.set('secret_portal', 'org.freedesktop.impl.portal.Secret=oo7-portal')
else
    portals_data.set('secret_portal', '')
endif

configure_file(
    input: 'budgie-portals.conf.in',
    output: 'budgie-portals.conf',
    configuration: portals_data,
    install_dir: join_paths(datadir, 'xdg-desktop-portal')
)
