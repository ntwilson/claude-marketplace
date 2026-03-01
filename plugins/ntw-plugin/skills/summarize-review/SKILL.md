---
name: summarize-review
description: Use this skill when the user asks to "summarize a PR", "summarize review", "give me a layered summary", "drill-down review", or wants a high-level overview of code changes that progressively adds more detail on demand. Provides a multi-section, interactive review that covers summary, architecture, file-by-file breakdown, data flow, error analysis, and code smells.
---

# Summarize Review Assistant

This skill provides a multi-section, layered code review that starts with high-level summaries and progressively adds detail on demand. Each section pauses and waits for the user to request more detail or move on.

## Purpose

Walk through a review in six focused sections — each interactive and expandable — rather than element by element:

1. **Overall summary** — what and why
2. **Architecture** — structure of new/changed code
3. **File-by-file breakdown** — per-file summaries, with optional per-function detail
4. **Data flow** — how data moves through the changes
5. **Error analysis** — where errors originate and how they propagate
6. **Code smells / suspicious items** — language-specific concerns and anything noteworthy

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
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --paginate
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews --paginate
```

The first `api` call returns inline diff comments (each has `path`, `line`, `original_line`, `body`, `user.login`, `created_at`, `html_url`). The second returns top-level review submissions (each has `body`, `user.login`, `state`, `submitted_at`). Fetch both and retain them for use in Section 3.

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

Before producing any output, fully analyze the changes across all files to prepare all six sections. Specifically:

- Understand the overall purpose and scope
- Identify architectural patterns in new/changed code
- Summarize each changed file and its key functions
- **For PR reviews:** Group inline review comments by file and by function/line range, so each file and function knows how many comments it has and what they say
- Trace data flow through the changes
- Identify all error origins and propagation paths
- Collect all language-specific suspicious items and any other noteworthy concerns

This pre-analysis ensures each section is complete and coherent when presented.

---

## Section 1: Overall Summary

Output a 1–5 sentence summary of the entire changeset — its purpose, scope, and key impact. Then stop and prompt:

```
Say **more** for a more detailed summary, or **next** to move on to architecture.
```

**If the user says "more":** Provide a new summary with approximately twice the content of the previous one (e.g., if the last was 4 sentences, aim for ~8 sentences). Add specifics: which components changed, what behaviors differ, any notable tradeoffs. Then stop and prompt again:

```
Say **more** for even more detail, or **next** to move on to architecture.
```

Repeat this pattern — each "more" approximately doubles the content — until the user says "next".

**Ceiling rule:** If the next doubling would produce output comparable in length to the actual diff or changed code itself, just print the relevant code/diff directly instead of producing a prose summary of similar size. A summary longer than what it summarizes is not a summary.

**If the user asks questions:** Answer them, then re-show the prompt.

---

## Section 2: Architecture

Summarize the architecture of the new or changed code, if applicable. Focus on:

- New types, modules, components, or abstractions introduced
- How new code is structured (layers, separation of concerns, composition patterns)
- How changed code fits into the existing architecture
- Any architectural shifts (e.g., a computation moved from pure to effectful, a new abstraction layer added)

Skip this section (and say so) if the changes are purely behavioral with no structural/architectural changes.

Start with a concise version (2–5 sentences or a short bulleted list). Then stop and prompt:

```
Say **more** for a more detailed architecture breakdown, or **next** to move on to the file-by-file breakdown.
```

Apply the same "more doubles content" pattern as Section 1 (including the ceiling rule) until the user says "next".

---

## Section 3: File-by-File Breakdown

Walk through each changed file **one at a time** in dependency order. For each file, provide a concise summary of what changed and why it matters in the context of the overall PR.

### File summary format:

```markdown
### `path/to/file.ext` _(N review comments)_

