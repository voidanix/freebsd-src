#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 voidanix <voidanix@FreeBSD.org>
#

class=label
. $(atf_get_srcdir)/../geom_subr.sh
. $(atf_get_srcdir)/../zoned_subr.sh

# These tests also need the zoned class for the underlying gzoned provider.
zoned_label_test_setup()
{
	geom_atf_test_setup
	if ! error_message=$(geom_load_class_if_needed zoned); then
		atf_skip "$error_message"
	fi
}

zoned_label_cleanup()
{
	[ -c /dev/label/$(cat label_name 2>/dev/null) ] && \
	    glabel destroy -f $(cat label_name) 2>/dev/null
	if [ -f "$TEST_MDS_FILE" ]; then
		while read md; do
			[ -c /dev/${md}.zoned ] && \
			    gzoned destroy ${md}.zoned 2>/dev/null
			mdconfig -d -u $md 2>/dev/null
		done < $TEST_MDS_FILE
	fi
	true
}

atf_test_case label_refused cleanup
label_refused_head()
{
	atf_set "descr" "glabel label refuses host-managed zoned providers"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
label_refused_body()
{
	zoned_label_test_setup

	zoned_attach_md
	atf_check -s not-exit:0 -e match:"host-managed" \
	    glabel label test0 /dev/${md}.zoned
	# The refusal must happen before anything is written: all zones
	# are still empty.
	atf_check_equal "$(zoned_zone_count /dev/${md}.zoned all)" \
	    "$(zoned_zone_count /dev/${md}.zoned empty)"
}
label_refused_cleanup()
{
	zoned_label_cleanup
}

atf_test_case clear_refused cleanup
clear_refused_head()
{
	atf_set "descr" "glabel clear refuses host-managed zoned providers"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
clear_refused_body()
{
	zoned_label_test_setup

	zoned_attach_md
	# Clearing writes the same sector a label would, so it is refused
	# rather than left to fail with a bare I/O error.
	atf_check -s not-exit:0 -e match:"host-managed" \
	    glabel clear /dev/${md}.zoned
	atf_check_equal "$(zoned_zone_count /dev/${md}.zoned all)" \
	    "$(zoned_zone_count /dev/${md}.zoned empty)"
}
clear_refused_cleanup()
{
	zoned_label_cleanup
}

atf_test_case create_params cleanup
create_params_head()
{
	atf_set "descr" "A manual label passes zone parameters through"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
create_params_body()
{
	zoned_label_test_setup

	zoned_attach_md
	echo test1 > label_name
	atf_check glabel create test1 ${md}.zoned
	atf_check_equal "Host Managed" \
	    "$(zonectl -d /dev/label/test1 -c params | \
	    awk -F': ' '/Zone Mode/ {print $2}')"
}
create_params_cleanup()
{
	zoned_label_cleanup
}

atf_test_case create_rz cleanup
create_rz_head()
{
	atf_set "descr" "A manual label reports the same zones as its provider"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
create_rz_body()
{
	zoned_label_test_setup

	zoned_attach_md
	echo test2 > label_name
	atf_check glabel create test2 ${md}.zoned
	atf_check_equal "$(zoned_zone_count /dev/${md}.zoned all)" \
	    "$(zoned_zone_count /dev/label/test2 all)"
}
create_rz_cleanup()
{
	zoned_label_cleanup
}

atf_test_case create_finish cleanup
create_finish_head()
{
	atf_set "descr" "Zone commands through a manual label reach the provider"
	atf_set "require.user" "root"
	atf_set "require.progs" "gzoned zonectl"
}
create_finish_body()
{
	zoned_label_test_setup

	zoned_attach_md
	echo test3 > label_name
	atf_check glabel create test3 ${md}.zoned
	atf_check zonectl -d /dev/label/test3 -c finish -l 0
	atf_check_equal "1" "$(zoned_zone_count /dev/${md}.zoned full)"
}
create_finish_cleanup()
{
	zoned_label_cleanup
}

atf_init_test_cases()
{
	atf_add_test_case label_refused
	atf_add_test_case clear_refused
	atf_add_test_case create_params
	atf_add_test_case create_rz
	atf_add_test_case create_finish
}
