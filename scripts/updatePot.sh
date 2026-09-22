#!/bin/bash
#
# Regenerate po/budgie-desktop.pot, then push it to Transifex.
#
# Extraction itself is meson's: po/meson.build reads the sources off the build
# targets and holds the xgettext keywords. Needs meson >= 1.8.0.

set -e

srcroot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$srcroot"

builddir="${1:-build}"

if [[ ! -d "$builddir" ]]; then
    echo "no meson build directory at '$builddir'" >&2
    echo "run: meson setup $builddir --prefix=/usr --sysconfdir=/etc" >&2
    exit 1
fi

ninja -C "$builddir" po/budgie-desktop.pot
cp "$builddir/po/budgie-desktop.pot" po/budgie-desktop.pot

# xgettext writes the references relative to the build directory, so without
# this the pot depends on where that is
sed -i -E \
    -e "\|^#:| s|[^ ]*$srcroot/||g" \
    -e "\|^#:| s|(\.\./)+||g" \
    -e "\|^#: | { :a; s|(:[0-9]+) ([^ ]+:[0-9]+)|\1\n#: \2|; ta }" \
    po/budgie-desktop.pot

#tx push -s
