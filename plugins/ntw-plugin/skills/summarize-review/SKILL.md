---
name: summarize-review
description: Use this skill when the user asks to "summarize a PR", "summarize review", "give me a layered summary", "drill-down review", or wants a high-level overview of code changes with an indexed report they can then ask follow-up questions about. Writes a full indexed review report to a markdown file, covering summary, architecture, suspicious items, and a file-by-file breakdown, with every item deep-linked to its exact line on the PR, then answers follow-up questions referenced by index number and posts inline comments or suggested code changes back to the PR.
---

# Summarize Review Assistant

This skill produces a complete code-review report and writes it to a markdown file. Every suspicious item and every file in the report is assigned a sequential index number (`#1`, `#2`, …) and deep-linked to its exact line on the PR. After writing the file, the skill stands ready to answer follow-up questions that refer to those index numbers (e.g. "tell me more about #19" refers to whatever item was indexed `#19` in the report), and to post inline comments or suggested code changes back to the PR against any index.

## Purpose

Produce a single written report covering:

1. **Overview** — summary and architecture in one place
2. **Suspicious items / noteworthy concerns** — language-specific concerns and anything noteworthy, each indexed
3. **File-by-file breakdown** — per-file summaries with inline review comments, each indexed

## Input Formats

1. **PR number only**: `123`
2. **PR number with alternative base**: `123` against `develop`
3. **Base and head branches**: `main` and `feature-branch`
4. **No argument**: assume the current branch has an open PR and review it. Resolve it with `gh pr view` (no argument) and proceed as if that number had been typed — see **section 0** of `../../shared/references/pr-interaction.md` for resolution and the fallbacks when there is no open PR. State which PR was resolved before going further.

## Review Process

### Step 0: Resolve the Target

If the user gave no PR number and no branch names, resolve the current branch's open PR per **section 0** of `../../shared/references/pr-interaction.md`, then continue as a PR review.

### Step 1: Fetch Change Information

**For PR number:**
```bash
gh pr view <PR_NUMBER> --json number,title,body,baseRefName,headRefName,headRefOid,files
gh pr diff <PR_NUMBER>
pwsh -File ../../shared/scripts/get-comments.ps1 -url "repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments"
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews --paginate
```

The `get-comments.ps1` script fetches inline diff comments and outputs each as `FILE: <path> | LINE: <line> | USER: <username>` followed by `BODY: <text>`, one per block separated by `---`. The final `api` call returns top-level review submissions (each has `body`, `user.login`, `state`, `submitted_at`). Fetch both and retain them for use in the file-by-file breakdown (Section 3).

Resolve `{owner}` and `{repo}` from `gh repo view --json owner,name` or from the PR URL.

**Retain `headRefOid`** — the head commit SHA. Report links and any posted comments are anchored to it, so both point at the code that was actually reviewed.

**For branches:**
```bash
git diff <BASE_BRANCH>...<HEAD_BRANCH>
git diff <BASE_BRANCH>...<HEAD_BRANCH> --name-status
```

### Step 1b: Compute Diff Anchors and Line Numbers (PR reviews only)

Follow **section 1** of `../../shared/references/pr-interaction.md` to compute the `#diff-<hash>` anchor for every changed file in one call, and **section 2** for deriving line numbers out of the hunk headers.

Record, for every item that will get an index in the report:

- **Suspicious items (Section 2)** — the `path`, the `anchorLine` of the flagged code, and its `startLine`–`endLine` span.
- **Files (Section 3)** — the `path` and the `anchorLine` of the file's first change.
- **Sub-indexed declarations (`#N.M`)** — the `path` and the declaration's `startLine`–`endLine` span, with `anchorLine` at its first changed line.

These line numbers are what make the report's links land correctly and what any posted comment anchors to. Skip this step for branch comparisons; there is no PR to link into.

### Step 2: Ensure Correct Branch

Check if head branch is checked out:
```bash
git branch --show-current
```

If not on head branch and files need to be read for context, check out the branch or proceed with available information.

### Step 3: Read Changed Files

