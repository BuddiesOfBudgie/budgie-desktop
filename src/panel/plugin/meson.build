libpanelpluginmanager_deps = [
  link_libconfig,
  link_libpanelplugin,
  dep_glib,
  dep_girepository,
  dep_peas,
]

libpanelpluginmanager_sources = [
  'plugin-manager.c',
]

libpanelpluginmanager_headers = [
  'plugin-manager.h',
]

libpanelpluginmanager = static_library(
  'panelpluginmanager',
  libpanelpluginmanager_sources,
  dependencies: libpanelpluginmanager_deps,
  include_directories: [
    include_directories('.'),
  ]
)

link_libpanelpluginmanager = declare_dependency(
  link_with: libpanelpluginmanager,
  include_directories: include_directories('.')
)
