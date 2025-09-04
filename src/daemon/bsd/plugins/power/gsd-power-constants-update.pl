#!/usr/bin/env perl

# Author  : Simos Xenitellis <simos at gnome dot org>.
# Author  : Bastien Nocera <hadess@hadess.net>
# Version : 1.2
#
# Input   : gsd-power-constants.h
# Output  : gsdpowerconstants.py
#
use strict;

# Used for reading the keysymdef symbols.
my @constantselements;

(scalar @ARGV >= 2) or die "Usage: $0 <input> <output>\n";
my ($input, $output) = @ARGV;

die "Could not open file gsd-power-constants.h: $!\n" unless open(IN_CONSTANTS, "<:utf8", $input);

# Output: gtk+/gdk/gdkkeysyms.h
die "Could not open file gsdpowerconstants.py: $!\n" unless open(OUT_CONSTANTS, ">:utf8", $output);

print OUT_CONSTANTS<<EOF;

# File auto-generated from script http://git.gnome.org/browse/gnome-settings-daemon/tree/plugins/power/gsd-power-constants-update.pl

# Modified by the GTK+ Team and others 1997-2012.  See the AUTHORS
# file for a list of people on the GTK+ Team.  See the ChangeLog
# files for a list of changes.  These files are distributed with
# GTK+ at ftp://ftp.gtk.org/pub/gtk/.

EOF

while (<IN_CONSTANTS>)
{
	next if ( ! /^#define / );

	@constantselements = split(/\s+/);
	die "Internal error, no \@constantselements: $_\n" unless @constantselements;

	my $constant = $constantselements[1];
	my $value = $constantselements[2];

	printf OUT_CONSTANTS "%s = %s;\n", $constant, $value;
}

close IN_CONSTANTS;

printf "We just finished converting $input to $output\nThank you\n";