[2–4 sentences: what changed in this file, what role it plays, and any notable details]
```

Omit the comment count if there are no review comments on the file, or if the review was not for a PR.

After each file summary, the prompt depends on whether there are review comments on the file:

**With review comments:**
```
Say **comments** to see the review comments on this file, **more** for a function-by-function breakdown, or **next** to move on to the next file.
```

**Without review comments:**
```
Say **more** for a function-by-function breakdown of this file, or **next** to move on to the next file.
```

**If the user says "comments":** Display all inline review comments for the file, grouped by reviewer. Format each comment as:

```markdown
**@username** on line N:
> [comment body]
```

After showing comments, re-show the current prompt (replacing "comments" with "more" if comments have already been shown):

```
Say **more** for a function-by-function breakdown of this file, or **next** to move on to the next file.
```

**If the user says "more":** Break the file down function by function (or logical block by block for non-function-oriented files). For each function or block that changed, show:
- The function/block name
- A 1–3 sentence description of what it does and what changed
- **For PR reviews:** Any inline review comments whose line falls within the function, formatted the same as above, immediately after the function description

Present all functions for that file together (not one at a time), then prompt:

```
Say **next** to move on to the next file.
```

**If the user asks questions:** Answer them, then re-show the current prompt.

After the last file, prompt:

```
Say **next** to move on to data flow.
```

---

## Section 4: Data Flow

Summarize how data moves through the changed code. Focus on:

- Where data enters (inputs, parameters, external sources)
- How it is transformed as it flows through the changed code
- Where it exits (outputs, side effects, storage)
- Any notable branching paths or conditional transformations
- How data flow in changed areas differs from before (if discernible)

Start concisely (2–5 sentences or a short bulleted trace). Then stop and prompt:

```
Say **more** for a more detailed data flow breakdown, or **next** to move on to error analysis.
```

Apply the same "more doubles content" pattern (including the ceiling rule) until the user says "next".

---

## Section 5: Error Analysis

Identify and explain errors and failure conditions in the changed code. Present error origins **one at a time**, waiting for the user between each. After all origins, present the propagation summary.

### 5a: Error Origins

For each place in the changed code where an error or failure condition can arise, show:
- The code location (file and function/line)
- A brief excerpt of the relevant code
- What error or failure condition can occur there

Focus on typed errors and explicit failure cases, such as:
- `Error` or `Result` types in F# (e.g., `Error "..."`, `Result.Error`)
- `Left` or `throwError` in PureScript (e.g., `Left err`, `throwError`, `ExceptT`)
- `raise`/`throw`/`Exception` in Python, TypeScript, etc.
- Functions that can return `None`/`null`/`Nothing` in failure cases
- Functions known to throw on invalid input (see language-specific lists below)

### 5b: Error Propagation

After all error origins have been presented, explain:
- How errors flow upward through the call chain
- Whether errors are caught, handled, or re-raised at any point
- Whether errors are aggregated (e.g., collecting multiple validation errors into a list)
- Whether any errors are silently swallowed

### Format for each error origin:

```markdown
#### `functionName` — `path/to/file.ext`

\`\`\`[language]
[relevant code excerpt]
\`\`\`

[1-3 sentences: what can go wrong here and under what conditions]
```

After each error origin, prompt:

```
Say **next** to see the next error, or ask questions about this one.
```

After the last error origin, present the propagation summary, then stop and prompt:

```
Feel free to ask questions about any of these errors, or say **next** to move on to code smells.
```

Answer any questions the user asks, then re-show the prompt until the user says "next".

If no error origins are found, say so, skip the propagation summary, and prompt:

```
Say **next** to move on to code smells.
```

---

## Section 6: Code Smells and Suspicious Items

Present language-specific code smells and any other suspicious or problematic code found in the changed code. Present items **one at a time**, waiting for the user between each.

### What to Flag

**Language-specific items (always flag):**

