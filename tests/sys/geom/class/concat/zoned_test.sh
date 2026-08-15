#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 voidanix <voidanix@FreeBSD.org>
#

class=concat
name=zconcat
. $(atf_get_srcdir)/../geom_subr.sh
. $(atf_get_srcdir)/../zoned_subr.sh

# These tests also need the zoned class for the underlying gzoned providers.
zoned_concat_test_setup()
{
	geom_atf_test_setup
	if ! error_message=$(geom_load_class_if_needed zoned); then
		atf_skip "$error_message"
	fi
}

zoned_concat_cleanup()
{
	[ -c /dev/concat/${name} ] && gconcat destroy -f ${name} 2>/dev/null
	if [ -f "$TEST_MDS_FILE" ]; then
		while read md; do
			[ -c /dev/${md}.zoned ] && \
			    gzoned destroy ${md}.zoned 2>/dev/null
			mdconfig -d -u $md 2>/dev/null
		done < $TEST_MDS_FILE
	fi
	true
}

atf_test_case create cleanup
create_head()
{
	atf_set "descr" "Concatenating zoned devices yields a zoned device"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
create_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	atf_check test -c /dev/concat/${name}
	atf_check_equal "Host Managed" \
	    "$(zonectl -d /dev/concat/${name} -c params | \
	    awk -F': ' '/Zone Mode/ {print $2}')"
}
create_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case rz_all cleanup
rz_all_head()
{
	atf_set "descr" "A zone report covers the zones of all components"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
rz_all_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	atf_check_equal "8" "$(zoned_zone_count /dev/concat/${name} all)"
}
rz_all_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case rz_translated cleanup
rz_translated_head()
{
	atf_set "descr" "Zones of later components report translated LBAs"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
rz_translated_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	# The first zone of the second component starts right after the four
	# 256m zones of the first: 4 * 524288 LBAs.
	atf_check_equal "0x200000" "$(zoned_zone_start /dev/concat/${name} 4)"
}
rz_translated_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case finish_translated cleanup
finish_translated_head()
{
	atf_set "descr" "Zone commands are routed to the owning component"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
finish_translated_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	atf_check zonectl -d /dev/concat/${name} -c finish -l 0x200000
	atf_check_equal "1" "$(zoned_zone_count /dev/concat/${name} full)"
	atf_check_equal "0" "$(zoned_zone_count /dev/${md1}.zoned full)"
	atf_check_equal "1" "$(zoned_zone_count /dev/${md2}.zoned full)"
}
finish_translated_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case rwp_all cleanup
rwp_all_head()
{
	atf_set "descr" "Resetting all write pointers reaches every component"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
rwp_all_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	atf_check zonectl -d /dev/concat/${name} -c finish -l 0
	atf_check zonectl -d /dev/concat/${name} -c finish -l 0x200000
	atf_check_equal "2" "$(zoned_zone_count /dev/concat/${name} full)"
	atf_check zonectl -d /dev/concat/${name} -c rwp -a
	atf_check_equal "0" "$(zoned_zone_count /dev/concat/${name} full)"
	atf_check_equal "8" "$(zoned_zone_count /dev/concat/${name} empty)"
}
rwp_all_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case write_across cleanup
write_across_head()
{
	atf_set "descr" "The zone model holds for writes to any component"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
write_across_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	# Writes at the write pointer are accepted in either component ...
	atf_check -e ignore \
	    dd if=/dev/zero of=/dev/concat/${name} bs=1m count=1
	atf_check -e ignore \
	    dd if=/dev/zero of=/dev/concat/${name} bs=1m oseek=1024 count=1
	# ... while a write past the write pointer of an untouched zone in
	# the second component keeps failing.
	atf_check -s not-exit:0 -e ignore \
	    dd if=/dev/zero of=/dev/concat/${name} bs=1m oseek=1281 count=1
}
write_across_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case label_refused cleanup
label_refused_head()
{
	atf_set "descr" "gconcat label refuses host-managed zoned providers"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
label_refused_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	atf_check -s not-exit:0 -e match:"host-managed" \
	    gconcat label ${name} ${md1}.zoned ${md2}.zoned
}
label_refused_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case mixed_refused cleanup
mixed_refused_head()
{
	atf_set "descr" "Zoned and conventional components cannot be mixed"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
mixed_refused_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	atf_check truncate -s 1025m backing_file.plain
	attach_md plain -t vnode -f backing_file.plain
	atf_check -s not-exit:0 -e ignore \
	    gconcat create ${name} ${md1}.zoned ${plain}
	atf_check test ! -c /dev/concat/${name}
}
mixed_refused_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case zonesize_refused cleanup
zonesize_refused_head()
{
	atf_set "descr" "Components with different zone sizes are refused"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
zonesize_refused_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1 256m
	zoned_attach_md_as md2 128m
	atf_check -s not-exit:0 -e ignore \
	    gconcat create ${name} ${md1}.zoned ${md2}.zoned
	atf_check test ! -c /dev/concat/${name}
}
zonesize_refused_cleanup()
{
	zoned_concat_cleanup
}

atf_test_case append_refused cleanup
append_refused_head()
{
	atf_set "descr" "Appending to a zoned concatenation is refused"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
append_refused_body()
{
	zoned_concat_test_setup

	zoned_attach_md_as md1
	zoned_attach_md_as md2
	zoned_attach_md_as md3
	atf_check gconcat create ${name} ${md1}.zoned ${md2}.zoned
	atf_check -s not-exit:0 -e match:"zoned" \
	    gconcat append ${name} ${md3}.zoned
	atf_check_equal "8" "$(zoned_zone_count /dev/concat/${name} all)"
}
append_refused_cleanup()
{
	zoned_concat_cleanup
}

atf_init_test_cases()
{
	atf_add_test_case create
	atf_add_test_case rz_all
	atf_add_test_case rz_translated
	atf_add_test_case finish_translated
	atf_add_test_case rwp_all
	atf_add_test_case write_across
	atf_add_test_case label_refused
	atf_add_test_case mixed_refused
	atf_add_test_case zonesize_refused
	atf_add_test_case append_refused
}