For each changed file, read the current version using the Read tool to understand full context — not just what changed, but how the changed code fits into the surrounding codebase.

### Step 4: Determine Dependency Order

Use dependency order throughout:

**For F# projects:** Read the `.fsproj` file; files are already in dependency order.

**For other languages:** Build a dependency graph from imports, type definitions, and call graphs; use topological order (callees before callers).

**Exception:** If the PR body specifies a review order, use that order.

### Step 5: Pre-analyze Everything

Before producing any output, fully analyze the changes across all files to prepare all sections. Specifically:

- Understand the overall purpose and scope
- Identify architectural patterns in new/changed code
- Collect all language-specific suspicious items and any other noteworthy concerns
- Summarize each changed file, and separately summarize each added/edited leaf declaration (type/class/function/method) within it for the sub-indexed breakdown in Section 3
- **For PR reviews:** Group inline review comments by file and by function/line range, so each file and function knows how many comments it has and what they say

This pre-analysis ensures the report is complete and coherent when written.

### Step 6: Write the Report

Write the entire report to a markdown file in one pass. Do not pause between sections. Write it under the repo's `.claude/` directory: name the file `<repo-root>/.claude/pr-<PR_NUMBER>-review.md` for a PR, or `<repo-root>/.claude/review-<BASE>-<HEAD>.md` for a branch comparison. The `Write` tool creates the `.claude/` directory if it does not already exist. After writing it, tell the user the path and invite follow-up questions by index number (see "Answering Follow-up Questions").

**Index numbering:** Maintain a single sequential counter across the whole report. Assign the next index number to each suspicious item (Section 2) and then to each file (Section 3), continuing the same sequence. Each index appears once and unambiguously identifies one item. Render every index as a bold `#N` at the start of the item's heading so it is easy to scan and reference. In Section 3, each added/edited leaf declaration within a file gets a **sub-index** derived from its file's index (`#N.1`, `#N.2`, …); these do not consume top-level counter numbers.

The report has three sections in this order.

---

## Section 1: Overview

1. **Summary** — 1–2 paragraphs describing the entire changeset's purpose, scope, and key impact
2. **Architecture** — 1-3 paragraphs or a short bulleted list describing new/changed structure; omit (and say so) if the changes are purely behavioral with no structural changes. Include a visualization of the call graph for the changed code, showing how functions relate to each other across files, and describe any new data structures introduced by the changes.

This section is not indexed.

---

## Section 2: Suspicious Items and Noteworthy Concerns

List code smells and any other suspicious or problematic code found in the changed code. Assign each item the next index number.

### What to Flag

**Anything that _you_ find suspicious or noteworthy according to your judgment**

**Language-specific items (always flag):**

**F# files (`.fs`):**
- `let mutable` declarations
- Mutable collection operations: `.Add(...)`, `.Remove(...)`, `.Clear()`, `.Insert(...)`, `dict.[key] <- value`, `.Push(...)`, `.Pop()`, `.Enqueue(...)`, `.Dequeue()`
- Functions that may throw on invalid input:
  - `Array.head`, `Array.tail`, `Array.last`, `Array.reduce`, `Array.item`, `Array.exactlyOne`
  - `List.head`, `List.tail`, `List.last`, `List.reduce`, `List.item`, `List.exactlyOne`
  - `Seq.head`, `Seq.last`, `Seq.reduce`, `Seq.item`, `Seq.exactlyOne`
  - `Map.find`, `Map.item`, `Option.get`, `Result.get`, `Option.unless`, `Result.expect`
  - `dict.[key]` indexer access
  - `int`/`float` conversions that throw on failure
- Non-deterministic operations outside `io { }`: `DateTime.Now`, `DateTime.UtcNow`, `DateTimeOffset.Now`, `DateTimeOffset.UtcNow`, `System.Random`, `Guid.NewGuid()`, `Environment.GetEnvironmentVariable`, `Stopwatch`
- Side effects outside `io { }`: `System.IO` operations, `Console.WriteLine`, `printfn` (outside scripts/entry points), network calls (`HttpClient`, `WebRequest`), database access, `System.Diagnostics.Process`

