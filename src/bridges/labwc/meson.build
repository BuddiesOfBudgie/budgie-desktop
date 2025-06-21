# Provides the bridges component

bridge_config_data = configuration_data()
bridge_config_data.set('libexecdir', libexecdir)

labwc_desktop = configure_file(
    input: 'org.buddiesofbudgie.labwc-bridge.desktop.in',
    output: 'org.buddiesofbudgie.labwc-bridge.desktop',
    configuration: bridge_config_data,
)

install_data(
    labwc_desktop,
    install_dir: xdg_appdir
)

install_data(
    'labwc_bridge.py',
    install_dir: libexecdir
)

install_data(
    'rc.xml',
    install_dir: join_paths(datadir, 'budgie-desktop', 'labwc')
)

install_data(
    'environment',
    install_dir: join_paths(datadir, 'budgie-desktop', 'labwc')
)

install_data(
    'menu.xml',
    install_dir: join_paths(datadir, 'budgie-desktop', 'labwc')
)
