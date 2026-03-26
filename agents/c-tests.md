<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# C Test Rules

This file contains MANDATORY rules for C tests. Load this file when reviewing
or writing any patch that modifies `*.c` or `*.h` files.

## Required Test Structure

Every C test MUST follow this structure:

```c
// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (c) YYYY Author Name <email@example.org>
 */

/*\
 * High-level RST-formatted test description goes here.
 * Explain _what_ is being tested (exported to docs).
 *
 * The following part is OPTIONAL:
 * [Algorithm]
 *
 * Explanation of how algorithm in the test works in a list (-) syntax.
 */

#include "tst_test.h"

static void run(void)
{
    tst_res(TPASS, "Test passed");
}

static struct tst_test test = {
    .test_all = run,
};
```

## Checklist

When reviewing or writing C tests, verify ALL of the following:

### 1. Coding Style

- Code MUST follow Linux kernel coding style
- `make check` or `make check-$TCID` MUST pass (uses vendored `checkpatch.pl`)
- MUST use C99 features where appropriate

### 2. API Usage

- MUST use new API (`tst_test.h`), NOT old API (`test.h`)
- MUST NOT define `main()` (unless `TST_NO_DEFAULT_MAIN` is used)
- MUST use `struct tst_test` for configuration
- Handlers MUST be thin; logic goes in `.setup` and `.cleanup` callbacks

### 3. Syscall Usage

- Syscall usage MUST match man pages and kernel code

### 4. File Organization

- New test binary MUST be added to corresponding `.gitignore`
- Datafiles go in `datafiles/` subdirectory (installed to `testcases/data/$TCID`)
- Syscall tests go under `testcases/kernel/syscalls/`
- Entry MUST exist in appropriate `runtest/` file
- Sub-executables MUST use `$TESTNAME_` prefix
- MUST use `.needs_tmpdir = 1` for temp files (work in current directory)

### 5. Result Reporting

- MUST use `tst_res()` for results: `TPASS`, `TFAIL`, `TCONF`, `TBROK`, `TINFO`
- MUST use `tst_brk()` for fatal errors that abort the test
- MUST use `TEST()` macro to capture return value (`TST_RET`) and errno (`TST_ERR`)
- MUST return `TCONF` (not `TFAIL`) when feature is unavailable

### 6. Safe Macros

- MUST use `SAFE_*` macros for system calls that have a `SAFE_*` version in `include/`
- Safe macros are defined in `include/` directory (search `tst_*.h` headers)
- If no `SAFE_*` version exists, verify whether one can be added; otherwise use manual error handling

### 7. Kernel Version Handling

- MUST use `.min_kver` for kernel version gating
- MUST prefer runtime checks over compile-time checks

### 8. Tagging

- Regression tests MUST include `.tags` in `struct tst_test`

### 9. Cleanup

- Cleanup MUST run on ALL exit paths
- MUST unmount, restore sysctls, delete temp files, kill processes

### 10. Static Variables

- Static variables MUST be initialized before use in test logic (for `-i` option)
- Static allocated variables MUST be released in cleanup if allocated in setup

### 11. Memory Allocation

- Memory MUST be correctly deallocated
- EXCEPTION: If `.bufs` is used, ignore check for memory allocated with it

### 12. String Handling

- MUST use `snprintf()` when combining strings
- MUST use `PATH_MAX` for path buffers, NOT custom size macros

### 13. Architecture-Specific Tests

- MUST use `.supported_archs` in `struct tst_test` when the target architectures
  are supported by the framework (see `lib/tst_arch.c`)
- `#if defined(...)` arch guards are only acceptable when the target architecture
  is not supported by the framework

### 14. Compile-time Feature Guards (`HAVE_*`)

When the entire test depends on a compile-time feature flag (e.g. `HAVE_NUMA_V2`,
`HAVE_SYS_XATTR_H`), the `#ifdef` MUST wrap ALL test code at the file level —
never inside individual functions.

Rules:

- The `#ifdef HAVE_*` MUST appear after the includes that bring in `config.h`
  (which defines the `HAVE_*` macros), so that the guard is evaluated correctly
- ALL `#define` macros, static variables, helper functions, and `struct tst_test`
  MUST be inside the `#ifdef` block
- The `#else` branch MUST use `TST_TEST_TCONF("...")` with a human-readable
  literal string explaining what is missing — NEVER use the `HAVE_*` macro name
  or a generic constant like `NUMA_ERROR_MSG` as the message
