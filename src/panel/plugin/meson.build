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
  ]
)

link_libpanelpluginmanager = declare_dependency(
  link_with: libpanelpluginmanager,
  include_directories: include_directories('.')
)

# Generate .gir
# libpanelpluginmanager_gir = gnome.generate_gir(
#     libpanelpluginmanager,
#     sources: libpanelpluginmanager_sources + libpanelpluginmanager_headers,
#     namespace: 'BudgiePanel',
#     nsversion: '2.0',
#     dependencies: libpanelpluginmanager_deps,
#     includes: [
#         'Budgie-2.0',
#         'GObject-2.0',
#         'Gio-2.0',
#         'Peas-2',
#     ],
#     symbol_prefix: 'budgie',
#     identifier_prefix: 'Budgie',
#     header: 'plugin-manager.h',
#     install: false,
#     extra_args: [
#         '--c-include=plugin-manager.h',
#         '--warn-all',
#     ]
# )

# libpanelpluginmanager_vapi = gnome.generate_vapi(
#     'budgiepanel-2.0',
#     sources: [libpanelpluginmanager_gir[0]],
#     packages: [
#         'libpeas-2',
#     ],
#     install: false,
# )
