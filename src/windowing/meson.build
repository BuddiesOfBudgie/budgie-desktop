libwindowing_sources = [
    'dbus.vala',
    'windowing.vala',
    'window_group.vala',
    'window_mapper.vala',
]

libwindowing_deps = [
    dep_xfce4windowing,
    dep_wnck,
]

libwindowing = static_library(
    'windowing',
    libwindowing_sources,
    dependencies: libwindowing_deps,
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
    ],
    vala_args: [
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gdk-x11-3.0',
        '--pkg', 'libxfce4windowing-0',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
    ]
)

link_libwindowing = declare_dependency(
    link_with: libwindowing,
    include_directories: [
        include_directories('.'),
    ],
)

# Expose the current directory so that we can use vapidir
dir_libwindowing = meson.current_build_dir()