- When a support/helper `.c` file's entire body depends on the same feature flag,
  wrap the whole file body in a single top-level `#ifdef` — NEVER scatter
  per-function guards inside the same file

WRONG — guard buried inside a function:

```c
#include "tst_test.h"
#include "move_pages_support.h"

static void run(void)
{
#ifdef HAVE_NUMA_V2
    /* test logic */
#else
    tst_res(TCONF, NUMA_ERROR_MSG);
#endif
}

static struct tst_test test = { .test_all = run };
```

CORRECT — guard at file level, `struct tst_test` inside, `TST_TEST_TCONF` in `#else`:

```c
#include "tst_test.h"
#include "move_pages_support.h"  /* brings in config.h → defines HAVE_NUMA_V2 */

#ifdef HAVE_NUMA_V2

static void run(void)
{
    /* test logic */
}

static struct tst_test test = { .test_all = run };

#else
    TST_TEST_TCONF("numa v2 is not supported");
#endif
```

### 15. Deprecated Features

- MUST NOT define `[Description]` in the test description section

## New Syscalls Testing

When introducing new tests for new syscalls, ALWAYS update the architectures
syscalls files at `include/lapi/syscalls/*.in` by running the command:

```sh
./include/lapi/syscalls/generate_arch.sh <linux code>
```

Where `<linux code>` is the folder with the Linux Kernel source code.

Then ALWAYS regenerate the `lapi/syscalls.h` file to make sure we have all
syscalls updated:

```sh
./include/lapi/syscalls/generate_syscalls.sh include/lapi/syscalls.h
```

## Code Examples

The following sections contain examples which are considered reference when
rewriting old LTP tests or when writing new LTP tests.

ALWAYS follow these rules.

### Architecture-Specific Tests

When the target architectures are supported by the framework, do NOT use
preprocessor arch guards:

```c
/* WRONG: use .supported_archs instead when architectures are supported by the framework */
#if defined(__i386__) || defined(__x86_64__)
static void run(void)
{
    /* test logic */
}
#endif
};
```

CORRECT: use `.supported_archs` in `struct tst_test`:

```c
/* CORRECT: runtime arch check via the framework */
static struct tst_test test = {
    .test_all = run,
    .supported_archs = (const char *const []) {
        "x86_64",
        "x86",
        NULL
    },
};
```

### LTP API usage

#### Use the correct import

```c
/* WRONG: this is importing legacy API */
#include "test.h"

/* CORRECT: use new LTP API*/
#include "tst_test.h"
```

#### Use SAFE\_\* macros

ALWAYS verify that syscalls we are using have a `SAFE_*` version associated
with it inside the `include/tst_*.h` files. If it exists, use it. If it
doesn't, verify if you can create it.

```c
/* WRONG: don't use plain syscalls */
int fd = open("test_file", O_RDWR | O_CREAT, 0644);
if (fd < 0) {
    tst_brk(TBROK | TERRNO, "open() error");
}

/* CORRECT: use SAFE_* macros instead */
int fd = SAFE_OPEN("test_file", O_RDWR | O_CREAT, 0644);
```

### New SAFE\_\* macros definition

#### Don't use `cleanup_fn` in newly added `safe_*` definitions

```c
/* WRONG: cleanup_fn is used in the legacy LTP API */
void *safe_mysyscall(const char *file, const int lineno, void (*cleanup_fn) (void),
        size_t size)
{
    void *rval;

    rval = mysyscall(size);

    if (rval == NULL) {
        /* WRONG: tst_brkm_ is used by the legacy API */
        tst_brkm_(file, lineno, TBROK | TERRNO, cleanup_fn,
            "mysyscall(%zu) failed", size);
    }

    return rval;
}

/* CORRECT: use the new LTP API format */
void *safe_mysyscall(const char *file, const int lineno,
        size_t size)
{
    void *rval;

    rval = mysyscall(size);

    if (rval == NULL) {
        /* CORRECT: tst_brk_ is used by the new API */
        tst_brk_(file, lineno, TBROK | TERRNO,
            "mysyscall(%zu) failed", size);
    }

    return rval;
}
```

### Temporary folder

NEVER create files in the currently local folder:

```c
static int fd = -1;

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    /* WRONG: missing `.needs_tmpdir = 1` */
};
```

ALWAYS create files in the temporary folder:

```c
static int fd = -1;

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    /* CORRECT: create files in the temporary folder */
    .needs_tmpdir = 1,
};
```

