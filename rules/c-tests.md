<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# C Test Rules

This file contains MANDATORY rules for C tests (`*.c` or `*.h` files), EXCEPT
files under `testcases/open_posix_testsuite/` -- those tests use different
APIs and conventions (see `{{LTP_AGENT_DIR}}/rules/openposix.md`).

## Required Test Structure

Every C test MUST follow this structure:

```c
// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (c) YYYY Author Name <email@example.org>
 */

/*\
 * High-level RST-formatted test description goes here.
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

When working with LTP tests verify ALL of the following:

### 1. Coding Style

- Code MUST follow Linux kernel coding style
- `make check` or `make check-$TCID` MUST pass (uses vendored `checkpatch.pl`)
- MUST use C99 features where appropriate
- Variables declared after statements (C99/C11 style) are allowed and MUST
  NOT be flagged as errors or style issues. NEVER suggest moving a variable
  declaration to the top of the function -- this is an explicit exception to
  the kernel coding style rule
- Identifiers e.g. function, variable, macro names must not start with
  underscore since these are reserved for compiler, kernel, and libc
- MUST NOT use curly braces when the body is a single line
- MUST use curly braces when the body spans multiple lines
- MUST NOT add comments that describe obvious, i.e. literal translation of what
  the code does into the english

### 2. API Usage

- MUST use new API (`tst_test.h`), NOT old API (`test.h`)
- MUST NOT define `main()` (unless `TST_NO_DEFAULT_MAIN` is used)
- MUST use `struct tst_test` for configuration
- Handlers MUST be thin; logic goes in `.setup` and `.cleanup` callbacks

### 3. Test Execution Model

The LTP framework drives test callbacks in a specific order. Understanding
this lifecycle is essential for judging resource management, state reuse,
and iteration safety.

- `.setup` -- called **once** before all test iterations
- `.test` / `.test_all` -- called **per iteration** (the `-i N` option
  controls how many times)
- `.cleanup` -- called **once** after all iterations complete, and also on
  `tst_brk()` fatal errors

Because `.setup` and `.cleanup` are one-shot, resources allocated in
`.setup` and released in `.cleanup` do not need guards against repeated
calls.

Conversely, `.test` / `.test_all` may run many times, so any state
modified during a test iteration MUST be safe for re-entry (see rule 12
on static variable re-initialization).

### 4. Synchronization

- MUST NOT use `sleep()`, `usleep()`, or `nanosleep()` for synchronization
  (tests that sleep as part of testing timer APIs are exempt)
- Use instead: `SAFE_WAITPID()`, `TST_CHECKPOINT_WAIT()` /
  `TST_CHECKPOINT_WAKE()`, `TST_PROCESS_STATE_WAIT()`, or
  exponential-backoff polling
- SHOULD prefer the LTP `TST_CHECKPOINT_*` API over hand-rolled
  synchronization (pipes, eventfd, shared-memory flags) for inter-process
  rendezvous, unless the IPC itself is what the test exercises

### 5. Syscall Correctness

- Syscall usage MUST match man pages and kernel code

### 6. File Organization

- New test binary MUST be added to corresponding `.gitignore`
- Datafiles go in `datafiles/` subdirectory (installed to `testcases/data/$TCID`)
- Syscall tests go under `testcases/kernel/syscalls/`
- Entry MUST exist in appropriate `runtest/` file
- Sub-executables MUST use `$TESTNAME_` prefix
- MUST use `.needs_tmpdir = 1` for temp files (work in current directory)

### 7. Result Reporting

- MUST use `tst_res()` for results: `TPASS`, `TFAIL`, `TCONF`, `TBROK`, `TINFO`
- MUST use `tst_brk()` for fatal errors that abort the test
- MUST use `TEST()` macro to capture return value (`TST_RET`) and errno (`TST_ERR`)
- MUST return `TCONF` (not `TFAIL`) when feature is unavailable

### 8. Safe Macros

- MUST use `SAFE_*` macros for system calls that have a `SAFE_*` version in `include/`
- EXCEPTION: when the syscall is the **subject** of the test (e.g. testing
  `close()` error paths), do not use `SAFE_*` wrappers -- they abort on
  failure, which defeats testing failure behavior
- Subject syscalls MUST still be wrapped in `TEST()` or a `TST_EXP_*`
  macro -- never called bare
- Safe macros are defined in `include/` directory (search `tst_*.h` headers)
- If no `SAFE_*` version exists, verify whether one can be added; otherwise use manual error handling
- Do not check the return value of `SAFE_*` macros -- they abort on failure.

### 9. Runtime Feature Detection

- MUST prefer runtime checks over compile-time checks
- MUST use `.min_kver` for kernel version gating
- `configure.ac` compile-time checks may ONLY enable fallback API definitions
  in `include/lapi/`
- Runtime detection methods: errno checks (`ENOSYS`/`EINVAL`), `.min_kver`,
  `.needs_kconfigs`, kernel `.config` parsing

### 10. Tagging

- Regression tests MUST include `.tags` in `struct tst_test`
- Do NOT suggest adding GitHub PRs or GitHub issue URLs to `.tags`

### 11. Cleanup

- Cleanup MUST run on ALL exit paths
- MUST unmount, restore sysctls, delete temp files, kill processes,
  and remove SysV IPC objects (shared memory, semaphores, message queues
  persist after the process exits and MUST be removed with `IPC_RMID`)

### 12. Static Variables

- Static variables MUST be initialized before use in test logic (for `-i` option)
- Static allocated variables MUST be released in cleanup if allocated in setup

### 13. Memory Allocation

- Memory MUST be correctly deallocated
- EXCEPTION: If `.bufs` is used, ignore check for memory allocated with it

### 14. String Handling

- MUST use `snprintf()` when combining strings
- MUST use `PATH_MAX` for path buffers, NOT custom size macros (see Path Buffers)

### 15. Architecture-Specific Tests

- MUST use `.supported_archs` in `struct tst_test` when the target architectures
  are supported by the framework (see `lib/tst_arch.c`)
- `#if defined(...)` arch guards are only acceptable when the target architecture
  is not supported by the framework

