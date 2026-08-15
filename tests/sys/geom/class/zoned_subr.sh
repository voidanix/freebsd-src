#!/bin/sh

# Helpers for exercising GEOM classes on top of a gzoned provider.  Source this
# in addition to geom_subr.sh.

# Attach a vnode-backed md large enough for four zones of $2 (default 256m).
# gzoned reserves space at the end of the provider for its metadata block and
# zone table, so an exact multiple of the zone size would lose a zone.  Sets
# the variable named by $1 (default "md") to the md unit.
zoned_backing_md()
{
	local rv=${1:-md}
	local zonesize=${2:-256m}

	atf_check truncate -s $((4 * ${zonesize%m} + 1))m backing_file.$rv
	attach_md $rv -t vnode -f backing_file.$rv
}

# Set up a gzoned provider on a fresh backing md: $1 names the variable to
# fill (default "md"), $2 the zone size (default 256m) and $3 the conventional
# zone specification, if any.  Classes needing several components pass a
# distinct name for each.
zoned_attach_md_as()
{
	local rv=${1:-md}
	local zonesize=${2:-256m}
	local conv=$3
	local unit

	zoned_backing_md $rv $zonesize
	eval "unit=\$$rv"
	atf_check gzoned create -s $zonesize ${conv:+-c ${conv}} ${unit}
}

# Set up a single gzoned provider in ${md}.  Any argument is passed to gzoned
# create as its conventional zone specification.
zoned_attach_md()
{
	zoned_attach_md_as md 256m "$1"
}

# Number of zones on $1 matching the report option $2, e.g. "nonwp".
zoned_zone_count()
{
	zonectl -d $1 -c rz -o $2 -P summary | awk '/zones,/ {print $1}'
}

# Write pointer LBA of the zone containing LBA $2 on $1.
zoned_zone_wp()
{
	zonectl -d $1 -c rz -l $2 -P script | \
	    awk -F',' 'NR == 1 {gsub(/ /, "", $3); print $3}'
}

# Start LBA of zone number $2 on $1.
zoned_zone_start()
{
	zonectl -d $1 -c rz -P script | \
	    awk -F',' -v n=$(($2 + 1)) 'NR == n {gsub(/ /, "", $1); print $1}'
}
