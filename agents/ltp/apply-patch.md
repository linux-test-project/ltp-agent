# Downloading and Applying Patches

This file provides instructions for downloading and applying patches from
various sources. Use the appropriate section based on the input type.

## Quick Reference

- **Git commit**: No download needed - checkout directly
- **Git branch**: No download needed - checkout directly
- **Multiple commits**: Cherry-pick the range
- **Patchwork URL**: Use b4 or curl + git am
- **Lore URL**: Use b4 or curl + git am
- **Local patch file**: git am directly
- **GitHub PR**: Use gh or git fetch

## From Git Commit

```sh
git checkout -b review/<name> <commit-hash>
```

## From Git Branch

```sh
git checkout -b review/<name> <branch-name>
```

## From Multiple Commits

```sh
git checkout -b review/<name> master
git cherry-pick <start-commit>..<end-commit>
```

## From Patchwork URL

Patchwork URL comes in the form `https://patchwork.ozlabs.org/project/ltp/patch/<message-id>/`.

### Option 1: Using b4 (RECOMMENDED)

```sh
git checkout master && git pull origin master
git checkout -b review/<patch-name> master
b4 shazam <URL>
```

### Option 2: Without b4

```sh
git checkout master && git pull origin master
git checkout -b review/<patch-name> master
curl -sL "https://patchwork.ozlabs.org/patch/<message-id>/mbox/" -o /tmp/patch.mbox
git am /tmp/patch.mbox
```

## From Lore URL

Lore URL comes in the form `https://lore.kernel.org/r/<message-id>/`.

### Option 1: Using b4 (RECOMMENDED)

```sh
git checkout master && git pull origin master
git checkout -b review/<patch-name> master
b4 shazam <URL>
```

### Option 2: Without b4

```sh
git checkout master && git pull origin master
git checkout -b review/<patch-name> master
curl -sL "https://lore.kernel.org/ltp/<message-id>/raw" -o /tmp/patch.mbox
git am /tmp/patch.mbox
```

## From Local Patch File

```sh
git checkout master && git pull origin master
git checkout -b review/<patch-name> master
git am /path/to/patch.patch
```

## From GitHub PR

### Option 1: Using gh (RECOMMENDED)

```sh
git checkout master && git pull origin master
gh pr checkout <pr-number>
```

### Option 2: Without gh

```sh
git checkout master && git pull origin master
git fetch origin pull/<pr-number>/head:review/pr-<pr-number>
git checkout review/pr-<pr-number>
```

## Applying a Patch Series

For multiple patches in order:

```sh
git am /tmp/patch1.mbox /tmp/patch2.mbox /tmp/patch3.mbox
```

Or concatenate:

```sh
cat /tmp/patch*.mbox | git am
```

## b4 Command Reference

- `b4 shazam <URL>`: Download and apply patches directly
- `b4 am <message-id>`: Download patches as mbox (does not apply)
- `b4 am -o . <message-id>`: Save mbox to current directory

**Options:**

- `-o <dir>`: Save mbox to specific directory
- `-m <file>`: Use local mbox file instead of fetching
