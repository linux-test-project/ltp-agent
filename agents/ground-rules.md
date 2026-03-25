<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Ground Rules

These rules are **MANDATORY** and must **NEVER** be violated when writing or
reviewing LTP code. Violations MUST be flagged in reviews.

## Rule 1: No Kernel Bug Workarounds

Code MUST NOT work around known kernel bugs.

NEVER work around a kernel bug in LTP test code. Workarounds mask failures for
everyone else. If a test fails because a fix was not backported, that is the
expected (correct) result.

## Rule 2: No Sleep-Based Synchronization

Code MUST NOT use `sleep()`/`nanosleep()` for synchronization.

NEVER use sleep to synchronize between processes. It causes rare flaky failures,
wastes CI time, and breaks under load.

**Use instead:**

- Parent waits for child to finish → `waitpid()` / `SAFE_WAITPID()`
- Child must reach code point before parent continues → `TST_CHECKPOINT_WAIT()` / `TST_CHECKPOINT_WAKE()`
- Child must be sleeping in a syscall → `TST_PROCESS_STATE_WAIT()`
- Async or deferred kernel actions → Exponential-backoff polling loop

## Rule 3: Runtime Feature Detection Only

Code MUST use runtime checks, NOT compile-time assumptions.

Compile-time checks (`configure.ac`) may ONLY enable fallback API definitions
in `include/lapi/`. NEVER assume compile-time results reflect the running kernel.

**Runtime detection methods:**

- errno checks (`ENOSYS` / `EINVAL`)
- `.min_kver` in test struct
- `.needs_kconfigs` in test struct
- Kernel `.config` parsing

## Rule 4: Minimize Root Usage

Tests MUST NOT require root unless absolutely necessary.

If root is required, the reason MUST be documented in the test's doc comment.
Drop privileges for sections that do not need them.

## Rule 5: Always Clean Up

Tests MUST clean up on ALL exit paths (success, failure, early exit).

Every test MUST leave the system exactly as it found it:

- Filesystems → Unmount
- Sysctls, `/proc`/`/sys` values → Restore
- Temp files/dirs → Delete
- Spawned processes → Kill
- Cgroups/namespaces → Remove
- Loop devices → Detach
- Ulimits → Restore

**Prefer library helpers:** `.needs_tmpdir`, `.save_restore`, `.needs_device`,
`.restore_wallclock`, `.needs_cgroup_ctrls`

## Rule 6: Write Portable Code

- MUST NOT use nonstandard libc APIs when portable equivalent exists
- MUST NOT assume 64-bit, page size, endianness, or tool versions
- Architecture-specific tests MUST still compile everywhere (use `.supported_archs`)
- Shell tests MUST be portable POSIX shell (no bash-isms)

Verify with `make check`.

## Rule 7: One Logical Change Per Patch

- Each patch MUST contain exactly ONE logical change
- Each patch MUST compile successfully on its own
- Each patch MUST keep all tests and tooling functional
- Each patch MUST NOT introduce intermediate breakage
- Commit message MUST clearly explain the change

Patches mixing unrelated changes will be delayed or ignored.

## Rule 8: Unreleased Kernel Features

- Tests for unreleased kernel features MUST use `[STAGING]` subject prefix
- Staging tests MUST go into `runtest/staging` only

Tests for features not yet in a mainline kernel release will NOT be merged into
default test suites until the kernel code is finalized and released.
