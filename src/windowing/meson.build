libwindowing_sources = [
  'dbus.vala',
  'windowing.vala',
  'window_group.vala',
]

libwindowing_deps = [
  dep_giounix,
  dep_xfce4windowing,
]

libwindowing = shared_library(
  'budgie-windowing',
  libwindowing_sources,
  dependencies: libwindowing_deps,
  vala_args: [
    '--vapidir', join_paths(meson.project_source_root(), 'vapi'),
  ],
  version: '0.0.0',
  install: true,
)

# Allow building against libbudgie-windowing
pkgconfig.generate(
    name: 'Budgie Windowing',
    description: 'Budgie Windowing Library',
    version: '1',
    filebase: 'budgie-windowing-1.0',
    libraries: ['-L${libdir}', '-lbudgie-windowing'],
    requires: ['gtk+-3.0 >= 3.24.0']
)

link_libwindowing = declare_dependency(
  link_with: libwindowing,
  dependencies: libwindowing_deps,
  include_directories: include_directories('.'),
).as_static()

# Expose the current directory so that we can use vapidir
dir_libwindowing = meson.current_build_dir()
