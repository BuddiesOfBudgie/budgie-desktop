common_inc = include_directories('.')

sources = files(
  'gsd-input-helper.c',
  'gsd-settings-migrate.c',
  'gsd-shell-helper.c'
)

main_helper_sources = files(
  'gsd-main-helper.c',
)

resource_data = files('gtk.css')

sources += gnome.compile_resources(
  'gsd-resources',
  'gsd.gresources.xml',
  c_name: 'gsd',
  dependencies: resource_data
)

deps = plugins_deps + [
  gnome_desktop_dep,
  gtk_x11_dep,
  x11_dep,
  dependency('kbproto'),
  dependency('xi')
]

ldflags = []
if host_is_darwin
  ldflags += ['-Wl,-bundle_loader,@0@'.format(join_paths(), meson.project_build_root(), gsd_name, gsd_name)]
endif

libcommon = static_library(
  plugin_name,
  sources: sources,
  include_directories: top_inc,
  dependencies: deps,
  c_args: cflags,
  link_args: ldflags
)

libcommon_dep = declare_dependency(
  include_directories: common_inc,
  link_with: libcommon
)