### 16. Compile-time Feature Guards (`HAVE_*`)

When the entire test depends on a compile-time feature flag (e.g. `HAVE_NUMA_V2`,
`HAVE_SYS_XATTR_H`), the `#ifdef` MUST wrap ALL test code at the file level --
never inside individual functions.

Rules:

- The `#ifdef HAVE_*` MUST appear after the includes that bring in `config.h`
  (which defines the `HAVE_*` macros), so that the guard is evaluated correctly
- ALL `#define` macros, static variables, helper functions, and `struct tst_test`
  MUST be inside the `#ifdef` block
- The `#else` branch MUST use `TST_TEST_TCONF("...")` with a human-readable
  literal string explaining what is missing -- NEVER use the `HAVE_*` macro name
  or a generic constant like `NUMA_ERROR_MSG` as the message
- When a support/helper `.c` file's entire body depends on the same feature flag,
  wrap the whole file body in a single top-level `#ifdef` -- NEVER scatter
  per-function guards inside the same file

WRONG -- guard buried inside a function:

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

CORRECT -- guard at file level, `struct tst_test` inside, `TST_TEST_TCONF` in `#else`:

```c
#include "tst_test.h"
#include "move_pages_support.h"  /* brings in config.h -> defines HAVE_NUMA_V2 */

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

### 17. Commit Messages

For commit-message rules, see `{{LTP_AGENT_DIR}}/rules/commit-message.md`.

### 18. Deprecated Features

- MUST NOT define `[Description]` in the test description section

### 19. Test high-level description

- The `/*\ ... */` doc comment MUST explain _what_ syscall, feature, or
  behavior is being tested (this block is exported to documentation).
- Flag if the description is missing, empty, or too generic (e.g.
  "Test for foo()" without stating what aspect of foo() is verified).
- Flag if the description looks copy-pasted from another test (e.g.
  references a different syscall or file name).
- When flagging, suggest a concrete replacement based on what the test
  code actually does.
- When referring to raw syscall or syscall libc wrapper in `/*\ ... */`
  ALWAYS use formatting with correct manpage section, e.g.:
  ``:manpage:`execve(2)` ``, which creates link to the man page
  [`execve(2)`](https://man7.org/linux/man-pages/man2/execve.2.html)
  in our [test catalog](https://linux-test-project.readthedocs.io/en/latest/users/test_catalog.html).
- Ordered and bulleted lists MUST be separated from the previous text by a
  blank line.
- Copyright line MUST be present with year and author

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

ALWAYS follow these rules when working with new LTP API.

### Architecture-Specific Tests

When the target architectures are supported by the framework, do NOT use
preprocessor arch guards:

WRONG -- preprocessor arch guards instead of .supported_archs:

```c
#if defined(__i386__) || defined(__x86_64__)
static void run(void)
{
    /* test logic */
}
#endif
```

CORRECT -- use `.supported_archs` in `struct tst_test`:

```c
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