**PureScript files (`.purs`):**
- Any function with `unsafe` in the name: `unsafeCoerce`, `unsafePartial`, `unsafePerformEffect`, `unsafeThrow`, `unsafeFreeze`, `unsafeThaw`, etc.

**General items to flag (use judgment):**
- Potential bugs or logic errors
- Missing or swallowed error handling
- Security concerns (SQL injection, command injection, hardcoded credentials, missing auth checks, data exposure)
- Breaking changes (signature changes, removed fields, behavioral changes)
- Performance issues (N+1 queries, unbounded collections, resource leaks, blocking on async)
- Concurrency issues (race conditions, shared mutable state, deadlock potential)
- Complex conditionals or deep nesting that is hard to follow
- Off-by-one errors, floating-point equality comparisons, timezone issues
- Missing test coverage for new or complex logic

### Format for Each Item

```markdown
### #N — ⚠️ **[Category]** — [`path/to/file.ext:<anchorLine>`](https://github.com/<owner>/<repo>/pull/<N>/files#diff-<hash>R<anchorLine>) (`functionName`)

\`\`\`[language]
[relevant code excerpt]
\`\`\`

[Explanation: what is suspicious or problematic and why it matters]
```

The file reference links to the exact line of the flagged code — see **section 3** of `../../shared/references/pr-interaction.md`. For branch comparisons, leave it as plain `path/to/file.ext:<line>` text.

If no suspicious items are found, write a short note saying so under the section heading.

---

## Section 3: File-by-File Breakdown

Walk through each changed file in dependency order (from Step 4), moving up from the bottom of the call graph. Assign each file the next index number. For each file, provide a concise summary of what changed and why it matters in the context of the overall PR.

After the file summary, add a 1–2 sentence summary of each type/class/function/method that was added or edited in that file, each with a **sub-index** derived from the file's index (e.g. if the file is `#12`, its edited members are `#12.1`, `#12.2`, `#12.3`, …, numbered in the order they appear in the file). Only the changed members get an entry — skip members the PR didn't touch.

**Work at the lowest level only.** Summarize the innermost (leaf) declarations that were changed, not their enclosing scopes. For example, if a changed file contains a module that adds a new class with three new methods, add sub-indexed summaries for the three methods only — not for the module or the class. If a leaf declaration has no meaningful enclosing scope (e.g. a top-level function), summarize the function itself.

### File summary format:

```markdown
### #N — [`path/to/file.ext:<anchorLine>`](https://github.com/<owner>/<repo>/pull/<N>/files#diff-<hash>R<anchorLine>) _(M review comments)_

[what changed in this file, what role it plays, and any notable details]

- **#N.1** — [`memberName`](https://github.com/<owner>/<repo>/pull/<N>/files#diff-<hash>R<memberAnchorLine>) — [1–2 sentence summary of what this member does / how it changed]
- **#N.2** — [`memberName`](…R<memberAnchorLine>) — [1–2 sentence summary]
- …
```

Both the file heading and each sub-indexed member link to their own exact line, so a member can be opened directly rather than by scrolling the file. All members share the file's `#diff-<hash>`; only the `R<line>` differs. For branch comparisons, drop the links and leave the paths and member names as plain text.

If a file has no added/edited leaf declarations (e.g. only config or whitespace changes), omit the sub-index list and note that briefly.

Then display all inline review comments for the file, grouped by reviewer. Format each comment as:

```markdown
**@username** on [function or type]:
> [comment body]
```

---

## Answering Follow-up Questions

After the report is written, the user may ask questions that reference index numbers (e.g. "why is #7 a problem?", "explain #19", "is #3 actually a bug?"). References may be top-level (`#N`) or sub-indexes for a specific declaration (`#N.M`, e.g. "tell me more about #12.2"). Resolve each reference to the item that was assigned that index in the report and answer with the full context you gathered during pre-analysis. The user may reference multiple indexes in one question. Answer directly; do not re-emit the whole report.

---

