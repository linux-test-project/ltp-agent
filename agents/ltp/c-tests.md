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
 * Explaination of how algorithm in the test works in a list (-) syntax.
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
- C tests must be written in C99 (or later C standard)

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

- MUST use `SAFE_*` macros for system calls that must not fail
- Safe macros are defined in `include/` directory

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

### 13. Deprecated Features

- MUST NOT define `[Description]` in the test description section

## Code Examples

The following sections contain examples which are considered reference when
rewriting old LTP tests or when writing new LTP tests.

ALWAYS follow these rules.

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
with it. If it exists, use it. If it doesn't, verify if you can create it.

```c
/* WRONG: don't use plain syscalls */
int fd = open("test_file", O_RDWR | O_CREAT, 0644);
if (fd > 0) {
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
    if (fd > 0)
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
    if (fd > 0)
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
    if (fd > 0)
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
    if (fd > 0)
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
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
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

ALWAYS use `TST_EXP_FAIL2` when syscall returns positive on success:

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
/* CORRECT: check NULL return with multiple possible errors */
int errors[] = {EINVAL, ENOMEM};
TST_EXP_FAIL_PTR_NULL_ARR(malloc_invalid(size), errors, 2);
```

#### TFAIL on expected failure with (void \*)-1 and multiple errnos

ALWAYS use `TST_EXP_FAIL_PTR_VOID_ARR` when syscall should fail with
`(void *)-1` and one of several errnos:

```c
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