WRONG -- importing legacy API:

```c
#include "test.h"
```

CORRECT -- use new LTP API:

```c
#include "tst_test.h"
```

#### Use SAFE\_\* macros

ALWAYS verify that syscalls we are using have a `SAFE_*` version associated
with it inside the `include/tst_*.h` files. If it exists, use it. If it
doesn't, verify if you can create it.

WRONG -- plain syscall without SAFE\_\* macro:

```c
int fd = open("test_file", O_RDWR | O_CREAT, 0644);
if (fd < 0) {
    tst_brk(TBROK | TERRNO, "open() error");
}
```

CORRECT -- use SAFE\_\* macros:

```c
int fd = SAFE_OPEN("test_file", O_RDWR | O_CREAT, 0644);
```

#### Don't define SAFE\_\* macros inside the test

The `SAFE_*` prefix is reserved by the LTP core library. Tests MUST NOT
define their own `SAFE_*` macros.

WRONG -- test defines its own SAFE\_\* macro:

```c
#define SAFE_TRY_UNLINK(path) do { \
    if (unlink(path) == -1 && errno != ENOENT) \
        tst_brk(TBROK | TERRNO, "unlink(%s) failed", path); \
} while (0)
```

CORRECT -- use a plain helper or open-code the call:

```c
static void try_unlink(const char *path)
{
    if (unlink(path) == -1 && errno != ENOENT)
        tst_brk(TBROK | TERRNO, "unlink(%s) failed", path);
}
```

If the wrapper is generic enough, add it to `include/tst_safe_*.h`
following the conventions in the section below.

### New SAFE\_\* macros definition

#### Don't use `cleanup_fn` in newly added `safe_*` definitions

WRONG -- cleanup_fn is used in the legacy LTP API:

```c
void *safe_mysyscall(const char *file, const int lineno, void (*cleanup_fn) (void),
        size_t size)
{
    void *rval;

    rval = mysyscall(size);

    if (rval == NULL) {
        /* tst_brkm_ is used by the legacy API */
        tst_brkm_(file, lineno, TBROK | TERRNO, cleanup_fn,
            "mysyscall(%zu) failed", size);
    }

    return rval;
}
```

CORRECT -- new LTP API format for safe\_\* definitions:

```c
void *safe_mysyscall(const char *file, const int lineno,
        size_t size)
{
    void *rval;

    rval = mysyscall(size);

    if (rval == NULL) {
        /* tst_brk_ is used by the new API */
        tst_brk_(file, lineno, TBROK | TERRNO,
            "mysyscall(%zu) failed", size);
    }

    return rval;
}
```

### Temporary folder

Tests that create files MUST set `.needs_tmpdir = 1` in `struct tst_test`.
The framework creates a temporary directory and `chdir`s into it before
calling `.setup`. NEVER create files in the current directory without it:

```c
static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```

### File descriptors

#### Initialization and cleanup

File descriptors MUST be initialized to `-1` (not left as `0`, which is
stdin) and MUST be closed in `cleanup()` with a `fd != -1` guard:

WRONG -- fd initialized to zero, no cleanup:

```c
static int fd;     /* zero is a valid fd (stdin) */
/* no .cleanup to close the fd */
```

CORRECT -- init to -1, open in setup, close in cleanup:

```c
static int fd = -1;

static void setup(void)
{
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void)
{
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

`SAFE_CLOSE()` is a macro that calls `safe_close()` and ALWAYS sets the passed
argument file descriptor to `-1` in a single step. This applies everywhere in
the code. NEVER set the passed argument to `-1` after `SAFE_CLOSE()`.

#### Ensure resources are released in `cleanup()` after `tst_brk()` or failing `SAFE_*` macros

`tst_brk()` and `SAFE_*` macros can abort `run()` at any point by jumping
to `cleanup()`. If a resource is acquired in `run()` and only released at
the end of `run()`, the release is skipped on abort and the resource leaks.

This is especially critical for resources that outlive the process -- such as
mounted filesystems, SysV IPC objects (shared memory, semaphores, message
queues), loop devices, modified sysctls or `/proc`/`/sys` values, and cgroups.

WRONG -- mount done in `run()` with no `cleanup()`, leaked if `SAFE_WRITE`
aborts:

```c
static void run(void)
{
    int fd;

    SAFE_MOUNT("none", MNTPOINT, "tmpfs", 0, NULL);

    fd = SAFE_OPEN(MNTPOINT "/file", O_CREAT | O_RDWR, 0644);
    SAFE_WRITE(SAFE_WRITE_ALL, fd, "x", 1); /* may call tst_brk() */

    /* these are never reached on abort -- mount persists! */
    SAFE_CLOSE(fd);
    SAFE_UMOUNT(MNTPOINT);
}

static struct tst_test test = {
    .test_all = run,
    .needs_root = 1,
    .needs_tmpdir = 1,
};
```

CORRECT -- state tracked in statics, `cleanup()` handles all exit paths:

```c
static int fd = -1;
static int mounted;

static void run(void)
{
    SAFE_MOUNT("none", MNTPOINT, "tmpfs", 0, NULL);
    mounted = 1;

    fd = SAFE_OPEN(MNTPOINT "/file", O_CREAT | O_RDWR, 0644);
    SAFE_WRITE(SAFE_WRITE_ALL, fd, "x", 1);

    SAFE_CLOSE(fd);
    SAFE_UMOUNT(MNTPOINT);
    mounted = 0;
}

static void cleanup(void)
{
    if (fd != -1)
        SAFE_CLOSE(fd);

    if (mounted)
        SAFE_UMOUNT(MNTPOINT);
}

static struct tst_test test = {
    .test_all = run,
    .cleanup = cleanup,
    .needs_root = 1,
    .needs_tmpdir = 1,
};
```

#### Use `fd != -1` to check file descriptor validity

NEVER use `fd >= 0` or `fd > 0` to check whether a file descriptor is valid:

WRONG -- fd >= 0 or fd > 0 to check validity:

```c
/* fd >= 0 is not the LTP convention */
if (fd >= 0)
    SAFE_CLOSE(fd);

/* fd > 0 silently skips fd 0 which is valid */
if (fd > 0)
    SAFE_CLOSE(fd);
```

ALWAYS use `fd != -1` since file descriptors are initialized to `-1`:

CORRECT -- matches the -1 initialization convention:

```c
if (fd != -1)
    SAFE_CLOSE(fd);
```

### Tests Results

#### Report results with `tst_res()`, NEVER via return values

Test results MUST be reported by calling `tst_res()` or `tst_brk()` directly
at the point where the outcome is determined. NEVER propagate pass/fail status
through function return values, flags, or variables -- this obscures what was
actually tested and makes the output harder to trace back to the source.

WRONG -- result propagated via return value:

```c
static int check_result(int val, int expected)
{
    if (val != expected)
        return 1;

    return 0;
}