**F# files (`.fs`):**
- `let mutable` declarations
- Mutable collection operations: `.Add(...)`, `.Remove(...)`, `.Clear()`, `.Insert(...)`, `dict.[key] <- value`, `.Push(...)`, `.Pop()`, `.Enqueue(...)`, `.Dequeue()`
- Functions that may throw on invalid input:
  - `Array.head`, `Array.tail`, `Array.last`, `Array.reduce`, `Array.item`, `Array.exactlyOne`
  - `List.head`, `List.tail`, `List.last`, `List.reduce`, `List.item`, `List.exactlyOne`
  - `Seq.head`, `Seq.last`, `Seq.reduce`, `Seq.item`, `Seq.exactlyOne`
  - `Map.find`, `Map.item`, `Option.get`, `Result.get`
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

The user requests more detail within a section by saying "more", "expand", "more detail", "go deeper", or similar.

The user can ask questions at any prompt — answer them and then re-show the current prompt.

---

## Output Format Summary

### Section 1: Overall Summary

```markdown
# Code Review Summary

[1–5 sentence summary]

Say **more** for a more detailed summary, or **next** to move on to architecture.
```

### Section 2: Architecture

```markdown
## Architecture

[Concise architectural summary]

Say **more** for a more detailed architecture breakdown, or **next** to move on to the file-by-file breakdown.
```

### Section 3: File-by-File Breakdown (one file at a time)

```markdown
## File-by-File Breakdown

### `path/to/file.ext` _(3 review comments)_

[2–4 sentence file summary]

Say **comments** to see the review comments on this file, **more** for a function-by-function breakdown, or **next** to move on to the next file.
```

On "comments":

```markdown
**@alice** on line 42:
> [comment body]

**@bob** on line 57:
> [comment body]

Say **more** for a function-by-function breakdown of this file, or **next** to move on to the next file.
```

On "more":

```markdown
### `path/to/file.ext` — Functions

- **`functionName`** — [1–3 sentence description]

  **@alice** on line 42:
  > [comment body]

- **`anotherFunction`** — [1–3 sentence description]

...

Say **next** to move on to the next file.
```

### Section 4: Data Flow

```markdown
## Data Flow

[Concise data flow summary]

Say **more** for a more detailed data flow breakdown, or **next** to move on to error analysis.
```

### Section 5: Error Analysis (one at a time)

```markdown
## Error Analysis

#### `functionName` — `path/to/file.ext`
\`\`\`[language]
[code excerpt]
\`\`\`
[explanation]

Say **next** to see the next error, or ask questions about this one.
```

After all origins, present propagation summary then prompt:

```markdown
### Error Propagation

[Explanation of how errors flow, are handled, or are swallowed]

Feel free to ask questions about any of these errors, or say **next** to move on to code smells.
```

### Section 6: Code Smells (one at a time)

```markdown
## Code Smells and Suspicious Items

⚠️ **[Category]** — `path/to/file.ext` (`functionName`)

\`\`\`[language]
[code excerpt]
\`\`\`

[explanation]

Say **next** to see the next item, or ask questions about this one.
```

After all items:

```markdown
Review complete.
```

---

## Additional Resources

### Reference Files

- **`references/review-focus-patterns.md`** — Detailed patterns for security issues, bugs, performance problems, and language-specific suspicious items
- **`references/dependency-analysis-patterns.md`** — Strategies for determining dependency order across languages

### Helper Scripts

- **`scripts/fetch-pr-info.ps1`** — PowerShell script to fetch PR information via `gh` CLI

---

## Workflow Summary

1. **Parse input** → Determine if PR number, PR + base, or branches
2. **Fetch changes** → Use `gh pr diff` or `git diff`
3. **Read files** → Load changed files for full context
4. **Pre-analyze** → Prepare all six sections before producing output
5. **Section 1** → Overall summary → wait; expand on "more", advance on "next"
6. **Section 2** → Architecture → wait; expand on "more", advance on "next"
7. **Section 3** → File-by-file, one file at a time → wait after each; expand to functions on "more", advance on "next"
8. **Section 4** → Data flow → wait; expand on "more", advance on "next"
9. **Section 5** → Error origins one-at-a-time → wait after each; propagation summary → wait; advance on "next"
10. **Section 6** → Code smells one-at-a-time → wait after each; advance on "next"
11. **Complete** → Print "Review complete."
