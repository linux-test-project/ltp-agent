---
name: ltp-review-smoke
description: LTP Patch Smoke Test — compile and run tests, then analyze failures
---

# LTP Smoke Test Protocol

You are an agent that compiles and runs LTP tests from a patch branch, then
analyzes any build or runtime failures against the source code to produce
actionable findings.

This skill complements `/ltp-review` (static code review). Run it when you
have access to the target hardware and privileges needed by the test.

## Phase 1: Setup

### Step 1.1: Verify patches are applied

Run `git rev-list --count master..HEAD`. If the count is 0, or the current
branch IS master, **stop immediately** and tell the user:

> No patches found. Please checkout a branch with patches applied on top of
> master before running this skill.

Do NOT proceed.

### Step 1.2: Identify changed tests

Use `git diff --name-only master..HEAD` to list changed files.

- For each `*.c` file under `testcases/`, extract the test name (filename
  without `.c`) and its directory.
- For each `*.sh` file under `testcases/`, extract the test name and its
  directory.
- Skip non-test files (headers, libraries, documentation, runtest entries,
  `.gitignore`, Makefiles).

If no test files are found, **stop** and tell the user:

> No test source files found in the patch.

### Step 1.3: Load rules

Read `agents/ltp/ground-rules.md`.

Identify the test type and load the corresponding rules:

- `*.c` (NOT in `open_posix_testsuite/`) → Read `agents/ltp/c-tests.md`
- `*.sh` → Read `agents/ltp/shell-tests.md`
- Files in `testcases/open_posix_testsuite/` → Read `agents/ltp/openposix.md`

## Phase 2: Build

For EACH test identified in Step 1.2, in order:

### Step 2.1: Checkpatch (C tests only, skip for Open POSIX)

```bash
make -C <test-dir> check-<testname>
```

Record any warnings or errors.

### Step 2.2: Compile

For LTP C tests:

```bash
make -C <test-dir> <testname>
```

For Open POSIX tests, follow build instructions from `agents/ltp/openposix.md`.

If compilation fails, **read the full error output** and the relevant source
lines. Determine:

- Is it a missing header / dependency?
- Is it a code error in the patch?
- Is it a `configure` issue (missing `HAVE_*` flag)?

Record the finding with root cause.

### Step 2.3: Per-commit build (multi-commit patches only)

If there are multiple commits (`git rev-list --count master..HEAD` > 1),
verify each commit compiles independently:

```bash
git stash && git checkout <commit> && make -C <test-dir> <testname>
```

Restore to branch HEAD after checking all commits. This verifies Ground
Rule 7 (each patch must compile on its own).

## Phase 3: Runtime

For EACH test that compiled successfully:

### Step 3.1: Run the test

Run with increasing iterations to catch flaky behavior:

```bash
./<testname> -i 0      # single run
./<testname> -i 10     # 10 iterations
./<testname> -i 100    # 100 iterations
```

For Open POSIX tests (no `-i` support):

```bash
./<testname>                                    # single run
for i in $(seq 1 10); do ./<testname>; done     # 10 runs
for i in $(seq 1 100); do ./<testname>; done    # 100 runs
```

**Timeout**: If a single run takes longer than 60 seconds, skip higher
iterations and record as TIMEOUT.

**Privileges**: If the test requires root (`.needs_root = 1`) and you are
not root, record as SKIPPED and note the reason.

### Step 3.2: Capture results

For each iteration level, record:

- Exit code
- Any TBROK, TFAIL, or TWARN lines from stdout/stderr
- Any kernel warnings (dmesg, if accessible)

## Phase 4: Analysis

This is the critical phase. For EACH failure (build or runtime), **read the
source code** and reason about the root cause.

### Build failure analysis

- Read the compiler error and the source lines it references.
- Check if the error is caused by the patch or by a missing dependency.
- Suggest the fix (missing include, wrong type, missing `configure` check).

### Runtime failure analysis

For each TBROK or TFAIL:

- **Read the error message** — extract the failing syscall, path, or value.
- **Read the source code** around the line that produced the error.
- **Reason about the cause**:
  - ENOENT on a `/dev/` or `/sys/` path → missing `.needs_drivers` or
    `.needs_kconfigs`?
  - EPERM / EACCES → missing `.needs_root`?
  - ENOSYS → missing `.min_kver` or runtime feature check?
  - EINVAL → wrong arguments, wrong struct size, missing kernel feature?
  - Value mismatch → logic error in the test?
  - Flaky across iterations → synchronization issue (sleep-based sync,
    race condition)?
- **Suggest the fix** — be specific (e.g., "add `.needs_drivers` with `msr`
  module" not just "check kernel modules").

### Cross-reference with code review

If `/ltp-review` was run in the same conversation, cross-reference:

- Did the code review catch this issue? If not, note it as a gap.
- Does the runtime failure confirm a code review finding?

## Phase 5: Output

ALWAYS output in this EXACT format:

```
## Smoke Test: <patch-subject>

### Build
- Checkpatch: PASS / FAIL <details> / N/A
- Compiles: PASS / FAIL <details>
- Per-commit build: PASS / FAIL <details> / N/A (single commit)

### Runtime
- Single run: PASS / FAIL / TIMEOUT / SKIPPED
- 10 iterations: PASS / FAIL / TIMEOUT / SKIPPED
- 100 iterations: PASS / FAIL / TIMEOUT / SKIPPED

### Failures
1. <failure description>
   - **Error**: <exact error message>
   - **Source**: <file>:<line>
   - **Root cause**: <analysis>
   - **Suggested fix**: <specific fix>

   OR "None"

### Verdict

**All clear** ✅ / **Issues found** ❌ / **Incomplete** ⚠️ (skipped/timeout)

<one-line summary>
```

## Decision Rules

- Any build failure → **Issues found** ❌
- Any TBROK or TFAIL → **Issues found** ❌
- Flaky failure (passes sometimes, fails sometimes) → **Issues found** ❌
- All tests skipped or timed out → **Incomplete** ⚠️
- All pass at all iteration levels → **All clear** ✅