### File descriptors

#### Initialization

NEVER initialize file descriptors to valid values:

```c
/* WRONG: zero value file descriptor is a valid value (stdin) */
static int fd;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```

ALWAYS set file descriptors to an invalid value:

```c
/* CORRECT: initialize file descriptor to an invalid value */
static int fd = -1;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```

#### Close open file descriptors

NEVER leave test without closing open file descriptors:

```c
static int fd = -1;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static struct tst_test test = {
    .setup = setup,
    /* WRONG: missing .cleanup */
    .test_all = run,
    .needs_tmpdir = 1,
};
```

ALWAYS close file descriptors at cleanup:

```c
static int fd = -1;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

/* CORRECT: close file descriptors at cleanup */
static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```

#### No manual reset after SAFE_CLOSE

`SAFE_CLOSE()` already resets the file descriptor to `-1` after closing.
NEVER manually reset it afterwards:

```c
/* WRONG: redundant reset — SAFE_CLOSE() already sets fd = -1 */
static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
    fd = -1;
}
```

ALWAYS rely on `SAFE_CLOSE()` to handle the reset:

```c
/* CORRECT: SAFE_CLOSE() sets fd = -1 internally */
static void cleanup(void) {
    if (fd != -1)
        SAFE_CLOSE(fd);
}
```

### Tests Results

#### TPASS on numbers equality

ALWAYS prefer `TST_EXP_EQ_LI` over numeric equality statements which are
combined with `tst_res(TPASS, ...)`:

```c
/* WRONG: multiple lines don't bring any useful information */
if (uid == CHILD2UID)
    tst_res(TPASS, "Read UID matches Child2 UID");
else
    tst_res(TFAIL, "Read UID doesn't match Child2 UID");

/* CORRECT: one line check is short and streamlined */
TST_EXP_EQ_LI(uid, CHILD2UID);
```

#### TPASS on string equality

ALWAYS prefer `TST_EXP_EQ_STR` or `TST_EXP_EQ_STRN` over `strcmp()` or
`strncmp()` statements which are combined with `tst_res(TPASS, ...)`:

```c
/* WRONG: verbose string comparison with manual result reporting */
if (strcmp(buf, expected) == 0)
    tst_res(TPASS, "Buffer matches expected value");
else
    tst_res(TFAIL, "Buffer doesn't match expected value");

/* CORRECT: use TST_EXP_EQ_STR for null-terminated string comparison */
TST_EXP_EQ_STR(buf, expected);

/* CORRECT: use TST_EXP_EQ_STRN for length-limited string comparison */
TST_EXP_EQ_STRN(buf, expected, sizeof(expected));
```

#### TPASS on real file descriptor

ALWAYS use `TST_EXP_FD` when we need to check if returned value is a real
file descriptor:

```c
/* WRONG: manual check and reporting */
TEST(fd = open("file", O_RDONLY));
if (TST_RET < 0)
    tst_res(TFAIL | TTERRNO, "open failed");
else
    tst_res(TPASS, "open returned %ld", TST_RET);

/* CORRECT: use TST_EXP_FD */
TST_EXP_FD(open("file", O_RDONLY));
```

#### TPASS on unsigned numbers equality

ALWAYS prefer `TST_EXP_EQ_LU` for unsigned long long comparisons:

```c
/* WRONG: manual unsigned comparison */
if (size == expected_size)
    tst_res(TPASS, "Size matches");
else
    tst_res(TFAIL, "Size doesn't match");

/* CORRECT: use TST_EXP_EQ_LU for unsigned long long */
TST_EXP_EQ_LU(size, expected_size);
```

#### TPASS on size_t equality

ALWAYS prefer `TST_EXP_EQ_SZ` for size_t comparisons:

```c
/* WRONG: manual size_t comparison */
if (len == expected_len)
    tst_res(TPASS, "Length matches");
else
    tst_res(TFAIL, "Length doesn't match");

/* CORRECT: use TST_EXP_EQ_SZ for size_t values */
TST_EXP_EQ_SZ(len, expected_len);
```

#### TPASS on ssize_t equality

ALWAYS prefer `TST_EXP_EQ_SSZ` for ssize_t comparisons:

```c
/* WRONG: manual ssize_t comparison */
if (ret == expected_ret)
    tst_res(TPASS, "Return value matches");
else
    tst_res(TFAIL, "Return value doesn't match");

/* CORRECT: use TST_EXP_EQ_SSZ for ssize_t values */
TST_EXP_EQ_SSZ(ret, expected_ret);
```

