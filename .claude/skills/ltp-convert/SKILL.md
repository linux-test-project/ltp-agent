---
name: ltp-convert
description: LTP Old-to-New API Converter
---

# LTP Test Conversion Protocol

You are an agent that converts LTP tests from the old API (`test.h`) to the
new API (`tst_test.h`).

The user will provide a file path or test name to convert.

## Phase 1: Setup

### Step 1.1: Load Rules

Read these files before doing anything else:

- `agents/ltp/ground-rules.md`
- `agents/ltp/c-tests.md`

`c-tests.md` is the authoritative reference for what the converted test MUST
look like. Every conversion decision must comply with it.

### Step 1.2: Prepare a Branch

```bash
git checkout master
git checkout -b convert/<testname>
```

### Step 1.3: Confirm the Test Uses the Old API

Before converting, verify the file actually uses the old API:

```bash
grep -n '#include.*test\.h\|tst_resm\|tst_brkm\|tst_brkm_\|TEST_LOOPING\|tst_exit\|TCID\|TST_TOTAL\|int main.*argc' <file>
```

If none of these are found, the test may already use the new API — stop and
tell the user.

---

## Phase 2: Analyse the Test

Read the entire file carefully. Before writing a single line, produce an
**analysis block** listing:

1. **Test purpose** — what syscall/behavior is being tested
2. **Test cases** — how many, what they test, what errno/return they expect
3. **Old API constructs found** — itemised list of everything that needs to change
4. **Resources opened** — fds, sockets, temp files, child processes, mounts
5. **Cleanup path** — what the old `cleanup()` does
6. **Conversion plan** — ordered list of changes you will make

Show this analysis to the user before making any edits.

---

## Phase 3: Convert

Apply the changes from the plan. Use the mapping table below and the rules
from `c-tests.md` as the authoritative guide.

### 3.1 Old → New API Mapping

| Old                                          | New                                            |
| -------------------------------------------- | ---------------------------------------------- |
| `#include "test.h"`                          | `#include "tst_test.h"`                        |
| `char *TCID = "...";`                        | Remove                                         |
| `int TST_TOTAL = ...;`                       | Remove                                         |
| `int main(int argc, char *argv[])`           | Remove; use `struct tst_test`                  |
| `tst_parse_opts(...)`                        | Remove                                         |
| `TEST_LOOPING(lc)`                           | Remove; framework handles iterations           |
| `tst_count = 0;`                             | Remove                                         |
| `TEST_PAUSE;`                                | Remove                                         |
| `tst_exit();`                                | Remove                                         |
| `tst_resm(TPASS, fmt, ...)`                  | `tst_res(TPASS, fmt, ...)`                     |
| `tst_resm(TFAIL, fmt, ...)`                  | `tst_res(TFAIL, fmt, ...)`                     |
| `tst_resm(TINFO, fmt, ...)`                  | `tst_res(TINFO, fmt, ...)`                     |
| `tst_brkm(TBROK\|TERRNO, cleanup, fmt, ...)` | `tst_brk(TBROK\|TERRNO, fmt, ...)`             |
| `tst_brkm(TCONF, cleanup, fmt, ...)`         | `tst_brk(TCONF, fmt, ...)`                     |
| `TEST_RETURN`                                | `TST_RET`                                      |
| `TEST_ERRNO`                                 | `TST_ERR`                                      |
| `tst_fork()`                                 | `SAFE_FORK()`                                  |
| `SAFE_*(cleanup, ...)` (old cleanup arg)     | `SAFE_*(...)` (no cleanup arg)                 |
| Old GPL boilerplate header                   | `// SPDX-License-Identifier: GPL-2.0-or-later` |
| Old-style doc comment                        | `/*\` RST-formatted doc comment                |

### 3.2 Structure Conversion

**Remove `main()`.** Replace the old loop structure:

```c
/* OLD */
int main(int argc, char *argv[]) {
    int lc;
    tst_parse_opts(argc, argv, NULL, NULL);
    setup();
    for (lc = 0; TEST_LOOPING(lc); lc++) {
        tst_count = 0;
        run_tests();
    }
    cleanup();
    tst_exit();
}
```

with a `struct tst_test`:

```c
/* NEW */
static struct tst_test test = {
    .setup   = setup,
    .cleanup = cleanup,
    .test_all = run,       /* single test case */
    /* OR */
    .test = verify,        /* parametrized: also set .tcnt */
    .tcnt = ARRAY_SIZE(tcases),
};
```

**Parametrized tests.** If the old test iterates over a `struct test_case_t`
array, convert it to the new `.test` + `.tcnt` pattern (see `c-tests.md`
"Test Case Parametrization" section). Do NOT call multiple per-case functions
from a single `run()`.

**Per-case setup/cleanup.** If old test cases have individual `setup()`/
`cleanup()` function pointers, fold them into the single `.setup`/`.cleanup`
or into per-iteration logic inside `verify(unsigned int n)`.

**`cleanup()` parameter removal.** All `SAFE_*` macros in the new API do NOT
take a cleanup function pointer. Remove the `cleanup` argument everywhere.

### 3.3 Resource and Cleanup Rules

Follow `c-tests.md` and `ground-rules.md` exactly:

- All file descriptors MUST be initialised to `-1` and closed in `cleanup()`
- Use `.needs_tmpdir = 1` for any temp files
- Use `.forks_child = 1` if the test forks
- Use `.needs_root = 1` only if truly required; document why in the doc comment
- Cleanup MUST run on ALL exit paths (the framework calls cleanup on `tst_brk`)

### 3.4 Result Reporting

Apply `c-tests.md` result-reporting rules:

- Use `TST_EXP_FAIL` / `TST_EXP_FAIL2` instead of manual errno checks
- Use `TST_EXP_EQ_LI`, `TST_EXP_EQ_STR`, etc. for equality checks
- Use `TST_EXP_FD` when checking fd return values
- Return `TCONF` (not `TFAIL`) when a feature is unavailable

### 3.5 Conversion Examples

#### `HAVE_*` Header Guards

If the original test has a `HAVE_*` guard, preserve it. Replace the old
fallback `main()` with `TST_TEST_TCONF(...)`. Use a single `#ifdef` block
covering both the optional include and all test code:

```c
#include "config.h"
#include "tst_test.h"

#ifdef HAVE_SYS_XATTR_H
# include <sys/xattr.h>

/* test code */

static struct tst_test test = {
    .test_all = run,
};

#else
TST_TEST_TCONF("<sys/xattr.h> does not exist");
#endif
```

### 3.6 One Commit Per File

Each converted file MUST be committed separately using `git commit -s` to
automatically add the correct `Signed-off-by` from the git config:

```bash
git commit -s -m "<syscall>/<testname>: convert to new LTP API

<one-line explanation of what the test does>"
```

---

## Phase 4: Build and Check

Run in this exact order. Fix any errors before proceeding.

```bash
# Checkpatch
make -C testcases/kernel/syscalls/<syscall> check-<testname>

# Compile
make -C testcases/kernel/syscalls/<syscall> <testname>
```

If either step fails, fix the issue and re-run before continuing.

---

## Phase 5: Runtime Check

```bash
cd testcases/kernel/syscalls/<syscall>

./<testname> -i 0
./<testname> -i 10
./<testname> -i 100
```

Mark as UNKNOWN if the test requires privileges or unavailable hardware.
Any TFAIL or TBROK is a blocker — fix before proceeding.

---

## Phase 6: Hand Off to Reviewer

Once the test builds and passes runtime checks, invoke `/ltp-review` on the
branch to validate the conversion against all rules in `c-tests.md`.

Tell the reviewer: "This is a converted test — pay particular attention to
result reporting patterns, fd initialisation, cleanup on all paths, and
parametrization style."

If the reviewer returns **Needs revision**, fix every issue listed, then
re-run Phase 4 (build) and Phase 5 (runtime) before invoking `/ltp-review`
again. Repeat until the reviewer returns **Approved**.

---

## Phase 7: Output

Report to the user in this format:

```
## Conversion: <testname>

### Analysis
- Test purpose: <one line>
- Test cases: <N cases, what they test>
- Old API constructs replaced: <list>

### Changes Made
- <change 1>
- <change 2>
- ...

### Build
- Checkpatch: ✅/❌
- Compiles: ✅/❌

### Runtime
- Tests pass (-i 0): ✅/❌/UNKNOWN
- Tests pass (-i 10): ✅/❌/UNKNOWN
- Tests pass (-i 100): ✅/❌/UNKNOWN

### Reviewer Output
<output from /ltp-review>

### Verdict
**Done** ✅ / **Blocked** ❌

<one-line reason if blocked>
```
