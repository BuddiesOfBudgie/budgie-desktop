
gsd_version = '48.0'
gsd_name = 'budgie-settings-daemon'
version_array = gsd_version.split('.')
gsd_major_version = version_array[0].to_int()

gsd_api_name = '@0@-@1@'.format(gsd_name, gsd_major_version)

glib_min_version = '2.70'

glib_version_def = 'GLIB_VERSION_@0@_@1@'.format(
    glib_min_version.split('.')[0], glib_min_version.split('.')[1])

gsd_prefix = get_option('prefix')
gsd_bindir = join_paths(gsd_prefix, get_option('bindir'))
gsd_datadir = join_paths(gsd_prefix, get_option('datadir'))
gsd_includedir = join_paths(gsd_prefix, get_option('includedir'))
gsd_libdir = join_paths(gsd_prefix, get_option('libdir'))
gsd_libexecdir = join_paths(gsd_prefix, get_option('libexecdir'))
gsd_localedir = join_paths(gsd_prefix, get_option('localedir'))
gsd_sysconfdir = join_paths(gsd_prefix, get_option('sysconfdir'))

gsd_pkgdatadir = join_paths(gsd_datadir, gsd_name)
gsd_pkgincludedir = join_paths(gsd_includedir, gsd_api_name)
gsd_pkglibdir = join_paths(libdir, meson.project_name()) #join_paths(gsd_libdir, gsd_api_name)

gsd_schemadir = join_paths(gsd_datadir, 'glib-2.0', 'schemas')

gsd_xdg_autostart = join_paths(gsd_sysconfdir, 'xdg', 'autostart')

gsd_3_0_api_name = '@0@-@1@'.format(gsd_name, '3.0')
gsd_gtk_modules_directory = join_paths(gsd_libdir, gsd_3_0_api_name, 'gtk-modules')

gsd_buildtype = get_option('buildtype')

host_is_darwin = host_machine.system().contains('darwin')
host_is_linux = host_machine.system().contains('linux')
host_is_linux_not_s390 = host_is_linux and not host_machine.cpu().contains('s390')

cc = meson.get_compiler('c')

config_h = configuration_data()

# defines
set_defines = [
  ['PACKAGE_NAME', gsd_name],
  ['PACKAGE_VERSION', gsd_version],
  # i18n
  ['GETTEXT_PACKAGE', gsd_name]
]

foreach define: set_defines
  config_h.set_quoted(define[0], define[1])
endforeach

# compiler flags
common_flags = ['-DHAVE_CONFIG_H']
compiler_flags = []

if gsd_buildtype.contains('debug')
  common_flags += ['-DG_ENABLE_DEBUG']

  test_cflags = [
    '-Wcast-align',
    '-Wmissing-declarations',
    '-Wmissing-prototypes',
    '-Wnested-externs',
    '-Wno-strict-aliasing',
    '-Wno-sign-compare',
    '-Wpointer-arith',
    '-DGLIB_VERSION_MIN_REQUIRED=' + glib_version_def,
    '-DGLIB_VERSION_MAX_ALLOWED=' + glib_version_def,
  ]

  compiler_flags = cc.get_supported_arguments(test_cflags)
elif gsd_buildtype.contains('release')
  common_flags += ['-DG_DISABLE_CAST_CHECKS']
endif

if get_option('b_ndebug') == 'true'
  common_flags += ['-DG_DISABLE_ASSERT']
endif

#add_project_arguments(common_flags + compiler_flags, language: 'c')

accountsservice_dep = dependency('accountsservice')
glib_dep = dependency('glib-2.0', version: '>=' + glib_min_version)
#geocode_glib_dep = dependency('geocode-glib-2.0', version: '>= 3.26.3', required: false)
#if not geocode_glib_dep.found()
#  geocode_glib_dep = dependency('geocode-glib-1.0', version: '>= 3.10.0')
#endif
gio_dep = dependency('gio-2.0', version: '>= 2.53.0')
gio_unix_dep = dependency('gio-unix-2.0')
gnome_desktop_dep = dependency('gnome-desktop-3.0', version: '>= 3.37.1')
gsettings_desktop_dep = dependency('gsettings-desktop-schemas', version: '>= 46.beta')
gtk_dep = dependency('gtk+-3.0', version: '>= 3.15.3')
gtk_x11_dep = dependency('gtk+-x11-3.0')
#gweather_dep = dependency('gweather4')
libcanberra_gtk_dep = dependency('libcanberra-gtk3')
#libgeoclue_dep = dependency('libgeoclue-2.0', version: '>= 2.3.1')
libnotify_dep = dependency('libnotify', version: '>= 0.7.3')
libpulse_mainloop_glib_dep = dependency('libpulse-mainloop-glib', version: '>= 2.0')
pango_dep = dependency('pango', version: '>= 1.20.0')
polkit_gobject_dep = dependency('polkit-gobject-1', version: '>= 0.114')
upower_glib_dep = dependency('upower-glib', version: '>= 0.99.12')
x11_dep = dependency('x11')
xfixes_dep = dependency('xfixes', version: '>= 6.0')

