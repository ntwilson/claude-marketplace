---
name: summarize-review
description: Use this skill when the user asks to "summarize a PR", "summarize review", "give me a layered summary", "drill-down review", or wants a high-level overview of code changes with an indexed report they can then ask follow-up questions about. Writes a full indexed review report to a markdown file, covering summary, architecture, suspicious items, and a file-by-file breakdown, then answers follow-up questions referenced by index number.
---

# Summarize Review Assistant

This skill produces a complete code-review report and writes it to a markdown file. Every suspicious item and every file in the report is assigned a sequential index number (`#1`, `#2`, …). After writing the file, the skill stands ready to answer follow-up questions that refer to those index numbers (e.g. "tell me more about #19" refers to whatever item was indexed `#19` in the report).

## Purpose

Produce a single written report covering:

1. **Overview** — summary and architecture in one place
2. **Suspicious items / noteworthy concerns** — language-specific concerns and anything noteworthy, each indexed
3. **File-by-file breakdown** — per-file summaries with inline review comments, each indexed

## Input Formats

1. **PR number only**: `123`
2. **PR number with alternative base**: `123` against `develop`
3. **Base and head branches**: `main` and `feature-branch`

## Review Process

### Step 1: Fetch Change Information

**For PR number:**
```bash
gh pr view <PR_NUMBER> --json number,title,body,baseRefName,headRefName,files
gh pr diff <PR_NUMBER>
pwsh -File scripts/get-comments.ps1 -url "repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments"
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews --paginate
```

The `get-comments.ps1` script fetches inline diff comments and outputs each as `FILE: <path> | LINE: <line> | USER: <username>` followed by `BODY: <text>`, one per block separated by `---`. The final `api` call returns top-level review submissions (each has `body`, `user.login`, `state`, `submitted_at`). Fetch both and retain them for use in the file-by-file breakdown (Section 3).

Resolve `{owner}` and `{repo}` from `gh repo view --json owner,name` or from the PR URL.

**For branches:**
```bash
git diff <BASE_BRANCH>...<HEAD_BRANCH>
git diff <BASE_BRANCH>...<HEAD_BRANCH> --name-status
```

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
- Summarize each changed file and its key functions
- **For PR reviews:** Group inline review comments by file and by function/line range, so each file and function knows how many comments it has and what they say

This pre-analysis ensures the report is complete and coherent when written.

### Step 6: Write the Report

Write the entire report to a markdown file in one pass. Do not pause between sections. Write it under the repo's `.claude/` directory: name the file `<repo-root>/.claude/pr-<PR_NUMBER>-review.md` for a PR, or `<repo-root>/.claude/review-<BASE>-<HEAD>.md` for a branch comparison. The `Write` tool creates the `.claude/` directory if it does not already exist. After writing it, tell the user the path and invite follow-up questions by index number (see "Answering Follow-up Questions").

**Index numbering:** Maintain a single sequential counter across the whole report. Assign the next index number to each suspicious item (Section 2) and then to each file (Section 3), continuing the same sequence. Each index appears once and unambiguously identifies one item. Render every index as a bold `#N` at the start of the item's heading so it is easy to scan and reference.

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
### #N — ⚠️ **[Category]** — `path/to/file.ext` (`functionName` or line reference)

\`\`\`[language]
[relevant code excerpt]
\`\`\`

[Explanation: what is suspicious or problematic and why it matters]
```

If no suspicious items are found, write a short note saying so under the section heading.

---

## Section 3: File-by-File Breakdown

Walk through each changed file in dependency order (from Step 4), moving up from the bottom of the call graph. Assign each file the next index number. For each file, provide a concise summary of what changed and why it matters in the context of the overall PR.

### File summary format:

```markdown
### #N — `path/to/file.ext` _(M review comments)_

[what changed in this file, what role it plays, and any notable details]
```

Then display all inline review comments for the file, grouped by reviewer. Format each comment as:

```markdown
**@username** on [function or type]:
> [comment body]
```

---

## Answering Follow-up Questions

After the report is written, the user may ask questions that reference index numbers (e.g. "why is #7 a problem?", "explain #19", "is #3 actually a bug?"). Resolve each `#N` to the item that was assigned that index in the report and answer with the full context you gathered during pre-analysis. The user may reference multiple indexes in one question. Answer directly; do not re-emit the whole report.

---

## Additional Resources

### Reference Files

- **`references/review-focus-patterns.md`** — Detailed patterns for Section 2: Suspicious Items and Noteworthy Concerns
- **`references/dependency-analysis-patterns.md`** — Strategies for determining dependency order across languages

### Helper Scripts

- **`scripts/fetch-pr-info.ps1`** — PowerShell script to fetch PR information via `gh` CLI
- **`scripts/get-comments.ps1`** — Fetches inline diff comments from the GitHub API and formats them as readable `FILE | LINE | USER` / `BODY` blocks. Always invoke with `pwsh -File "<absolute-path-to-script>"` (not just `pwsh "<path>"`) so that backslashes in the path are not interpreted as escape characters on Windows. Example: `pwsh -File "C:\path\to\get-comments.ps1" -url "repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments"`

---

## Workflow Summary

1. **Parse input** → Determine if PR number, PR + base, or branches
2. **Fetch changes** → Use `gh pr diff` or `git diff`
3. **Read files** → Load changed files for full context
4. **Pre-analyze** → Prepare all sections before producing output
5. **Write report** → Write the full report to a markdown file under the repo's `.claude/` directory in one pass, with a single sequential index counter spanning Section 2 (suspicious items) then Section 3 (files):
   - **Section 1** → Overview (summary + architecture), not indexed
   - **Section 2** → Suspicious items and noteworthy concerns, each indexed `#N`
   - **Section 3** → File-by-file breakdown **in dependency order** (from Step 4), each file indexed `#N`
6. **Report the path** → Tell the user where the file was written and invite follow-up questions by index number
7. **Answer follow-ups** → Resolve `#N` references to the corresponding indexed items
