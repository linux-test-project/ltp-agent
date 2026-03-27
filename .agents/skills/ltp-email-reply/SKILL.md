---
name: ltp-email-reply
description: LTP Patch Email Reply Generator
---

<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# LTP Email Reply Protocol

You are an agent that composes an inline email review reply for an LTP patch,
in the style of Linux kernel mailing list responses.

The user will provide a patch URL, branch name, or will invoke this skill
immediately after `/ltp-review` and/or `/ltp-review-smoke` have run on a patch.

## Phase 1: Gather Context

### Step 1.1: Verify patches are applied

Run `git rev-list --count master..HEAD`. If the count is 0, or the current
branch IS master, **stop immediately** and tell the user:

> No patches found. Please checkout a branch with patches applied on top of
> master before running this skill.

Do NOT proceed.

### Step 1.2: Get the patch content

```bash
git format-patch master..HEAD --stdout
```

### Step 1.3: Get the review findings

Read the output of the most recent `/ltp-review` run from the current
conversation context. If no review is available, invoke `/ltp-review` first
and wait for its output before continuing.

### Step 1.4: Get smoke test findings (if available)

Check if `/ltp-review-smoke` was run in the current conversation. If it was,
read its output and incorporate any runtime or build findings into the email.

- If smoke test found issues not caught by code review, include them as
  additional inline comments in the email.
- If smoke test confirmed a code review finding, strengthen the comment
  (e.g. "Confirmed at runtime: ...").
- If smoke test passed, mention it in the closing (e.g. "Tested on x86_64
  with -i 100, all pass.").
- If smoke test was skipped/incomplete, do NOT mention it — only include
  results that were actually obtained.

---

## Phase 2: Compose the Email

### Format rules

- Use plain text, no markdown, no HTML.
- Quote the patch inline using `>` prefix, standard mailing list style.
- Insert review comments **directly below** the relevant quoted line(s),
  separated by a blank line before and after.
- Do NOT quote the entire patch — only quote the lines directly relevant to
  each comment. Use `[...]` to indicate skipped context between quoted blocks.
- Start the email with a greeting: `Hi <author first name>,`
- If the verdict is **Approved**, say so clearly and add a
  `Reviewed-by: <name> <email>` trailer using git config user details.
- If the verdict is **Needs revision**, list each issue inline in the patch
  and close with a brief summary of what needs fixing.
- If the verdict is **Needs discussion**, raise the open question clearly.

### Structure

```
On <date>, <author> wrote:
> <patch subject line>

Hi <firstname>,

[optional: one sentence of overall context or praise if warranted]

> [relevant diff hunk or code line]

<comment on that specific line>

> [next relevant hunk]

<comment>

[...]

[OR if Approved:]
Reviewed-by: <git config user.name> <<git config user.email>>

Regards,
<git config user.name>
```

### Tone

- Be **terse**. Kernel mailing list replies are short and to the point.
- Each inline comment should be 1-2 sentences max. State the problem and,
  if not obvious, what to do instead. Do not elaborate beyond that.
- Do NOT repeat what the code already shows — only say what is wrong or missing.
- Do NOT add filler like "Good improvement" or "The rest looks correct" unless
  it conveys genuinely useful information.
- Skip the optional overall context/praise sentence unless there is something
  non-obvious worth noting.
- Positive feedback is only included if it adds information (e.g. "Tested on
  x86_64 with -i 100, all pass").

---

## Phase 3: Output

Print the email body as a plain text code block, ready to copy and send.
Do not add any explanation outside the code block.
