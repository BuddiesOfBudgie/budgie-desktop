# Unit tests for the labwc bridge: `meson test --suite labwc-bridge`

python3 = find_program('python3', required: false)

if not python3.found()
    message('python3 not found, skipping the labwc bridge unit tests')
    subdir_done()
endif

bridge_test_env = environment()
# The tests import labwc_bridge from the source tree rather than the install
bridge_test_env.set('PYTHONPATH', labwc_bridge_sourcedir)
bridge_test_env.set('PYTHONDONTWRITEBYTECODE', '1')

bridge_tests = ['rewrites']

# migration.py reaches GLib through paths.py, which a build configured without
# the runtime dependencies is entitled not to have
gi = run_command(python3, '-c', 'import gi', check: false)

if gi.returncode() == 0
    bridge_tests += 'migration'
else
    message('PyGObject not found, skipping the labwc bridge migration tests')
endif

foreach bridge_test : bridge_tests
    test(
        'labwc-bridge-' + bridge_test,
        python3,
        args: [files('test_' + bridge_test + '.py')],
        env: bridge_test_env,
        suite: 'labwc-bridge',
    )
endforeach
