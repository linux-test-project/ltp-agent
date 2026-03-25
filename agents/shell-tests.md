<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Shell Test Rules

This file contains MANDATORY rules for shell tests. Load this file when
reviewing or writing any patch that modifies `*.sh` files.

## Required Test Structure

Every shell test MUST follow this exact structure, in this exact order.
Omitting or reordering blocks will break the shell loader.

```sh
#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) YYYY Author Name <email@example.org>
# ---
# doc
# Brief RST description of what the test verifies.
#
# Additional detail if needed (exported to generated docs).
# ---
# ---
# env
# {
#  "needs_root": true,
#  "needs_tmpdir": true
# }
# ---

TST_SETUP=setup
TST_CLEANUP=cleanup

. tst_loader.sh

setup()
{
    tst_res TINFO "setup executed"
}

cleanup()
{
    tst_res TINFO "cleanup executed"
}

tst_test()
{
    tst_res TPASS "Test passed"
}

. tst_run.sh
```

## Structure Checklist

When reviewing or writing shell tests, verify ALL of the following:

### Block 1: Shebang + License + Copyright

- Shebang MUST be exactly `#!/bin/sh`
- License MUST be `GPL-2.0-or-later`
- Copyright line MUST be present with year and author

### Block 2: Doc Block

- `# --- doc` block MUST be present
- MUST contain RST-formatted description of WHAT is tested
- Will be exported to online test catalog

### Block 3: Env Block

- `# --- env` block MUST be present (even if empty: `{}`)
- MUST contain JSON serialization of `struct tst_test` fields
- Valid keys: `"needs_root"`, `"needs_tmpdir"`, `"needs_kconfigs"`, `"tags"`, etc.

### Block 4: Variable Assignments

- `TST_SETUP` and `TST_CLEANUP` MUST be set BEFORE sourcing `tst_loader.sh`
- These are optional but if used, MUST be set here

### Block 5: Source Loader

- `. tst_loader.sh` MUST come AFTER variable assignments
- `. tst_loader.sh` MUST come BEFORE function definitions

### Block 6: Function Definitions

- `setup()` and `cleanup()` MUST be defined AFTER loader is sourced
- Function names MUST match variables set in Block 4

### Block 7: Test Function

- `tst_test()` function MUST contain actual test logic
- MUST use `tst_res` and `tst_brk` for reporting

### Block 8: Source Runner

- `. tst_run.sh` MUST be the LAST line of the file
- NOTHING may come after this line

## Coding Style Checklist

- MUST be portable POSIX shell only (no bash-isms)
- MUST NOT use `[[ ]]` (use `[ ]` instead)
- MUST NOT use arrays
- MUST NOT use `function` keyword
- MUST NOT use process substitution
- MUST work with `dash`
- Lines SHOULD be under 80 characters
- MUST use tabs for indentation
- All variable expansions MUST be quoted
- SHOULD avoid unnecessary subshells
- Functions MUST NOT be named after common shell commands

**Allowed exceptions:**

- `local` keyword inside functions
- `-o` and `-a` test operators

## Env Block Reference

- `"needs_root"` (bool): Test requires root privileges
- `"needs_tmpdir"` (bool): Test needs a temporary directory
- `"needs_kconfigs"` (array): Required kernel configs, e.g. `["CONFIG_NUMA=y"]`
- `"tags"` (object): Git tags, e.g. `{"linux-git": "<hash>"}`
- `"min_kver"` (string): Minimum kernel version

## Running Shell Tests from Source Tree

```sh
# From the test's directory (adjust ../ depth as needed)
PATH=$PATH:$PWD:$PWD/../../lib/ ./foo01.sh
```

The path must reach `testcases/lib/` where `tst_loader.sh`, `tst_run.sh`, and
`tst_run_shell` binary reside.
