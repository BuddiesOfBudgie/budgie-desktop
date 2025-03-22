# libappsys provides an in-tree ABI for Raven + Panel

libappsys_sources = [
    'AppSystem.vala',
]

libappsys = static_library(
    'appsys',
    libappsys_sources,
    dependencies: [
        dep_giounix,
        dep_gtk3,
        dep_gdkx11,
        dep_wnck,
        link_libconfig,
    ],
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
    ],
)

link_libappsys = declare_dependency(
    link_with: libappsys,
    include_directories: [
        include_directories('.'),
        include_directories('../../'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libappsys = meson.current_build_dir()
