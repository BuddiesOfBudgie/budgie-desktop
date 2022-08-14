custom_target('desktop-file-wm',
    input : 'budgie-wm.desktop.in',
    output : 'budgie-wm.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'applications'))


budgie_wm_sources = [
    'background.vala',
    'ibus.vala',
    'keyboard.vala',
    'main.vala',
    'shim.vala',
    'wm.vala',
]

budgie_wm_status_vala_args = []

dep_graphene = dependency('graphene-gobject-1.0', version: '>= 1.10')
dep_mutter = dependency('libmutter-11', version: '>= 43', required: false)
if dep_mutter.found()
    #budgie_wm_status_vala_args += ['-D', 'HAVE_MUTTER_9']
    message('Using libmutter-11 ABI from GNOME 43')
    vapi_mutter = 'libmutter-11'
else
    dep_mutter = dependency('libmutter-10', version: gnome_minimum_version)
    if dep_mutter.found()
        message('Using libmutter-10 ABI from GNOME 42')
        vapi_mutter = 'libmutter-10'
    endif
endif

budgie_wm_deps = [
    link_libconfig,
    dep_mutter,
    dep_gnomedesktop,
    dep_gsettings,
    dep_ibus,
]

budgie_wm_vala_args =  [
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'ibus-1.0',
        '--pkg', 'gnome-desktop-3.0',
        '--pkg', vapi_mutter,
        '--pkg', 'budgie-config',
        '--pkg', 'gsettings-desktop-schemas',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
        '--vapidir', dir_libconfig,
        budgie_wm_status_vala_args,
]

rpath = ''

if dep_mutter.version().version_compare(gnome_minimum_version)
    rpath = dep_mutter.get_pkgconfig_variable('typelibdir')
    budgie_wm_vala_args += ['--girdir', rpath]
endif

executable(
    'budgie-wm', budgie_wm_sources,
    dependencies: budgie_wm_deps,
    include_directories: extra_includes,
    install: true,
    vala_args: budgie_wm_vala_args,
    c_args: [
        '-DGNOME_DESKTOP_USE_UNSTABLE_API',
    ],
    install_rpath: rpath,
)

# gschemas
install_data(
    files('com.solus-project.budgie.wm.gschema.xml',
          '20_solus-project.budgie.wm.gschema.override'),
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
