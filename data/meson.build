subdir('backgrounds')
subdir('icons')
subdir('man')

if with_gtk_doc == true
    subdir('gtk-docs')
endif

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
