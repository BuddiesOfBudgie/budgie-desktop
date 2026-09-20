# Provides the bridges component

# The bridge ships as a script rather than a build target, so nothing here
# would otherwise notice a missing import until it failed to start.
if get_option('with-runtime-dependencies')
    pymod = import('python')

    py = pymod.find_installation(
        'python3',
        modules: [
            'dbus',    # dbus-python
            'gi',      # PyGObject
            'psutil',
        ],
        required: true,
    )

    # Importing gi proves nothing about the typelibs, so run the same sequence
    # the bridge opens with
    gi_typelibs = run_command(
        py,
        '-c',
        'import gi; gi.require_version("Pango", "1.0"); from gi.repository import Gio, GLib, Pango',
        check: false,
    )

    if gi_typelibs.returncode() != 0
        error('labwc bridge needs the Gio, GLib and Pango typelibs: ' + gi_typelibs.stderr().strip())
    endif

    # Optional: the bridge logs to stdout when this is absent
    py_systemd = pymod.find_installation(
        'python3',
        modules: ['systemd.journal'],
        required: false,
    )

    if not py_systemd.found()
        message('python-systemd not found, the labwc bridge will log to stdout')
    endif
endif

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
    'labwc-bridge',
    install_dir: libexecdir,
    install_mode: 'rwxr-xr-x'
)

install_subdir(
    'labwc_bridge',
    install_dir: libexecdir,
    exclude_directories: '__pycache__'
)

labwc_files = [
    'rc.xml',
    'menu.xml',
    'keybinds.xml.example',
    'themerc-dark',
    'themerc-darkest',
    'themerc-mid',
    'themerc-light',
    'themerc-frappe'
]

install_data(
    labwc_files,
    install_dir: join_paths(datadir, 'budgie-desktop', 'labwc')
)