## Posting Comments and Suggestions Back to the PR

Follow `../../shared/references/pr-interaction.md` — **section 4** (comments), **section 5** (suggested changes and the approval preview), **section 6** (submitting), and **section 7** (failure modes). That document is the authority on the queue format, the two-gate rule, and the submit checklist.

For this skill, an index resolves to a comment target as follows:

- **`#N` on a suspicious item (Section 2)** — the flagged code's `anchorLine`, or its `startLine`–`endLine` span for a comment covering the whole construct. This is the most common case: the item is already a concern, so commenting on it is the natural next step.
- **`#N.M` on a declaration (Section 3)** — that declaration's line range. Prefer this over the bare file index; it is specific enough to comment on directly.
- **`#N` on a file (Section 3)** — a whole file has no single meaningful line. Ask which declaration or line the user means, or use the file's `anchorLine` if they say "anywhere in the file is fine". Do not silently pick a line.

Usage looks like:

> "#7 comment: this will throw if the list is empty"
> "#12.2 suggest: use tryHead and handle None instead"

A comment queues immediately; a suggestion is shown for approval first and queues only once the user says so.

---

## Additional Resources

Paths are relative to this skill's directory. `../../shared/` is the plugin-level shared directory, used by both review skills in this plugin.

### Shared — `../../shared/`

- **`../../shared/references/pr-interaction.md`** — the authority on deep links, line-number tracking, queueing comments, writing and previewing suggested changes, submitting, and failure modes. Sections are referenced by number from Step 1b, Sections 2–3, and "Posting Comments and Suggestions Back to the PR" above.
- **`../../shared/references/dependency-analysis-patterns.md`** — strategies for determining dependency order across languages
- **`../../shared/scripts/`** — `fetch-pr-info.ps1`, `get-comments.ps1`, `diff-anchors.ps1`, `show-lines.ps1`, `submit-review.ps1`. All require PowerShell Core; see section 8 of `pr-interaction.md` for what each does. Always invoke with `pwsh -File "<absolute-path-to-script>"` (not just `pwsh "<path>"`) so that backslashes in the path are not interpreted as escape characters on Windows.

### Skill-specific — `references/`

- **`references/review-focus-patterns.md`** — detailed patterns for Section 2: Suspicious Items and Noteworthy Concerns. This copy is tuned for this skill and intentionally differs from `detailed-review`'s.

---

## Workflow Summary

1. **Parse input** → Determine if PR number, PR + base, or branches; **with no input, resolve the current branch's open PR** and treat it as a PR review
2. **Fetch changes** → Use `gh pr diff` or `git diff`; retain `headRefOid`
3. **Anchor** → Compute the `#diff-<hash>` anchor per changed file and derive line numbers for every item that will be indexed
4. **Read files** → Load changed files for full context
5. **Pre-analyze** → Prepare all sections before producing output
6. **Write report** → Write the full report to a markdown file under the repo's `.claude/` directory in one pass, with a single sequential index counter spanning Section 2 (suspicious items) then Section 3 (files):
   - **Section 1** → Overview (summary + architecture), not indexed
   - **Section 2** → Suspicious items and noteworthy concerns, each indexed `#N` and linked to its exact line
   - **Section 3** → File-by-file breakdown **in dependency order** (from Step 4), each file indexed `#N` and linked, with each added/edited leaf declaration sub-indexed `#N.M`, linked to its own line, and given a 1–2 sentence summary
7. **Report the path** → Tell the user where the file was written and invite follow-up questions by index number, or comments and suggestions by index
8. **Answer follow-ups** → Resolve `#N` references to the corresponding indexed items
9. **Queue comments** → `#N comment: …` appends to `.claude/pr-<N>-comments.json`; nothing is sent yet
10. **Write suggestions** → `#N suggest: …` reads the exact lines at the head commit and writes the replacement code as an applicable ` ```suggestion ` block, then **shows it and waits** — it enters the queue only once the user approves
11. **Submit on request** → dry-run, re-check the head SHA, confirm no suggestion is still pending, then post all queued comments as one review