enable_systemd = false #get_option('systemd')
enable_elogind = false # get_option('elogind')

if enable_systemd and enable_elogind
  error('Only systemd or elogind support should be activated')
elif enable_systemd
  systemd_dep = dependency('systemd', version: '>= 243', required: true)
  libsystemd_dep = dependency('libsystemd', version: '>= 243', required: true)
  systemd_userunitdir = systemd_dep.get_variable(pkgconfig: 'systemduserunitdir',
                                                 pkgconfig_define: ['prefix', gsd_prefix])
elif enable_elogind
  elogind_dep = dependency('libelogind', version: '>= 209', required: true)
endif

config_h.set10('HAVE_SYSTEMD_LIB', enable_systemd or enable_elogind)

m_dep = cc.find_library('m')

# ALSA integration (default enabled)
enable_alsa = false #get_option('alsa')
#assert(enable_alsa or not host_is_linux, 'ALSA is not optional on Linux platforms')

#libgvc = subproject(
#  'gvc',
#  default_options: [
#    'static=true',
#    'alsa=' + enable_alsa.to_string()
#  ]
#)
libgvc_dep = gvc.get_variable('libgvc_dep')

# GUdev integration (default enabled)
enable_gudev = true #get_option('gudev')
if enable_gudev
  gudev_dep = dependency('gudev-1.0')
endif
config_h.set10('HAVE_GUDEV', enable_gudev)
if host_is_linux
  assert(enable_gudev, 'GUdev is not optional on Linux platforms')
endif

has_timerfd_create = cc.has_function('timerfd_create')
config_h.set10('HAVE_TIMERFD', has_timerfd_create)

# Check for wayland dependencies
enable_wayland = false #get_option('wayland')
if enable_wayland
  assert(enable_gudev, 'GUDev support is required for wayland support.')
  wayland_client_dep = dependency('wayland-client')
  wayland_gdk_dep = dependency('gdk-wayland-3.0')
endif
config_h.set10('HAVE_WAYLAND', enable_wayland)

# wacom (disabled for s390/s390x and non Linux platforms)
enable_wacom = host_is_linux_not_s390
if enable_wacom
  assert(enable_gudev, 'GUDev support is required for wacom support.')
  libwacom_dep = dependency('libwacom', version: '>= 0.7')
endif
config_h.set10('HAVE_WACOM', enable_wacom)

# smartcard section
enable_smartcard = false #get_option('smartcard')
if enable_smartcard
  if get_option('gcr3')
    smartcard_deps = dependency('gck-1', version: '>= 3.36')
  else
    smartcard_deps = dependency('gck-2')
  endif
endif

enable_usb_protection = false #get_option('usb-protection')

# CUPS
enable_cups = false #get_option('cups')
if enable_cups
  cups_dep = dependency('cups', version : '>= 1.4', required: false)
  assert(cups_dep.found(), 'CUPS 1.4 or newer not found')

  # FIXME: 1.6 cflags generate a lot of errors
  '''
  cups_cflags = []
  if cups_dep.version().version_compare('>= 1.6')
    cups_cflags += '-D_PPD_DEPRECATED=""'
  endif

  cups_dep = declare_dependency(
    dependencies: cups_dep,
    compile_args: cups_cflags
  )
  '''
endif

# Rfkill
enable_rfkill = true #get_option('rfkill')
assert(enable_rfkill or not host_is_linux, 'rfkill is not optional on Linux platforms')
if enable_rfkill
  assert(cc.has_header('linux/rfkill.h'), 'rfkill support requested but RFKill headers not found')
  assert(enable_gudev, 'GUdev is required for rfkill support')

  udev_dir = '' #get_option('udev_dir')
  if udev_dir == ''
    udev_dir = dependency('udev').get_variable(pkgconfig: 'udevdir')
  endif
endif

# wwan
enable_wwan = false #get_option('wwan')
if enable_wwan
  if get_option('gcr3')
     gcr_dep = dependency('gcr-base-3', version: '>= 3.7.5')
     config_h.set10('HAVE_GCR3', 1)
  else
     gcr_dep = dependency('gcr-4', version: '>= 3.90.0')
  endif
  mm_glib_dep = dependency('mm-glib', version: '>= 1.18')
endif

# Sharing plugin
enable_network_manager = false #get_option('network_manager')
#assert(enable_network_manager or not host_is_linux, 'NetworkManager support is not optional on Linux platforms')
if enable_network_manager
  # network manager
  libnm_dep = dependency('libnm', version: '>= 1.0')
endif
config_h.set10('HAVE_NETWORK_MANAGER', enable_network_manager)

# colord
enable_colord = false #get_option('colord')
if enable_colord
  colord_dep = dependency('colord', version: '>= 1.4.5')
endif

gnome = import('gnome')
i18n = import('i18n')
pkg = import('pkgconfig')

po_dir = podir #join_paths(meson.project_source_root(), 'po')

top_inc = include_directories('.')

subdir('gnome-settings-daemon')
subdir('data')
subdir('plugins')
#subdir('po')

configure_file(
  output: 'config.h',
  configuration: config_h
)

gnome.post_install(
  glib_compile_schemas: true,
)
