project(
    'budgie-desktop',
    ['c', 'vala'],
    version: '10.9.2',
    license: [
        'GPL-2.0',
        'LGPL-2.1',
    ],
    default_options: [
        'c_std=c11',
        'warning_level=3'
    ],
)

# Vala generates bad C code and missing these on gcc 14 will cause FTBFS
# Additionally, Meson 1.4 unhides warnings from valac-generated C code,
# which causes unreadable logspam. Reenables prior behavior.
am_cflags = [
    '-w',
    '-Wno-incompatible-pointer-types',
    '-Wno-implicit-function-declaration',
]
add_global_arguments(am_cflags, language: 'c')

meson.add_install_script('scripts/mesonPostInstall.sh')

fs = import('fs')

# Budgie needs a minimum GNOME 40 stack with GTK 3.24+
gnome_minimum_version = '>= 40.0'

dep_gtk3 = dependency('gtk+-3.0', version: '>= 3.24.0')
dep_glib = dependency('glib-2.0', version: '>= 2.64.0')
dep_gee = dependency('gee-0.8', version: '>= 0.20.0')
dep_giounix = dependency('gio-unix-2.0', version: '>= 2.64.0')
dep_peas = dependency('libpeas-1.0', version: '>= 1.26.0')
dep_gdkx11 = dependency('gdk-x11-3.0', version: '>= 3.24.0')
dep_libuuid = dependency('uuid')
dep_vala = dependency('vapigen', version: '>= 0.52.5')
dep_gst = dependency('gstreamer-1.0')
dep_cairo = dependency('cairo')
dep_gtk_layer_shell = dependency('gtk-layer-shell-0', version: '>= 0.8.0')

# Needed for Budgie Menu
dep_cairo = dependency('cairo', version: '>= 1.15.10')

# Needed for keyboardy bits
dep_ibus = dependency('ibus-1.0', version: '>= 1.5.10')
dep_notify = dependency('libnotify', version: '>= 0.7')
dep_gnomedesktop = dependency('gnome-desktop-3.0', version: gnome_minimum_version)
dep_gsettings = dependency('gsettings-desktop-schemas', version: gnome_minimum_version)
dep_gsd = dependency('gnome-settings-daemon', version: gnome_minimum_version)

# wnck used all over the place..
dep_wnck = dependency('libwnck-3.0', version: '>= 3.36.0')

# accountsservice in multiple applets
dep_accountsservice = dependency('accountsservice', version: '>= 0.6.55')

# Needed for Daemon (notifications)
dep_canberra = dependency('libcanberra')
dep_canberra_gtk3 = dependency('libcanberra-gtk3')

# Needed for window tracking
dep_xfce4windowing = dependency('libxfce4windowing-0', version: '>= 4.19.7')

# Needed for upower interaction
dep_upower = dependency('upower-glib', version: '>= 0.99.8')

# Create config.h
cdata = configuration_data()

if get_option('with-runtime-dependencies')
    find_program('wlopm', required: true)
    find_program('swayidle', required: true)
    found_gtklock = find_program('gtklock', required: false)
    if found_gtklock.found() == false
        find_program('swaylock', required: true)
    endif
endif

# Inspired by https://github.com/GNOME/recipes/blob/master/meson.build
package_version = meson.project_version()

ci = get_option('ci')
if fs.exists('.git') and ci == false
    git = find_program('git')
    git_version = run_command('git', ['rev-parse', 'HEAD'], check: true)
    package_version += ' (git-'+git_version.stdout().strip()+')'
endif

cdata.set_quoted('PACKAGE_VERSION', package_version)

# Make gettext work
cdata.set_quoted('GETTEXT_PACKAGE', meson.project_name())
add_global_arguments('-DGETTEXT_PACKAGE="budgie-desktop"', language: 'c')

# Globals that we need
prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
libexecdir = join_paths(prefix, get_option('libexecdir'), meson.project_name())
confdir = join_paths(prefix, get_option('sysconfdir'))
datadir = join_paths(prefix, get_option('datadir'))
localedir = join_paths(prefix, get_option('localedir'))
podir = join_paths(meson.source_root(), 'po')

cdata.set_quoted('DATADIR', datadir)
cdata.set_quoted('SYSCONFDIR', confdir)
cdata.set_quoted('LOCALEDIR', localedir)
cdata.set_quoted('PACKAGE_URL', 'https://buddiesofbudgie.org')

# Handle i18n on the .desktop file
# Originally stolem from TingPing:
# https://github.com/vinszent/gnome-twitch/blob/master/data/meson.build
# Later changed to use intltool as we use _Key style files
intltool = find_program('intltool-merge')

# Make sure this is accessible to panel applet builds
plugin_libdir = join_paths(libdir, meson.project_name(), 'plugins')
plugin_datadir = join_paths(datadir, meson.project_name(), 'plugins')

