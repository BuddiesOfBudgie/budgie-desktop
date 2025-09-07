sources = files(
  'gpm-common.c',
  'gsd-backlight.c',
  'gsd-power-manager.c',
  'main.c'
)
sources += main_helper_sources

deps = plugins_deps + [
  libcanberra_gtk_dep,
  libcommon_dep,
  libnotify_dep,
  gio_unix_dep,
  gnome_desktop_dep,
  gsd_enums_dep,
  m_dep,
  upower_glib_dep,
  x11_dep,
  dependency('xext')
]

# required for gsd-power-enums-update, which we have
# to compile natively
native_deps = [
  dependency('glib-2.0', native: true),
  dependency('gio-2.0', native:true)
]

if host_is_linux
  deps += gudev_dep
endif

cflags += ['-DLIBEXECDIR="@0@"'.format(gsd_libexecdir)]
cflags += ['-DUSE_GTK=1']

gsd_power = executable(
  'bsd-' + plugin_name,
  sources,
  include_directories: top_inc,
  dependencies: deps,
  c_args: cflags,
  install: true,
  install_rpath: gsd_pkglibdir,
  install_dir: gsd_libexecdir
)

sources = files('gsd-power-enums-update.c')

enums_headers = files(
  'gsm-inhibitor-flag.h',
  'gsm-presence-flag.h'
)

enums = 'gsd-power-enums'

sources += gnome.mkenums(
  enums,
  sources: enums_headers,
  c_template: enums + '.c.in',
  h_template: enums + '.h.in'
)

gsd_power_enums_update = executable(
  'bsd-power-enums-update',
  sources,
  include_directories: top_inc,
  dependencies: native_deps,
  c_args: cflags,
  native: true
)

if host_is_linux
  policy = 'org.buddiesofbudgie.settings-daemon.plugins.power.policy'

  policy_in = configure_file(
    input: policy + '.in.in',
    output: policy + '.in',
    configuration: plugins_conf
  )

  i18n.merge_file(
    input: policy_in,
    output: policy,
    po_dir: po_dir,
    install: true,
    install_dir: join_paths(gsd_datadir, 'polkit-1', 'actions')
  )

  sources = files(
    'gsd-backlight-helper.c',
  )

  deps = [
  ]

  executable(
    'bsd-backlight-helper',
    sources,
    include_directories: top_inc,
    dependencies: deps,
    install: true,
    install_rpath: gsd_pkglibdir,
    install_dir: gsd_libexecdir
  )
endif


