#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Andrea Cervesato <andrea.cervesato@suse.com>
#
# Delete all local 'review/*' branches created by ltp-apply-patch.sh.
# Run this from inside an LTP git tree.
#
# Usage:
#   ltp-review-cleanup.sh [-f]
#
# Options:
#   -f    Force delete without confirmation
#
# Examples:
#   ltp-review-cleanup.sh       # interactive, asks before deleting
#   ltp-review-cleanup.sh -f    # delete all review branches immediately

set -e

die() {
	echo "ERROR: $1" >&2
	exit 1
}

usage() {
	sed -n '2,/^$/s/^# \?//p' "$0"
	exit 0
}

[ "$1" = "-h" ] || [ "$1" = "--help" ] && usage

FORCE=0
[ "$1" = "-f" ] && FORCE=1

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
	die "not inside a git repository"

BRANCHES=$(git branch --list 'review/*' | sed 's/^[* ]*//')

if [ -z "$BRANCHES" ]; then
	echo "No review/* branches found."
	exit 0
fi

CURRENT=$(git rev-parse --abbrev-ref HEAD)

echo "Found review branches:"
echo "$BRANCHES" | while read -r b; do
	commits=$(git rev-list --count "master..$b" 2>/dev/null || echo "?")
	if [ "$b" = "$CURRENT" ]; then
		echo "  * $b ($commits commits) [current]"
	else
		echo "    $b ($commits commits)"
	fi
done

COUNT=$(echo "$BRANCHES" | wc -l)

if [ "$FORCE" -eq 0 ]; then
	printf "\nDelete all %d branch(es)? [y/N] " "$COUNT"
	read -r answer
	case "$answer" in
		y|Y|yes|YES) ;;
		*) echo "Aborted."; exit 0 ;;
	esac
fi

# Switch away if currently on a review branch
case "$CURRENT" in
	review/*)
		echo "Switching to master (currently on $CURRENT)..."
		git checkout master
		;;
esac

echo "$BRANCHES" | while read -r b; do
	git branch -D "$b"
done

echo ""
echo "Deleted $COUNT review branch(es)."
