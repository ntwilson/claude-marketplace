---
name: summarize-review
description: Use this skill when the user asks to "summarize a PR", "summarize review", "give me a layered summary", "drill-down review", or wants a high-level overview of code changes that progressively adds more detail on demand. Provides a multi-section, interactive review that covers summary, architecture, data flow, file-by-file breakdown, error analysis, and code smells.
---

# Summarize Review Assistant

This skill provides a multi-section, layered code review that starts with high-level summaries and progressively adds detail on demand. Each section pauses and waits for the user to request more detail or move on.

## Purpose

Walk through a review in four focused sections — each interactive and expandable — rather than element by element:

1. **Overview** — summary, architecture, and data flow all in one place; drill into any of the three on demand
2. **Architecture breakdown** — describe new types, per-file summaries, with optional per-function detail
3. **Code smells / suspicious items** — language-specific concerns and anything noteworthy

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

The `get-comments.ps1` script fetches inline diff comments and outputs each as `FILE: <path> | LINE: <line> | USER: <username>` followed by `BODY: <text>`, one per block separated by `---`. The final `api` call returns top-level review submissions (each has `body`, `user.login`, `state`, `submitted_at`). Fetch both and retain them for use in Section 2.

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
- Trace data flow through the changes
- Summarize each changed file and its key functions
- **For PR reviews:** Group inline review comments by file and by function/line range, so each file and function knows how many comments it has and what they say
- Identify all error origins and propagation paths
- Collect all language-specific suspicious items and any other noteworthy concerns

This pre-analysis ensures each section is complete and coherent when presented.

---

## Section 1: Overview

Present all subsections concisely together:

1. **Summary** — 1–2 paragraphs describing the entire changeset's purpose, scope, and key impact
2. **Architecture** — 1-3 paragraphs or a short bulleted list describing new/changed structure; omit (and say so) if the changes are purely behavioral with no structural changes
Then stop and prompt:

```
Ask questions for deeper detail on any of these, or **next** to move on to the architecture breakdown.
```

**If the user asks questions:** Answer them, then re-show the prompt.

---

## Section 2: Architecture Breakdown

Present any new data structures that were introduced by the changes. Then give an overview of each module added or changed, including the functions that are part of the PR. Then present a visualization of the call graph for the changed code, showing how functions relate to each other across files. 

Then stop and propmt:

```
Ask questions for deeper detail on any of these, or **next** to move on to the module breakdown.
```

Walk through each changed file **one at a time** moving up from the bottom of the call graph. For each file, provide a concise summary of what changed and why it matters in the context of the overall PR.

### File summary format:

```markdown
### `path/to/file.ext` _(N review comments)_

[what changed in this file, what role it plays, and any notable details]
```
Then display all inline review comments for the file, grouped by reviewer. Format each comment as:

```markdown
**@username** on [function or type]:
> [comment body]
```

Then stop and prompt:

```
Ask questions for deeper details of this file, or **next** to move on to the next file.
```

**If the user asks questions:** Answer them, then re-show the current prompt.

After the last file, prompt:

```
Say **next** to move on to error analysis.
```

## Section 3: Suspicious Items and Noteworthy Concerns

Present code smells and any other suspicious or problematic code found in the changed code. Present items **one at a time**, waiting for the user between each.

### What to Flag

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
⚠️ **[Category]** — `path/to/file.ext` (`functionName` or line reference)

\`\`\`[language]
[relevant code excerpt]
\`\`\`

[Explanation: what is suspicious or problematic and why it matters]
```

After each item, prompt:

```
Say **next** to see the next item, or ask questions about this one.
```

After the last item, print:

```
Review complete.
```

If no suspicious items are found, say so and print "Review complete."

---

## Navigating Sections

The user moves forward by saying "next", "proceed", "continue", "move on", or similar.

The user requests more detail within a section by saying "more", "expand", "more detail", "go deeper", or similar. In Section 1, the user can target a specific subsection with "more summary", "more architecture", or "more data flow".

The user can ask questions at any prompt — answer them and then re-show the current prompt.

---

## Additional Resources

### Reference Files

- **`references/review-focus-patterns.md`** — Detailed patterns for Section 3: Suspicious Items and Noteworthy Concerns
- **`references/dependency-analysis-patterns.md`** — Strategies for determining dependency order across languages

### Helper Scripts

- **`scripts/fetch-pr-info.ps1`** — PowerShell script to fetch PR information via `gh` CLI
- **`scripts/get-comments.ps1`** — Fetches inline diff comments from the GitHub API and formats them as readable `FILE | LINE | USER` / `BODY` blocks. Always invoke with `pwsh -File "<absolute-path-to-script>"` (not just `pwsh "<path>"`) so that backslashes in the path are not interpreted as escape characters on Windows. Example: `pwsh -File "C:\path\to\get-comments.ps1" -url "repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments"`

---

## Workflow Summary

1. **Parse input** → Determine if PR number, PR + base, or branches
2. **Fetch changes** → Use `gh pr diff` or `git diff`
3. **Read files** → Load changed files for full context
4. **Pre-analyze** → Prepare all four sections before producing output
5. **Section 1** → Overview (summary + architecture + data flow together) → wait; expand individual subsections on "more [topic]", advance on "next"
6. **Section 2** → File-by-file **in dependency order** (from Step 4), one file at a time → wait after each; expand to functions on "more", advance on "next"
7. **Section 3** → Error origins one-at-a-time → wait after each; propagation summary → wait; advance on "next"
8. **Section 4** → Code smells one-at-a-time → wait after each; advance on "next"
9. **Complete** → Print "Review complete."