# and raven widget builds
raven_plugin_libdir = join_paths(libdir, meson.project_name(), 'raven-plugins')
raven_plugin_datadir = join_paths(datadir, meson.project_name(), 'raven-plugins')

cdata.set_quoted('MODULEDIR', plugin_libdir)
cdata.set_quoted('MODULE_DATA_DIR', plugin_datadir)
cdata.set_quoted('RAVEN_PLUGIN_LIBDIR', raven_plugin_libdir)
cdata.set_quoted('RAVEN_PLUGIN_DATADIR', raven_plugin_datadir)

if prefix == '/usr' or prefix == '/usr/local'
    cdata.set('HAS_SECONDARY_PLUGIN_DIRS', true)

    if prefix == '/usr'
        secondary_libdir_root = join_paths(prefix, 'local', get_option('libdir'), meson.project_name())
        secondary_datadir_root = join_paths(prefix, 'local', get_option('datadir'), meson.project_name())
    else
        secondary_libdir_root = join_paths('/usr', get_option('libdir'), meson.project_name())
        secondary_datadir_root = join_paths('/usr', get_option('datadir'), meson.project_name())
    endif

    cdata.set_quoted('MODULEDIR_SECONDARY', join_paths(secondary_libdir_root, 'plugins'))
    cdata.set_quoted('MODULE_DATA_DIR_SECONDARY', join_paths(secondary_datadir_root, 'plugins'))
    cdata.set_quoted('RAVEN_PLUGIN_LIBDIR_SECONDARY', join_paths(secondary_libdir_root, 'raven-plugins'))
    cdata.set_quoted('RAVEN_PLUGIN_DATADIR_SECONDARY', join_paths(secondary_datadir_root, 'raven-plugins'))
endif

with_hibernate = get_option('with-hibernate')
if with_hibernate == true
  add_project_arguments('-D', 'WITH_HIBERNATE', language: 'vala')
endif

with_libuuid_time_safe = get_option('with-libuuid-time-safe')
if with_libuuid_time_safe == true
  add_project_arguments('-D', 'with_libuuid_time_safe', language: 'vala')
endif

with_stateless = get_option('with-stateless')
if with_stateless == true
    warning('Only use stateless option with a supported OS like Solus')
endif

xdg_appdir = get_option('xdg-appdir')
if xdg_appdir == ''
    if with_stateless == true
        xdg_appdir = join_paths(datadir, 'xdg', 'autostart')
    else
        xdg_appdir = join_paths(get_option('sysconfdir'), 'xdg', 'autostart')
    endif
endif

# Bluetooth option. BSD systems have no Bluetooth stack, so this allows
# BSD systems to compile and run Budgie.
with_bluetooth = get_option('with-bluetooth')
if with_bluetooth == true
    add_project_arguments('-D', 'WITH_BLUETOOTH', language: 'vala')
endif

# GVC rpath. it's evil, but gvc will bomb out glib2 due to static linking weirdness now,
# so we have to use a shared library to prevent multiple registration of the same types..
rpath_libdir = join_paths(libdir, meson.project_name())

# Write config.h
configure_file(
    output: 'config.h',
    configuration: cdata,
)

# Enable others to find this .h file
extra_includes = [
    include_directories('.'),
]

# Determine if polkit is allowed.
with_polkit = get_option('with-polkit')

# Get gvc built before we do anything
gvc = subproject('gvc',
    default_options: [
        'static=false',
        'pkglibdir=@0@'.format(rpath_libdir),
        'package_name=' + meson.project_name(),
        'package_version=' + meson.project_version(),
        'warning_level=0',
    ],
)

# Prep translations prior to build
subdir('po')

# Now build Budgie proper
subdir('src')

# Take care of documentation
with_gtk_doc = get_option('with-gtk-doc')
subdir('docs')

# And lastly, data bits
subdir('data')

report = [
    '    Build configuration:',
    '    ====================',
    '',
    '    prefix:                                 @0@'.format(prefix),
    '    datadir:                                @0@'.format(datadir),
    '    sysconfdir:                             @0@'.format(confdir),
    '    localedir:                              @0@'.format(localedir),
    '    libdir:                                 @0@'.format(libdir),
    '    module library directory:               @0@'.format(plugin_libdir),
    '    module data directory:                  @0@'.format(plugin_datadir),
    '    xdg config directory:                   @0@'.format(xdg_appdir),
    '',
    '    Extra options:',
    '    ==============',
    '',
    '    gtk-doc:                                                                     @0@'.format(with_gtk_doc),
    '    stateless:                                                                   @0@'.format(with_stateless),
    '    bluetooth:                                                                   @0@'.format(with_bluetooth),
]


# Output some stuff to validate the build config
message('\n\n\n' + '\n'.join(report) + '\n\n')