static void run(void)
{
    int ret;

    TEST(syscall_under_test());

    /* result is invisible in the check function */
    if (check_result(TST_RET, 0))
        tst_res(TFAIL, "unexpected return value");
    else
        tst_res(TPASS, "syscall succeeded");
}
```

CORRECT -- result reported directly where it is checked:

```c
static void run(void)
{
    TST_EXP_PASS(syscall_under_test());
}
```

If a helper function performs multiple checks, it MUST call `tst_res()`
itself for each check rather than returning a status code to the caller.

#### Report results with `tst_res()` in children, NEVER via exit values

The LTP library automatically propagates `tst_res()` calls from children to the
parent. NEVER encode pass/fail as the child's exit code and interpret it in the
parent -- this obscures what was actually tested and loses the error message
context.

WRONG -- child exit code used to propagate result:

```c
static void run(void)
{
    int status;
    pid_t pid = SAFE_FORK();

    if (!pid) {
        TEST(syscall_under_test());
        if (TST_RET != 0)
            exit(1);
        exit(0);
    }

    SAFE_WAITPID(pid, &status, 0);

    /* parent guesses what happened in the child */
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
        tst_res(TPASS, "syscall succeeded");
    else
        tst_res(TFAIL, "syscall failed");
}
```

CORRECT -- child calls `tst_res()` directly, library propagates to parent:

```c
static void run(void)
{
    if (!SAFE_FORK())
        TST_EXP_PASS(syscall_under_test());
}
```

#### Use `TST_EXP_*` macros instead of manual `TEST()` + `if/else` + `tst_res()`

ALWAYS prefer `TST_EXP_*` macros over manual `TEST()` + `if/else` +
`tst_res()` blocks. `TEST()` is only appropriate when the test needs custom
logic beyond what any `TST_EXP_*` macro provides (e.g. multiple side-effect
checks after one syscall).

WRONG -- manual check and reporting:

```c
TEST(syscall(args));

if (TST_RET == -1) {
    tst_res(TFAIL | TTERRNO, "syscall failed");
    return;
}

tst_res(TPASS, "syscall returned %ld", TST_RET);
```

CORRECT -- use the appropriate `TST_EXP_*` macro:

```c
TST_EXP_PASS(syscall(args));
```

Use the following table to pick the right macro. The same principle applies
to every entry: replace manual `if/else` + `tst_res()` with the one-liner.

**Success macros:**

| Scenario                                         | Macro                              |
| ------------------------------------------------ | ---------------------------------- |
| Syscall returns 0 on success                     | `TST_EXP_PASS(syscall(...))`       |
| Syscall returns positive (fd, pid, byte count)   | `TST_EXP_POSITIVE(syscall(...))`   |
| Syscall returns a PID                            | `TST_EXP_PID(fork())`              |
| Syscall returns a file descriptor                | `TST_EXP_FD(open(...))`            |
| Expect a specific return value                   | `TST_EXP_VAL(getuid(), expected)`  |
| Syscall returns valid pointer (not `(void *)-1`) | `TST_EXP_PASS_PTR_VOID(mmap(...))` |
| Boolean expression check                         | `TST_EXP_EXPR(uid > 0, "msg")`     |

**Equality macros:**

| Scenario                              | Macro                      |
| ------------------------------------- | -------------------------- |
| Signed long long equality             | `TST_EXP_EQ_LI(a, b)`      |
| Unsigned long long equality           | `TST_EXP_EQ_LU(a, b)`      |
| `size_t` equality                     | `TST_EXP_EQ_SZ(a, b)`      |
| `ssize_t` equality                    | `TST_EXP_EQ_SSZ(a, b)`     |
| Null-terminated string equality       | `TST_EXP_EQ_STR(a, b)`     |
| Length-limited string/buffer equality | `TST_EXP_EQ_STRN(a, b, n)` |

Also use `TST_EXP_EQ_STRN` instead of manual `memcmp()` + `tst_res()`, and
`TST_EXP_EQ_STR` instead of manual `strcmp()` + `tst_res()`.

**Failure macros:**

| Scenario                                                     | Macro                                             |
| ------------------------------------------------------------ | ------------------------------------------------- |
| Syscall fails with errno (returns -1 on error, 0 on success) | `TST_EXP_FAIL(open(...), ENOENT)`                 |
| Syscall fails with errno (returns positive on success)       | `TST_EXP_FAIL2(fork(), EAGAIN)`                   |
| Fails with one of several errnos                             | `TST_EXP_FAIL_ARR(syscall(...), errnos, cnt)`     |
| Fail returning `NULL`                                        | `TST_EXP_FAIL_PTR_NULL(fn(...), ENOMEM)`          |
| Fail returning `(void *)-1`                                  | `TST_EXP_FAIL_PTR_VOID(mmap(...), ENOMEM)`        |
| Fail `NULL` + multiple errnos                                | `TST_EXP_FAIL_PTR_NULL_ARR(fn(...), errs, cnt)`   |
| Fail `(void *)-1` + multiple errnos                          | `TST_EXP_FAIL_PTR_VOID_ARR(mmap(...), errs, cnt)` |
| FD on success or expected errno on failure                   | `TST_EXP_FD_OR_FAIL(open(...), ENOENT)`           |

**`TST_EXP_FAIL` vs `TST_EXP_FAIL2`:** use `TST_EXP_FAIL` when the syscall
returns 0 on success (e.g. `close`, `chmod`). Use `TST_EXP_FAIL2` when it
returns a positive value on success (e.g. `open`, `fork`, `read`).

#### TBROK for syscall failures, not TINFO | TERRNO

NEVER use `tst_res(TINFO | TERRNO, ...)` to report syscall failures:

WRONG -- TINFO | TERRNO misused for error reporting:

```c
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
```

CORRECT -- use TBROK | TERRNO for syscall errors:

```c
fd = SAFE_OPEN(path, O_RDWR);
if (fd < 0)
    tst_brk(TBROK | TERRNO, "open failed");

