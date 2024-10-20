#!/bin/bash
set -xe

version=$1
girdir=$(pkg-config libmagpie-$version --variable=girdir)

cd $(dirname $0)

for lib in cogl clutter meta; do
    libversion=$lib-$version
    girname=${libversion^}
    vapiname=magpie-$libversion
    vapiname=${vapiname/magpie-meta/libmagpie}
    custom_vapi=""

    if [ -f "$vapiname-custom.vala" ]; then
        custom_vapi="$vapiname-custom.vala"
    fi

    vapigen --library $vapiname $girdir/$girname.gir \
            --girdir . -d . --metadatadir . --vapidir . \
            --girdir $girdir/ $custom_vapi
done
