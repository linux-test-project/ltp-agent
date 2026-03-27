#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Andrea Cervesato <andrea.cervesato@suse.com>
#
# Apply LTP patches from various sources onto a review branch.
# Run this from inside an LTP git tree before invoking /ltp-review.
#
# Usage:
#   apply-patch.sh <source>
#
# Sources:
#   <patchwork-url>    https://patchwork.ozlabs.org/project/ltp/patch/...
#   <lore-url>         https://lore.kernel.org/...
#   <github-pr>        https://github.com/<owner>/<repo>/pull/<number>
#   <local-file>       /path/to/patch.mbox
#   <branch>           branch:<name>
#   <commit>           commit:<hash>
#
# Examples:
#   apply-patch.sh https://patchwork.ozlabs.org/project/ltp/patch/abc123/
#   apply-patch.sh https://lore.kernel.org/r/abc123/
#   apply-patch.sh https://github.com/linux-test-project/ltp/pull/42
#   apply-patch.sh /tmp/my-patch.mbox
#   apply-patch.sh branch:feature-xyz
#   apply-patch.sh commit:abc1234

set -e

die() {
	echo "ERROR: $1" >&2
	exit 1
}

usage() {
	sed -n '2,/^$/s/^# \?//p' "$0"
	exit 0
}

[ $# -eq 0 ] && usage
[ "$1" = "-h" ] || [ "$1" = "--help" ] && usage

SOURCE="$1"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
	die "not inside a git repository"

# Turn a subject line into a short branch-safe slug
# e.g. "[PATCH v2 1/3] dio_read: fix sparse warnings" → "dio_read-fix-sparse-warnings"
slugify() {
	echo "$1" |
		sed 's/^\[.*\] *//' |
		tr '[:upper:]' '[:lower:]' |
		tr -cs 'a-z0-9' '-' |
		sed 's/^-//; s/-$//' |
		cut -c1-50
}

# Get branch name from the subject of the first applied commit
branch_from_subject() {
	local subject="$1"
	local slug uid

	slug=$(slugify "$subject")
	[ -z "$slug" ] && slug="patch"
	uid=$(printf '%s%s' "$subject" "$$" | cksum | cut -d' ' -f1)
	echo "review/${slug}-${uid}"
}

prepare_branch() {
	local name="$1"

	git checkout master
	git pull origin master
	git branch -D "$name" 2>/dev/null || true
	git checkout -b "$name" master
}

# Apply patches, then rename the branch based on the commit subject
rename_branch_from_commits() {
	local subject
	subject=$(git log -1 --format=%s HEAD)
	local new_branch
	new_branch=$(branch_from_subject "$subject")
	local current
	current=$(git rev-parse --abbrev-ref HEAD)

	if [ "$current" != "$new_branch" ]; then
		git branch -m "$new_branch" 2>/dev/null || true
	fi
}

case "$SOURCE" in

# ── Patchwork URL ─────────────────────────────────────────────────────────
*patchwork.ozlabs.org*)
	prepare_branch "review/tmp-apply"

	if command -v b4 >/dev/null 2>&1; then
		b4 shazam -S "$SOURCE"
	else
		_msgid=$(echo "$SOURCE" | sed 's|.*/patch/||; s|/$||')
		curl -sL "https://patchwork.ozlabs.org/patch/${_msgid}/mbox/" -o /tmp/ltp-patch.mbox
		git am /tmp/ltp-patch.mbox
		rm -f /tmp/ltp-patch.mbox
	fi

	rename_branch_from_commits
	;;

# ── Lore URL ──────────────────────────────────────────────────────────────
*lore.kernel.org*)
	prepare_branch "review/tmp-apply"

	if command -v b4 >/dev/null 2>&1; then
		b4 shazam -S "$SOURCE"
	else
		_msgid=$(echo "$SOURCE" | sed 's|.*/r/||; s|/$||')
		curl -sL "https://lore.kernel.org/ltp/${_msgid}/raw" -o /tmp/ltp-patch.mbox
		git am /tmp/ltp-patch.mbox
		rm -f /tmp/ltp-patch.mbox
	fi

	rename_branch_from_commits
	;;

# ── GitHub PR ─────────────────────────────────────────────────────────────
*github.com/*/pull/*)
	command -v gh >/dev/null 2>&1 || die "gh CLI required for GitHub PRs"

	git checkout master
	git pull origin master
	gh pr checkout "$SOURCE"
	;;

# ── Local patch file ──────────────────────────────────────────────────────
*.patch | *.mbox | *.mbx)
	[ -f "$SOURCE" ] || die "file not found: $SOURCE"

	prepare_branch "review/tmp-apply"
	git am "$SOURCE"
	rename_branch_from_commits
	;;

# ── Branch ────────────────────────────────────────────────────────────────
branch:*)
	_branch="${SOURCE#branch:}"
	_slug=$(slugify "$_branch")
	git checkout -b "review/${_slug}" "$_branch"
	;;

# ── Commit ────────────────────────────────────────────────────────────────
commit:*)
	_commit="${SOURCE#commit:}"
	_subject=$(git log -1 --format=%s "$_commit")
	_new_branch=$(branch_from_subject "$_subject")
	git checkout -b "$_new_branch" "$_commit"
	;;

*)
	# Try as a local file
	if [ -f "$SOURCE" ]; then
		prepare_branch "review/tmp-apply"
		git am "$SOURCE"
		rename_branch_from_commits
	else
		die "unrecognized source: $SOURCE"
	fi
	;;
esac

echo ""
echo "Ready for review on branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commits: $(git rev-list --count master..HEAD)"