ptr = SAFE_MMAP(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
if (ptr == MAP_FAILED) {
    SAFE_CLOSE(fd);
    tst_brk(TBROK | TERRNO, "mmap failed");
}
```

### Memory Allocations

#### Release memory allocations in cleanup

Memory allocated in `setup()` MUST be released in `cleanup()`. This applies
to `mmap()` / `SAFE_MMAP()` (use `SAFE_MUNMAP()`) and `malloc()` /
`SAFE_MALLOC()` (use `free()`):

CORRECT -- mmap resources released in cleanup:

```c
static void *addr = NULL;

static void setup(void)
{
    addr = SAFE_MMAP(NULL, size, prot, flags, fd, 0);
}

static void cleanup(void)
{
    if (addr != NULL)
        SAFE_MUNMAP(addr, size);
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

WRONG -- stack-allocated struct passed by address:

```c
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

CORRECT -- framework-managed allocation via .bufs:

```c
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

WRONG -- static data not re-initialized between iterations:

```c
static char str[256];
static int fd = -1;

static void run(void)
{
    ...

    /* static str not re-initialized but re-used before each iteration */
    SAFE_READ(0, fd, str, mylen);

    /* here we might have a string without \0 terminator */
}
```

ALWAYS re-initialize static data at the start of `run()` before using it:

CORRECT -- re-initialize static data before each iteration:

```c
static char str[256];
static int fd = -1;

static void run(void)
{
    ...

    /* str re-initialized before each test iteration */
    memset(str, 0, sizeof(str));
    SAFE_READ(0, fd, str, mylen);

    /* here we are sure buffer has a \0 terminator */
}
```

### Test Case Parametrization

NEVER define separate functions for each test case and call them manually:

WRONG -- separate functions called manually from run():

```c
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
    /* manual dispatch, no automatic sub-test numbering */
    test_new_file_no_creat();
    test_noatime_unprivileged();
}

static struct tst_test test = {
    /* .test_all used instead of .test + .tcnt */
    .test_all = run,
};
```

ALWAYS define a single `struct tcase` array and use `.test` + `.tcnt` in
`struct tst_test`. The test function receives the index `n` and dispatches
through the array:

CORRECT -- one struct tcase array, one generic handler, .test + .tcnt:

```c
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
    /* framework iterates tcases[], prints "1.", "2.", ... automatically */
    .tcnt = ARRAY_SIZE(tcases),
    .test = verify_open,
};
```

Key rules:

- `.test` (takes `unsigned int n`) is used when there are multiple test cases.
- `.test_all` (takes no arguments) is used only when there is a single test case.
- NEVER use separate per-case functions called from `run()`.
- NEVER use `.test_all` when multiple cases exist.

#### Modifying tcase Items in setup()

NEVER use `struct tcase` array indexes to modify items in `setup()` -- this is
error-prone and breaks silently when entries are reordered. Instead, store a
pointer to a static variable in the struct and modify the static variable:

WRONG -- array index used to modify tcase in setup:

```c
static struct tcase {
    int val;
    int exp_err;
} tcases[] = {
    {-1, EINVAL},
    {0, ENOENT},
};

static void setup(void)
{
    /* array index breaks when entries are reordered */
    tcases[1].val = SAFE_OPEN("testfile", O_RDWR);
}
```

CORRECT -- modify via static variable, not array index:

```c
static int fd = -1;

static struct tcase {
    int *val;
    int exp_err;
} tcases[] = {
    {.exp_err = EINVAL},
    {.val = &fd, .exp_err = ENOENT},
};

static void setup(void)
{
    /* modify via static variable, not array index */
    fd = SAFE_OPEN("testfile", O_RDWR);
}
```

#### Stringification Macros for Test Cases

When the test case description repeats an enum or macro name, use a
stringification macro to avoid duplication (DRY):

WRONG -- description duplicates the macro name:

```c
static struct tcase {
    const char *desc;
    int exp_err;
} tcases[] = {
    {"EINVAL", EINVAL},
    {"ENOENT", ENOENT},
    {"EACCES", EACCES},
};
```

CORRECT -- stringification macro eliminates duplication:

```c
#define TC(x) {.desc = #x, .exp_err = x}

static struct tcase {
    const char *desc;
    int exp_err;
} tcases[] = {
    TC(EINVAL),
    TC(ENOENT),
    TC(EACCES),
};
```

### Path Buffers

NEVER define a custom buffer size for path strings:

WRONG -- custom buffer size for paths:

```c
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

CORRECT -- use PATH_MAX for path buffers:

```c
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
there -- not `PATH_MAX`.

### Kernel Config Dependencies

NEVER manually check for kernel config features by handling ioctl/syscall
errors at runtime when `.needs_kconfigs` can be used:

WRONG -- manually handling missing kernel config:

```c
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

CORRECT -- framework checks kernel config before running the test:

```c
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

WRONG -- plain syscall() requires manual ENOSYS check:

```c
syscall(__NR_listns, &req, NULL, 0, 0);
if (errno == ENOSYS)
        tst_brk(TCONF, "listns() not supported");
```

ALWAYS use `tst_syscall` instead:

CORRECT -- tst_syscall() handles ENOSYS automatically:

```c
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

WRONG -- child signals before setup is complete:

```c
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

CORRECT -- parent triggers child, waits for setup, then releases:

```c
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
```

### Child Process Exit

NEVER let a child process return or fall through without an explicit exit:

WRONG -- missing exit, child may fall through into parent code:

```c
child_pid = SAFE_FORK();
if (!child_pid) {
    /* child work */
}
/* parent code */
```

ALWAYS call `exit(0)` at the end of the child block when parent code
follows it.

MUST NOT use `_exit()` -- use `exit(0)` instead so the LTP
framework can propagate test results from child to parent.

Example:

CORRECT -- child exits explicitly before parent code:

```c
child_pid = SAFE_FORK();
if (!child_pid) {
    /* child work */
    exit(0);
}
/* parent code */
```

A child that returns from the test function (`.test` / `.test_all`) back
to the LTP library is exited by the library with `exit(0)`. When the child
code ends the test function, a trailing `exit(0)` is redundant and SHOULD
NOT be added. Reviewers SHOULD flag it.

WRONG -- redundant `exit(0)` at the end of the test function:

```c
static void run(void)
{
    if (SAFE_FORK())
        return;

    TST_EXP_PASS(syscall_under_test());
    exit(0);
}
```

CORRECT -- child returns to the library, which exits it:

```c
static void run(void)
{
    if (SAFE_FORK())
        return;

    TST_EXP_PASS(syscall_under_test());
}
```

This applies ONLY to the test function itself. A child forked in
`setup()`, in a helper function, or followed by more code in the test
function MUST still call `exit(0)` explicitly.

### Child Process Reaping

NEVER add `SAFE_WAITPID()` solely to reap a child before the test exits.
The LTP framework calls `tst_reap_children()` on exit and reaps leftover
children automatically. `SAFE_WAITPID()` remains appropriate when the
parent must observe the child's exit status or serialize on its
termination -- the rule below targets the redundant case only:

WRONG -- explicit waitpid is redundant:

```c
static void run(void)
{
    pid_t child_pid;

    child_pid = SAFE_FORK();
    if (!child_pid) {
        exit(0);
    }

    SAFE_WAITPID(child_pid, NULL, 0);
}
```

ALWAYS rely on the framework to reap children:

CORRECT -- let the framework reap the child:

```c
static void run(void)
{
    if (!SAFE_FORK()) {
        /* child work */
    }
}
```

### Static Variable Initialization

Static variables whose value is fully derived from other statics already set
in `setup()` MUST be initialized in `setup()` as well, NOT inside `run()`.
Recomputing a constant derived value on every iteration is redundant and
misleading -- it implies the value may change across iterations when it does not.

WRONG -- derived value recomputed on every call to `run()`:

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

CORRECT -- derived value computed once in `setup()`:

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

### Save/Restore for sysctl and proc values

NEVER manually save and restore `/proc` or `/sys` values in
setup/cleanup. ALWAYS use `.save_restore` in `struct tst_test`:

WRONG -- manual save/restore of proc/sys values:

```c
static char old_val[64];

static void setup(void)
{
    SAFE_FILE_SCANF("/proc/sys/kernel/core_pattern", "%s", old_val);
    SAFE_FILE_PRINTF("/proc/sys/kernel/core_pattern", "./core");
}

static void cleanup(void)
{
    SAFE_FILE_PRINTF("/proc/sys/kernel/core_pattern", "%s", old_val);
}
```

CORRECT -- framework handles save/restore automatically:

```c
static struct tst_test test = {
    .test_all = run,
    .save_restore = (const struct tst_path_val[]) {
        {"/proc/sys/kernel/core_pattern", "./core", TST_SR_TCONF},
        {},
    },
};
```

### TCONF for unsupported features

MUST return `TCONF` (not `TFAIL`) when a syscall or feature is
unavailable at runtime:

WRONG -- TFAIL for unsupported feature:

```c
TEST(syscall(__NR_foo, args));
if (TST_RET == -1 && TST_ERR == ENOSYS)
    tst_res(TFAIL, "foo() not supported");
```

CORRECT -- TCONF for unsupported feature:

```c
TEST(syscall(__NR_foo, args));
if (TST_RET == -1 && TST_ERR == ENOSYS)
    tst_brk(TCONF, "foo() not supported");
```

### TST_TEST_TCONF Placement

`TST_TEST_TCONF(message)` provides an alternative `struct tst_test` that makes
the test immediately exit with TCONF. Because it is a struct definition, strict
placement rules apply:

- MUST appear at **file scope** only -- never inside a function body
- MUST be inside an `#else` branch of a preprocessor conditional, immediately
  followed by `#endif`
- MUST use a **literal string**, not a macro constant (e.g. `NUMA_ERROR_MSG`)
- MUST be the **only** `struct tst_test` in its compilation path -- the normal
  `struct tst_test test = {...}` goes in the `#ifdef` branch,
  `TST_TEST_TCONF` goes in the `#else` branch (mutual exclusion is enforced
  by the compiler)

WRONG -- TST_TEST_TCONF inside a function body:

```c
#ifndef HAVE_LIBCAP
static void run(void)
{
    TST_TEST_TCONF("System is missing libcap");
}
#endif
```

WRONG -- macro constant instead of literal string:

```c
#else
TST_TEST_TCONF(NUMA_ERROR_MSG);
#endif
```

CORRECT -- file scope, literal string, in `#else` before `#endif`:

```c
#ifdef HAVE_LIBCAP

static void run(void)
{
    /* test logic */
}

static struct tst_test test = { .test_all = run };

#else
TST_TEST_TCONF("test requires libcap development packages");
#endif
```

### Helper Binaries (`TST_NO_DEFAULT_MAIN`)

Some `.c` files under `testcases/` are not standalone tests -- they are
helper binaries spawned by tests. They have their own `main()` and are
NOT listed in any `runtest/` file.

Helper binaries MUST use the new API but MUST NOT use `struct tst_test`.
Instead, define `TST_NO_DEFAULT_MAIN` before including `tst_test.h`.

WRONG -- helper using old API:

```c
#include "test.h"

char *TCID = "myhelper";
int TST_TOTAL = 1;

int main(int argc, char *argv[])
{
    tst_parse_opts(argc, argv, NULL, NULL);
    tst_resm(TINFO, "helper running");
    tst_exit();
}
```

CORRECT -- helper using new API with TST_NO_DEFAULT_MAIN:

```c
#define TST_NO_DEFAULT_MAIN
#include "tst_test.h"

int main(int argc, char *argv[])
{
    tst_res(TINFO, "helper running");
}
```
