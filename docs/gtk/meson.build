find_program('gtkdocize', required: true)

# Handles gtkdoc installation
gnome = import('gnome')

gnome.gtkdoc(
    meson.project_name(),
    main_sgml: 'budgie-desktop-docs.sgml',
    src_dir: join_paths(meson.project_source_root(), 'src', 'plugin'),
    install: true,
    scan_args: [
        '--ignore-headers=util.h',
    ],
    gobject_typesfile : 'budgie-desktop.types',
    dependencies: [link_libpanelplugin, link_libravenplugin],
)
