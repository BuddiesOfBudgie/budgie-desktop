# Provides budgie-polkit component

polkit_config_data = configuration_data()
polkit_config_data.set('libexecdir', libexecdir)

polkit_dialog_desktop = configure_file(
    input: 'budgie-polkit.desktop.in.in',
    output: 'budgie-polkit.desktop.in',
    configuration: polkit_config_data,
)

custom_target('desktop-file-polkit',
    input : polkit_dialog_desktop,
    output : 'org.buddiesofbudgie.BudgiePolkit.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'applications'))

# Compile the assets into the binary
polkit_resources = gnome.compile_resources(
    'budgie-polkit-resources',
    'budgie-polkit.gresource.xml',
    source_dir: '.',
    c_name: 'budgie_polkit',
)

polkit_sources = [
    'polkitdialog.vala',
    polkit_resources,
]

# Don't need APIs from anything older than this
pkversion = '>= 0.105'

polkit_deps = [
    dep_giounix,
    dep_gtk3,
    dep_gtk_layer_shell,
    dep_xfce4windowing,
    link_libconfig,
    link_libtheme,
    link_libsession,
    link_libbudgiewayland,
    dependency('polkit-gobject-1', version: pkversion),
    dependency('polkit-agent-1', version: pkversion),
]

# polkit vapi files are in top vapi dir
pkvapi = join_paths(meson.project_source_root(), 'vapi')

# Need absolute path to gresource
gresource = join_paths(meson.current_source_dir(), 'budgie-polkit.gresource.xml')

executable(
    'budgie-polkit-dialog', polkit_sources,
    dependencies: polkit_deps,
    vala_args: [
        '--vapidir', dir_libtheme,
        '--vapidir', dir_libconfig,
        '--vapidir', pkvapi,
        '--pkg', 'theme',
        '--pkg', 'budgie-config',
        '--pkg', 'polkit-gobject-1',
        '--pkg', 'polkit-agent-1',
        '--pkg', 'posix',
        '--pkg', 'theme',
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    c_args: [
        '-DPOLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE',
        '-Wno-overlength-strings', # gresource generates overlength strings...
    ],
    install: true,
    install_dir: libexecdir,
)
