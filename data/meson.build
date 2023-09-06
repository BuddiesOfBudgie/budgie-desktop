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

install_data(
    'budgie-portals.conf',
    install_dir: join_paths(datadir, 'xdg-desktop-portal')
)
