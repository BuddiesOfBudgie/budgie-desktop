libpanelpluginmanager_deps = [
  link_libconfig,
  link_libpanelplugin,
  dep_glib,
  dep_gobject_introspection,
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
  ],
  c_args: [
      '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
  ]
)

link_libpanelpluginmanager = declare_dependency(
  link_with: libpanelpluginmanager,
  include_directories: include_directories('.')
)