#### TPASS on positive syscall return

ALWAYS use `TST_EXP_POSITIVE` when syscall should return >= 0:

```c
/* WRONG: manual positive check */
TEST(ret = syscall(args));
if (TST_RET < 0)
    tst_res(TFAIL | TTERRNO, "syscall failed");
else
    tst_res(TPASS, "syscall returned %ld", TST_RET);

/* CORRECT: use TST_EXP_POSITIVE */
TST_EXP_POSITIVE(syscall(args));
```

#### TPASS on PID return

ALWAYS use `TST_EXP_PID` when syscall returns a process ID:

```c
/* WRONG: manual pid check */
TEST(pid = fork());
if (TST_RET < 0)
    tst_res(TFAIL | TTERRNO, "fork failed");
else
    tst_res(TPASS, "fork returned pid %ld", TST_RET);

/* CORRECT: use TST_EXP_PID */
pid_t pid = TST_EXP_PID(fork());
```

#### TPASS on specific return value

ALWAYS use `TST_EXP_VAL` when expecting a specific return value:

```c
/* WRONG: manual value check */
TEST(ret = getuid());
if (TST_RET != expected_uid)
    tst_res(TFAIL, "getuid returned %ld, expected %d", TST_RET, expected_uid);
else
    tst_res(TPASS, "getuid returned expected value");

/* CORRECT: use TST_EXP_VAL */
TST_EXP_VAL(getuid(), expected_uid);
```

#### TPASS on syscall success (return 0)

ALWAYS use `TST_EXP_PASS` when syscall should return 0 on success:

```c
/* WRONG: manual success check */
TEST(ret = close(fd));
if (TST_RET != 0)
    tst_res(TFAIL | TTERRNO, "close failed");
else
    tst_res(TPASS, "close succeeded");

/* CORRECT: use TST_EXP_PASS */
TST_EXP_PASS(close(fd));
```

#### TPASS on valid pointer return

ALWAYS use `TST_EXP_PASS_PTR_VOID` when syscall returns a valid pointer
(not `(void *)-1`):

```c
/* WRONG: manual pointer check */
TEST(ptr = mmap(NULL, size, prot, flags, fd, 0));
if (TST_RET_PTR == MAP_FAILED)
    tst_res(TFAIL | TTERRNO, "mmap failed");
else
    tst_res(TPASS, "mmap returned %p", TST_RET_PTR);

/* CORRECT: use TST_EXP_PASS_PTR_VOID */
void *ptr = TST_EXP_PASS_PTR_VOID(mmap(NULL, size, prot, flags, fd, 0));
```

#### TFAIL on expected syscall failure

ALWAYS use `TST_EXP_FAIL` when syscall should fail with specific errno
(returns 0 on success):

```c
/* WRONG: manual failure check */
TEST(ret = open("/nonexistent", O_RDONLY));
if (TST_RET != -1 || TST_ERR != ENOENT)
    tst_res(TFAIL | TTERRNO, "Expected ENOENT");
else
    tst_res(TPASS | TTERRNO, "open failed as expected");

/* CORRECT: use TST_EXP_FAIL */
TST_EXP_FAIL(open("/nonexistent", O_RDONLY), ENOENT);
```

#### TFAIL on expected syscall failure (positive success)

ALWAYS use `TST_EXP_FAIL2` when syscall returns positive on success (e.g.
returns a PID, fd, or byte count). Use `TST_EXP_FAIL` (without `2`) when
syscall returns 0 on success.

```c
/* WRONG: manual failure check for fork */
TEST(pid = fork());
if (TST_RET >= 0 || TST_ERR != EAGAIN)
    tst_res(TFAIL | TTERRNO, "Expected EAGAIN");
else
    tst_res(TPASS | TTERRNO, "fork failed as expected");

/* CORRECT: use TST_EXP_FAIL2 */
TST_EXP_FAIL2(fork(), EAGAIN);
```

#### TFAIL on expected failure with multiple possible errnos

ALWAYS use `TST_EXP_FAIL_ARR` when syscall can fail with one of several errnos:

```c
/* WRONG: multiple errno checks */
TEST(ret = syscall(args));
if (TST_RET != -1 || (TST_ERR != EINVAL && TST_ERR != ENOSYS))
    tst_res(TFAIL | TTERRNO, "Expected EINVAL or ENOSYS");
else
    tst_res(TPASS | TTERRNO, "syscall failed as expected");

/* CORRECT: use TST_EXP_FAIL_ARR */
int expected_errnos[] = {EINVAL, ENOSYS};
TST_EXP_FAIL_ARR(syscall(args), expected_errnos, 2);
```

#### TFAIL on expected NULL pointer failure

ALWAYS use `TST_EXP_FAIL_PTR_NULL` when syscall should fail and return NULL:

```c
/* WRONG: manual NULL check */
TEST(ptr = malloc_huge(size));
if (TST_RET_PTR != NULL || TST_ERR != ENOMEM)
    tst_res(TFAIL | TTERRNO, "Expected ENOMEM");
else
    tst_res(TPASS | TTERRNO, "malloc failed as expected");

/* CORRECT: use TST_EXP_FAIL_PTR_NULL */
TST_EXP_FAIL_PTR_NULL(malloc_huge(size), ENOMEM);
```

#### TFAIL on expected (void \*)-1 failure

ALWAYS use `TST_EXP_FAIL_PTR_VOID` when syscall should fail and return
`(void *)-1`:

```c
/* WRONG: manual MAP_FAILED check */
TEST(ptr = mmap(NULL, huge_size, prot, flags, fd, 0));
if (TST_RET_PTR != MAP_FAILED || TST_ERR != ENOMEM)
    tst_res(TFAIL | TTERRNO, "Expected ENOMEM");
else
    tst_res(TPASS | TTERRNO, "mmap failed as expected");

/* CORRECT: use TST_EXP_FAIL_PTR_VOID */
TST_EXP_FAIL_PTR_VOID(mmap(NULL, huge_size, prot, flags, fd, 0), ENOMEM);
```

#### TFAIL on expected failure with NULL and multiple errnos

ALWAYS use `TST_EXP_FAIL_PTR_NULL_ARR` when syscall should fail with NULL and
one of several errnos:

```c
/* WRONG: multiple errno checks with manual NULL pointer check */
TEST(ptr = malloc_invalid(size));
if (TST_RET_PTR != NULL || (TST_ERR != EINVAL && TST_ERR != ENOMEM))
    tst_res(TFAIL | TTERRNO, "Expected EINVAL or ENOMEM");
else
    tst_res(TPASS | TTERRNO, "malloc_invalid failed as expected");

/* CORRECT: check NULL return with multiple possible errors */
int errors[] = {EINVAL, ENOMEM};
TST_EXP_FAIL_PTR_NULL_ARR(malloc_invalid(size), errors, 2);
```

#### TFAIL on expected failure with (void \*)-1 and multiple errnos

ALWAYS use `TST_EXP_FAIL_PTR_VOID_ARR` when syscall should fail with
`(void *)-1` and one of several errnos:

```c
/* WRONG: multiple errno checks with manual MAP_FAILED check */
TEST(ptr = mmap_invalid(NULL, size, prot, flags, -1, 0));
if (TST_RET_PTR != MAP_FAILED || (TST_ERR != EINVAL && TST_ERR != ENOMEM))
    tst_res(TFAIL | TTERRNO, "Expected EINVAL or ENOMEM");
else
    tst_res(TPASS | TTERRNO, "mmap_invalid failed as expected");

/* CORRECT: check MAP_FAILED with multiple possible errors */
int errors[] = {EINVAL, ENOMEM};
TST_EXP_FAIL_PTR_VOID_ARR(mmap_invalid(NULL, size, prot, flags, -1, 0), errors, 2);
```

#### TPASS on FD or TFAIL on expected error

ALWAYS use `TST_EXP_FD_OR_FAIL` when syscall should return FD or fail with
expected errno:

```c
/* WRONG: manual fd or fail check */
TEST(fd = open("file", O_RDONLY));
if (TST_RET == -1 && TST_ERR == ENOENT)
    tst_res(TPASS | TTERRNO, "open failed as expected");
else if (TST_RET < 0)
    tst_res(TFAIL | TTERRNO, "Unexpected error");
else
    tst_res(TPASS, "open returned fd %ld", TST_RET);

/* CORRECT: use TST_EXP_FD_OR_FAIL */
int fd = TST_EXP_FD_OR_FAIL(open("file", O_RDONLY), ENOENT);
```

#### TPASS on boolean expression

ALWAYS use `TST_EXP_EXPR` for boolean expression checks:

```c
/* WRONG: manual expression check */
if (uid > 0 && gid > 0)
    tst_res(TPASS, "IDs are valid");
else
    tst_res(TFAIL, "IDs are invalid");

/* CORRECT: use TST_EXP_EXPR */
TST_EXP_EXPR(uid > 0 && gid > 0, "IDs should be positive");
```

#### TBROK for syscall failures, not TINFO | TERRNO

NEVER use `tst_res(TINFO | TERRNO, ...)` to report syscall failures:

```c
/* WRONG: TINFO | TERRNO misused for error reporting */
fd = open(path, O_RDWR);
if (fd < 0) {
    tst_res(TINFO | TERRNO, "open failed");
    exit(1);
}

ptr = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
if (ptr == MAP_FAILED) {
    tst_res(TINFO | TERRNO, "mmap failed");
    SAFE_CLOSE(fd);
    exit(1);
}

/* CORRECT: use TBROK | TERRNO for syscall errors */
fd = open(path, O_RDWR);
if (fd < 0)
    tst_brk(TBROK | TERRNO, "open failed");

ptr = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
if (ptr == MAP_FAILED) {
    SAFE_CLOSE(fd);
    tst_brk(TBROK | TERRNO, "mmap failed");
}
```

### Memory Allocations

#### Release mmap() allocations

NEVER leave `mmap()` allocations without `munmap()` in cleanup:

```c
/* WRONG: mmap'd memory not released in cleanup */
static void *addr = NULL;

static void setup(void) {
    addr = SAFE_MMAP(NULL, size, prot, flags, fd, 0);
}

static struct tst_test test = {
    .setup = setup,
    /* WRONG: missing .cleanup to munmap */
    .test_all = run,
};
```

ALWAYS `munmap()` in cleanup when `mmap()` in `setup()`:

```c
/* CORRECT: mmap resources released in cleanup */
static void *addr = NULL;

static void setup(void) {
    addr = SAFE_MMAP(NULL, size, prot, flags, fd, 0);
}

static void cleanup(void) {
    if (addr != NULL)
        SAFE_MUNMAP(addr, size);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
};
```

#### Release malloc() allocations

NEVER leave malloc'd memory without `free()` in cleanup:

```c
/* WRONG: malloc'd memory not released in cleanup */
static char *buffer = NULL;

static void setup(void) {
    buffer = SAFE_MALLOC(size);
}

static struct tst_test test = {
    .setup = setup,
    /* WRONG: missing .cleanup to free */
    .test_all = run,
};
```

ALWAYS `free()` in cleanup when `malloc()`:

```c
/* CORRECT: malloc resources released in cleanup */
static char *buffer = NULL;

static void setup(void) {
    buffer = SAFE_MALLOC(size);
}

static void cleanup(void) {
    free(buffer);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
};
```

#### Use `.bufs` for tested syscall struct arguments

NEVER allocate syscall struct arguments on the stack as local variables, if the
syscall is the subject of our test:

```c
/* WRONG: stack-allocated struct passed by address */
static void verify(unsigned int n)
{
    struct listns_req req = {
        .size = NS_ID_REQ_SIZE_VER0,
        .ns_type = tc->clone_flag,
    };

    TEST(listns(&req, buf, size, 0));
}

static struct tst_test test = {
    .test = verify,
    .tcnt = ARRAY_SIZE(tcases),
};
```

ALWAYS declare a static pointer and use `.bufs` to let the framework allocate it:

```c
/* CORRECT: framework-managed allocation via .bufs */
static struct listns_req *req;

static void verify(unsigned int n)
{
    req->size = NS_ID_REQ_SIZE_VER0;
    req->ns_type = tc->clone_flag;

    TEST(listns(req, buf, size, 0));
}

static struct tst_test test = {
    .test = verify,
    .tcnt = ARRAY_SIZE(tcases),
    .bufs = (struct tst_buffers []) {
        {&req, .size = sizeof(*req)},
        {},
    },
};
```

#### Memory re-initialization for iterative testing (-i parameter)

NEVER rely on static initialization for data modified during test logic when
using `-i` parameter:

```c
static char str[256];
static int fd = -1;

static void run(void)
{
    ...

    /* WRONG: static str not re-initialized but re-used before each iteration */
    SAFE_READ(0, fd, str, mylen);

    /* here we might have a string without \0 terminator */
}
```

ALWAYS re-initialize static data at the start of `run()` before using it:

```c
static char str[256];
static int fd = -1;

static void run(void)
{
    ...

    /* CORRECT: str re-initialized before each test iteration */
    memset(str, 0, sizeof(str));
    SAFE_READ(0, fd, str, mylen);

    /* here we are sure buffer has a \0 terminator */
}
```

### Test Case Parametrization

NEVER define separate functions for each test case and call them manually:

```c
/* WRONG: separate functions called manually from run() */
static void test_new_file_no_creat(void)
{
    TST_EXP_FAIL2(open("nofile", O_RDWR, 0444), ENOENT,
        "open() new file without O_CREAT");
}

static void test_noatime_unprivileged(void)
{
    TST_EXP_FAIL2(open("test_file2", O_RDONLY | O_NOATIME, 0444), EPERM,
        "open() unprivileged O_RDONLY | O_NOATIME");
}

static void run(void)
{
    /* WRONG: manual dispatch, no automatic sub-test numbering */
    test_new_file_no_creat();
    test_noatime_unprivileged();
}

static struct tst_test test = {
    /* WRONG: .test_all used instead of .test + .tcnt */
    .test_all = run,
};
```

ALWAYS define a single `struct tcase` array and use `.test` + `.tcnt` in
`struct tst_test`. The test function receives the index `n` and dispatches
through the array:

```c
/* CORRECT: one struct tcase array, one generic handler, .test + .tcnt */
static struct tcase {
    const char *filename;
    int flag;
    int exp_errno;
    const char *desc;
} tcases[] = {
    {"nofile",      O_RDWR,               ENOENT, "new file without O_CREAT"},
    {"test_file2",  O_RDONLY | O_NOATIME, EPERM,  "unprivileged O_RDONLY | O_NOATIME"},
};

static void verify_open(unsigned int n)
{
    struct tcase *tc = &tcases[n];

    TST_EXP_FAIL2(open(tc->filename, tc->flag, 0444),
        tc->exp_errno, "open() %s", tc->desc);
}

static struct tst_test test = {
    /* CORRECT: framework iterates tcases[], prints "1.", "2.", … automatically */
    .tcnt = ARRAY_SIZE(tcases),
    .test = verify_open,
};
```

Key rules:

- `.test` (takes `unsigned int n`) is used when there are multiple test cases.
- `.test_all` (takes no arguments) is used only when there is a single test case.
- NEVER use separate per-case functions called from `run()`.
- NEVER use `.test_all` when multiple cases exist.

### Path Buffers

NEVER define a custom buffer size for path strings:

```c
/* WRONG: custom size may be too small for real paths */
#define BUF_SIZE 256
static char fname[BUF_SIZE];
static char fname_copy[BUF_SIZE];

static void run(void)
{
    SAFE_GETCWD(fname, BUF_SIZE);
    /* silently truncates if CWD > 255 chars */
    snprintf(fname_copy, sizeof(fname_copy), "%s.bak", fname);
}
```

ALWAYS use `PATH_MAX` for buffers that hold filesystem paths:

```c
/* CORRECT: PATH_MAX (4096) accommodates any valid path */
#include <limits.h>

static char fname[PATH_MAX];
static char fname_copy[PATH_MAX];

static void run(void)
{
    SAFE_GETCWD(fname, sizeof(fname));
    snprintf(fname_copy, sizeof(fname_copy), "%s.bak", fname);
}
```

Note: `PATH_MAX` is for **full paths**. For buffers holding only a **filename**
(not a full path), use `NAME_MAX + 1` (= 256 on Linux). For example,
`struct inotify_event.name` stores a filename, so `NAME_MAX + 1` is correct
there — not `PATH_MAX`.

### Kernel Config Dependencies

NEVER manually check for kernel config features by handling ioctl/syscall
errors at runtime when `.needs_kconfigs` can be used:

```c
/* WRONG: manually handling missing kernel config */
static void run(void)
{
    TEST(ioctl(dev_fd, FS_IOC_GETLBMD_CAP, meta_cap));
    if (TST_RET == -1 && TST_ERR == EINVAL)
        tst_brk(TCONF, "CONFIG_BLK_DEV_INTEGRITY is not enabled");

    /* ... */
}

static struct tst_test test = {
    .test_all = run,
    .needs_device = 1,
};
```

ALWAYS use `.needs_kconfigs` to gate on required kernel configuration options:

