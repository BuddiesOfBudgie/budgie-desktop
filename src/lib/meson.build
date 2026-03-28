# libbudgieprivate provides a private ABI for Raven + Panel

libbudgieprivate_sources = [
    'animation.vala',
    'application.vala',
    'toplevel.vala',
    'shadow.vala',
    'manager.vala',
    'notification.vala',
    'switcheroo.vala',
]

libbudgieprivate = shared_library(
    'budgie-private',
    libbudgieprivate_sources,
    dependencies: [
        libpanelplugin_vapi,
        dep_peas,
        dep_giounix,
        dep_gtk3,
        meson.get_compiler('c').find_library('m', required: false),
        link_libpanelplugin,
    ],
    version: '0.0.0',
    install: true,
)

link_libbudgieprivate = declare_dependency(
    link_with: libbudgieprivate,
    dependencies: [
        link_libpanelplugin,
    ],
    include_directories: [
        include_directories('.'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libbudgieprivate = meson.current_source_dir()

# create static library for our libxfce4windowing wrapper
wayland_sources = files(
    'waylandclient.vala',
)

wayland_deps = [
    dep_giounix,
    dep_gtk3,
    dep_xfce4windowing,
    meson.get_compiler('c').find_library('m', required: false),
]

top_vapidir = join_paths(meson.project_source_root(), 'vapi')

# Build as a static library
libbudgiewayland = static_library(
    'budgie-waylandclient',
    wayland_sources,
    dependencies: wayland_deps,
    vala_header: 'budgie-waylandclient.h',
    vala_vapi: 'budgie-waylandclient.vapi',
    install: false,  # Don't install - internal use only
    vala_args: [
        '--vapidir', top_vapidir
    ],
)

# Create dependency object for linking
link_libbudgiewayland = declare_dependency(
    link_with: libbudgiewayland,
    include_directories: include_directories('.'),
)
