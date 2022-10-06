project(
    'budgie-desktop',
    ['c', 'vala'],
    version: '10.6.4',
    license: [
        'GPL-2.0',
        'LGPL-2.1',
    ],
    default_options: [
        'c_std=c11',
        'warning_level=3'
    ],
)

budgie_screensaver  = find_program('budgie-screensaver', required: false)
gnome_screensaver = find_program('gnome-screensaver', required: false)
with_gnome_screensaver = get_option('with-gnome-screensaver')
if with_gnome_screensaver == false
    assert(budgie_screensaver.found(), 'Budgie Screensaver is a required separate component of Budgie Desktop. Please ensure budgie-screensaver is available at configure and run time. You can find this at https://github.com/BuddiesOfBudgie/budgie-screensaver')
    budgie_screensaver_vala_args = []
else
    assert(gnome_screensaver.found(), 'Either GNOME Screensaver or Budgie Screensaver is a required separate component of Budgie Desktop. Please ensure one of these is available at configure and run time.')
    budgie_screensaver_vala_args = ['-D', 'HAVE_GNOME_SCREENSAVER']
endif

git = find_program('git', required: false)

meson.add_install_script('scripts/mesonPostInstall.sh')

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

# Create config.h
cdata = configuration_data()

# Inspired by https://github.com/GNOME/recipes/blob/master/meson.build
package_version = meson.project_version()

if git.found()
    git_version = run_command('git', ['rev-parse', 'HEAD'])
    if git_version.returncode() == 0
        package_version += ' (git-'+git_version.stdout().strip()+')'
    endif
endif

cdata.set_quoted('PACKAGE_VERSION', package_version)

# Make gettext work
cdata.set_quoted('GETTEXT_PACKAGE', meson.project_name())
add_global_arguments('-DGETTEXT_PACKAGE="budgie-desktop"', language: 'c')

# Globals that we need
prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
confdir = join_paths(prefix, get_option('sysconfdir'))
datadir = join_paths(prefix, get_option('datadir'))
localedir = join_paths(prefix, get_option('localedir'))
podir = join_paths(meson.source_root(), 'po')

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
cdata.set_quoted('DATADIR', datadir)
cdata.set_quoted('SYSCONFDIR', confdir)
cdata.set_quoted('LOCALEDIR', localedir)
cdata.set_quoted('PACKAGE_URL', 'https://buddiesofbudgie.org')

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

# Documentation...
with_gtk_doc = get_option('with-gtk-doc')
if with_gtk_doc == true
    subdir('docs')
endif

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
]


# Output some stuff to validate the build config
message('\n\n\n' + '\n'.join(report) + '\n\n')