```c
/* CORRECT: framework checks kernel config before running the test */
static void run(void)
{
    TST_EXP_PASS(ioctl(dev_fd, FS_IOC_GETLBMD_CAP, meta_cap),
        "FS_IOC_GETLBMD_CAP on block device");

    /* ... */
}

static struct tst_test test = {
    .test_all = run,
    .needs_device = 1,
    .needs_kconfigs = (const char *[]) {
        "CONFIG_BLK_DEV_INTEGRITY=y",
        NULL,
    },
};
```

### Using Syscalls

#### Using tst_syscall

NEVER call plain syscalls:

```c
/* WRONG: syscall() requires ENOSYS check */
syscall(__NR_listns, &req, NULL, 0, 0);
if (errno == ENOSYS)
        tst_brk(TCONF, "listns() not supported");
```

ALWAYS use `tst_syscall` instead:

```c
/* CORRECT: tst_syscall() always verify that errno == ENOSYS */
tst_syscall(__NR_listns, &req, NULL, 0, 0);
```

#### Importing Syscalls IDs

Syscalls `__NR_*` identifiers are ALWAYS defined in `lapi/syscalls.h`:

```c
#include "lapi/syscalls.h"

static void setup(void)
{
    tst_syscall(__NR_listns, &req, NULL, 0, 0);
}
```

### Child Process Handling

#### Parent - Child Synchronization

NEVER signal the parent from the child before setup is complete:

```c
/* WRONG: child signals before doing setup, parent may proceed too early */
child_pid = SAFE_FORK();
if (!child_pid) {
    TST_CHECKPOINT_WAKE(0);
    SAFE_UNSHARE(CLONE_NEWNS);
    TST_CHECKPOINT_WAIT(0);
    exit(0);
}

TST_CHECKPOINT_WAIT(0);
/* ... test work ... */
TST_CHECKPOINT_WAKE(0);
SAFE_WAITPID(child_pid, NULL, 0);
```

ALWAYS let the child wait for the parent's go-ahead, do setup, then signal
completion:

```c
/* CORRECT: parent triggers child, waits for setup, tests, then releases */
child_pid = SAFE_FORK();
if (!child_pid) {
    TST_CHECKPOINT_WAIT(0);
    /* child setup */
    TST_CHECKPOINT_WAKE_AND_WAIT(0);
    exit(0);
}

TST_CHECKPOINT_WAKE_AND_WAIT(0);
/* ... test work ... */
TST_CHECKPOINT_WAKE(0);
SAFE_WAITPID(child_pid, NULL, 0);
```

### Child Process Exit

NEVER let a child process return or fall through without an explicit exit:

```c
/* WRONG: missing exit, child may fall through into parent code */
child_pid = SAFE_FORK();
if (!child_pid) {
    /* child work */
}
/* parent code */
```

ALWAYS call `exit(0)` at the end of the child block:

```c
/* CORRECT: child always exits explicitly */
child_pid = SAFE_FORK();
if (!child_pid) {
    /* child work */
    exit(0);
}
/* parent code */
```

### Child Process Reaping

NEVER reap children before exit the test. LTP framework calls
`tst_reap_children()` before exiting and handles reaping automatically:

```c
static void run(void)
{
    pid_t child_pid;

    child_pid = SAFE_FORK();
    if (!child_pid) {
        exit(0);
    }

    /* WRONG: explicit waitpid is redundant */
    SAFE_WAITPID(child_pid, NULL, 0);
}
```

ALWAYS rely on the framework to reap children:

```c
static void run(void)
{
    if (!SAFE_FORK()) {
        exit(0);
    }

    /* CORRECT: let the framework reaping the child */
}
```

### Static Variable Initialization

Static variables whose value is fully derived from other statics already set
in `setup()` MUST be initialized in `setup()` as well, NOT inside `run()`.
Recomputing a constant derived value on every iteration is redundant and
misleading — it implies the value may change across iterations when it does not.

WRONG — derived value recomputed on every call to `run()`:

```c
static long page_size;
static size_t buf_size;

static void setup(void)
{
    page_size = getpagesize();
}

static void run(void)
{
    buf_size = page_size * 2;  /* needlessly recomputed every iteration */
    ...
}
```

CORRECT — derived value computed once in `setup()`:

```c
static long page_size;
static size_t buf_size;

static void setup(void)
{
    page_size = getpagesize();
    buf_size = page_size * 2;
}

static void run(void)
{
    /* use buf_size directly */
}
```
