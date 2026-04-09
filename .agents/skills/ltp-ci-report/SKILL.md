---
name: ltp-ci-report
description: LTP CI Review Report — format review output for GitHub Actions step summary
---

<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# LTP CI Report Protocol

You are an agent that formats `/ltp-review` output as a GitHub Actions step
summary using GitHub-flavored markdown.

The user will invoke this skill immediately after `/ltp-review` has run on
a patch. This skill does NOT perform the review itself — it only reformats
the findings.

## Phase 1: Gather Context

### Step 1.1: Verify patches are applied

Run `git rev-list --count master..HEAD`. If the count is 0, or the current
branch IS master, **stop immediately** and tell the user:

> No patches found. Please checkout a branch with patches applied on top of
> master before running this skill.

Do NOT proceed.

### Step 1.2: Get the review findings

Read the output of the most recent `/ltp-review` run from the current
conversation context. If no review is available, invoke `/ltp-review` first
and wait for its output before continuing.

### Step 1.3: Get the email reply

Read the output of the most recent `/ltp-email-reply` run from the current
conversation context. If no email reply is available, invoke
`/ltp-email-reply` and wait for its output before continuing.

### Step 1.4: Get patch metadata

Collect the following from git:

- Branch name: `git rev-parse --abbrev-ref HEAD`
- Commit count: `git rev-list --count master..HEAD`
- For each commit: hash (short), subject, author, date

If the branch name matches `review/series-<ID>`, extract the series ID
and build the Patchwork link:
`https://patchwork.ozlabs.org/project/ltp/list/?series=<ID>`

---

## Phase 2: Format the Report

Generate a GitHub-flavored markdown report. Keep the summary scannable by
using structured tables.

### Structure

````markdown
# LTP Patch Review

| Field         | Value                                                    |
| ------------- | -------------------------------------------------------- |
| **Patchwork** | [series <ID>](patchwork-link) (omit row if no series ID) |
| **Branch**    | `<branch>`                                               |
| **Commits**   | <count>                                                  |
| **Verdict**   | **Approved** / **Needs revision** / **Needs discussion** |

## Commit Messages

| Status          | Hash           | Subject   | Author   |
| --------------- | -------------- | --------- | -------- |
| <verdict-emoji> | `<short-hash>` | <subject> | <author> |

<if any commit message issues>

- **<rule-id>** `<hash>` — <issue>

</if>

## Code Review

| Category             | Status      |
| -------------------- | ----------- |
| Ground rules (G1–G8) | <pass/fail> |
| <C/S/P test rules>   | <pass/fail> |

<if issues found>

### Issues

| Rule          | Location        | Description   |
| ------------- | --------------- | ------------- |
| **<rule-id>** | `<file>:<line>` | <description> |

<for each issue with code context>

#### <rule-id>: <short description>

```c
<relevant code snippet from the diff>
```

<explanation of the issue and what to fix>

</for>
````

</if>

<if pre-existing issues>

## Pre-existing (informational)

These are not caused by the patch and do not affect the verdict.

| Location        | Description   |
| --------------- | ------------- |
| `<file>:<line>` | <description> |

</if>

## Email Reply

```
<output from /ltp-email-reply>
```

```

### Verdict Emoji Mapping

- **Approved**: use the text `Approved`
- **Needs revision**: use the text `Needs revision`
- **Needs discussion**: use the text `Needs discussion`
- Commit message pass: use `pass`
- Commit message fail: use `FAIL`

### Rules

- Use GitHub-flavored markdown only (rendered in Actions step summary).
- Use tables for structured data — they render well in step summaries.
- Do NOT use `<details>` / `<summary>` collapsible sections — always show
  all information directly.
- Include short code snippets from the diff when flagging issues — show the
  problematic lines so the reader does not need to look up the file.
- Do NOT include the full diff or full file contents.
- Do NOT use emoji.
- Keep descriptions terse — one sentence per issue.

---

## Phase 3: Output

Print the markdown report as raw text, ready to be appended to
`$GITHUB_STEP_SUMMARY`. Do not wrap it in a code block — output the
markdown directly.
```
