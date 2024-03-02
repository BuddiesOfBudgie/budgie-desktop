## Refreshing vapis

### Polkit

To refresh the Polkit vapi files:

```bash
vapigen --library polkit-gobject-1 /usr/share/gir-1.0/Polkit-1.0.gir --pkg gio-unix-2.0
vapigen --library polkit-agent-1 /usr/share/gir-1.0/PolkitAgent-1.0.gir --pkg gio-unix-2.0 --pkg polkit-gobject-1 --girdir=. --vapidir=.
```

Then have fun un-mangling it to support vala async syntax.

### Libxfce4windowing

To generate the libxfce4windowing vapi files:

```bash
vapigen --library libxfce4windowing-0 /usr/share/gir-1.0/Libxfce4windowing-0-0.gir --metadatadir .
```

### UPower

To generate the UPower vapi files:

```bash
vapigen --library upower-glib /usr/share/gir-1.0/UpowerGlib-1.0.gir --metadatadir . --pkg gio-unix-2.0 UPowerGlib-1.0-custom.vala
```

### Mutter

For mutter (and shipped cogl and clutter), once you defined the relative `*.deps`, `*.metadata` and `*-custom.vala` files, you can run:

```bash
./vapi/generate-mutter-vapi.sh <mutter-version>
```
