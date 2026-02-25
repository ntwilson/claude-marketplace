---
name: help-review
description: This skill should be used when the user asks to "review a PR", "review pull request", "review changes", "summarize a PR", "analyze code changes", "help review", or provides a GitHub PR number for review. Provides interactive, dependency-ordered code review walkthroughs with actionable insights.
---

# Code Review Assistant

This skill provides interactive, incremental code review walkthroughs organized in dependency order. It starts with a high-level overview, then walks through individual code elements one at a time, allowing the reviewer to ask questions at each step.

## Purpose

Generate interactive code review walkthroughs that:
- Start with a concise overview, then drill into details on demand
- Present changes in dependency order (callees before callers)
- Show diffs inline for all changes
- Surface suspicious items inline at the relevant code element
- Support multiple input formats (PR number, branches, or PR with custom base)

## When to Use

Use this skill when the user requests:
- Review of a GitHub pull request by number
- Summary of changes between branches
- Analysis of code changes for review purposes
- Hierarchical breakdown of a changeset

## Input Formats

Accept one of three input formats:

1. **PR number only**: `123`
2. **PR number with alternative base**: `123` and `develop` (instead of PR's default base)
3. **Base and head branches**: `main` and `feature-branch`

## Review Process

### Step 1: Fetch Change Information

**For PR number:**
```bash
gh pr view <PR_NUMBER> --json number,title,body,baseRefName,headRefName,files
gh pr diff <PR_NUMBER>
```

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

If not on head branch and files need to be read for context, use git to check out the branch or proceed with available information.

### Step 3: Analyze Changed Files

For each changed file:
1. Read the current version using the Read tool
2. Examine the diff to understand what changed
3. Identify:
   - Changed functions/methods
   - Changed types/classes/modules
   - Dependencies between changes
   - Nested structures (functions within functions, etc.)

### Step 4: Determine Dependency Order

Order files so that:
- Dependencies appear before dependents (callees before callers)
- Lower-level utilities come before higher-level orchestration
- Shared/common code comes before specific implementations

**Exception:** If the PR body includes a section specifying review order (e.g., "Review order:", "Files to review in order:"), use that order instead.

### Step 5: Identify Suspicious Items

Before producing any output, scan all changes and identify suspicious or noteworthy items across the **entire** review. These include general concerns:
- Potential bugs or logic errors
- Missing error handling
- Security concerns
- Breaking changes
- Performance implications
- Unexpected complexity

And language-specific items that should **always** be flagged (see "Language-Specific Suspicious Items" below for the full list):
- In F# files: `mutable` declarations, mutable collection operations, functions that may throw, non-deterministic or side-effectful operations outside `io { ... }`
- In PureScript files: any use of `unsafe` functions

All items are surfaced inline during the walkthrough at the specific code element they relate to — not as a separate up-front section.

### Step 6: Present Initial Overview (Phase 1 output)

Output the following and then **stop and wait** for the user:

1. **Overall summary**: 1-5 sentences describing the entire changeset's purpose and scope
2. **File list**: Each changed file (in dependency order) with 1-2 sentences summarizing its changes
3. **Prompt**: Tell the user to say "next" to begin walking through individual changes

### Step 7: Interactive Walkthrough (Phase 2, one element at a time)

When the user says "next", "proceed", "move on", "continue", or similar:

1. **If entering a new file** (first element in that file): print a 1-5 sentence summary of the changes in this file
2. **Current code element** (function, type definition, method, etc.):
   - Print the element's name and signature
   - Print the diff in a fenced code block
   - Print 1-5 sentences describing the change
   - If this element is one of the suspicious items identified in Step 5: print the concern with a ⚠️ prefix
3. **Stop and wait** — the user may ask questions about this element, or say "next" to continue

Repeat until all code elements across all files are exhausted, then print: "Review complete."

**Skipping files:** If the user says "next file" or "skip file", skip all remaining elements in the current file and move to the first element of the next file.

**Element ordering:**
- Files are presented in dependency order (same as the overview)
- Elements within each file are presented in **top-to-bottom order** as they appear in the file (no dependency analysis needed within a file)

## Output Format

The review is split into two phases:

### Phase 1: Initial Overview

```markdown
# Code Review Summary

[1-5 sentence overall summary]

## Files Changed (in dependency order)
1. **`path/to/file1.ext`** - [1-2 sentence summary]
2. **`path/to/file2.ext`** - [1-2 sentence summary]
3. **`path/to/file3.ext`** - [1-2 sentence summary]

Say **next** to begin walking through individual changes.
```

### Phase 2: Element-by-Element Walkthrough

Each time the user says "next", output one code element:

```markdown
## `path/to/file1.ext`
[1-5 sentence file summary — only printed when entering a new file]

### `functionName: paramType -> returnType`

\`\`\`diff
[diff]
\`\`\`

[1-5 sentence description of the change]

⚠️ [Suspicious item — only if this is one of the few flagged items]
```

After the last element:

```markdown
Review complete.
```

## Formatting Guidelines

**File paths:** Use backticks and full relative paths from repo root

**Function signatures:** Include parameter types and return types when available:
- F#/PureScript: `functionName: param1Type -> param2Type -> returnType`
- Python: `def functionName(param1: Type1, param2: Type2) -> ReturnType`
- TypeScript: `functionName(param1: Type1, param2: Type2): ReturnType`

**Line references:** When referring to specific code, use `file.ext:lineNumber` format

**Dependency order examples:**
```
✅ Correct order:
1. `Utils.fs` - Helper functions
2. `DataStructures.fs` - Type definitions using helpers
3. `Business.fs` - Business logic using data structures
4. `Program.fs` - Entry point orchestrating business logic

❌ Incorrect order:
1. `Program.fs` - References functions not yet explained
2. `Business.fs` - References types not yet explained
3. `DataStructures.fs`
4. `Utils.fs`
```

## Language-Specific Considerations

### F# Codebases

- Recognize module structure and nested modules
- Identify computation expressions (`io { }`, `async { }`)
- Note type inference impacts (when signatures change)

### PureScript Codebases

- Recognize module structure and imports
- Note Effect vs pure function boundaries

### Python Codebases

- Identify class vs function changes
- Note decorator changes
- Highlight type hint modifications
- Flag async/await additions

### General Principles

- Adapt hierarchy to language idioms
- Use language-native terminology (module vs class vs namespace)
- Recognize language-specific risks (null references, type safety, etc.)

## Language-Specific Suspicious Items

These items should **always** be flagged with ⚠️ when they appear in changed code.

### F# Files (`.fs`)

**Functions that may throw an exception** — flag any call to a function that throws on invalid input instead of returning an Option or Result:
- `Array.head`, `Array.tail`, `Array.last`, `Array.reduce`, `Array.item`, `Array.exactlyOne`
- `List.head`, `List.tail`, `List.last`, `List.reduce`, `List.item`, `List.exactlyOne`
- `Seq.head`, `Seq.last`, `Seq.reduce`, `Seq.item`, `Seq.exactlyOne`
- `Map.find`, `Map.item`
- `Option.get`
- `Result.get` (if present)
- `dict.[key]` (indexer access on dictionaries)
- `int`, `float` conversions that throw on failure
- Any similar function that throws rather than returning Option/Result

**Mutable variable declarations** — flag any use of `let mutable`:
```fsharp
// ⚠️ Always flag
let mutable counter = 0
```

**Mutable collection operations** — flag method calls that mutate a collection in place:
- `.Add(...)`, `.Remove(...)`, `.Clear()`, `.Insert(...)` on `Dictionary`, `ResizeArray`, `HashSet`, `List<T>`, etc.
- `dict.[key] <- value` (mutation via indexer)
- `.Push(...)`, `.Pop()`, `.Enqueue(...)`, `.Dequeue()` on `Stack`, `Queue`

**Non-deterministic operations outside `io { ... }`** — flag calls that produce non-deterministic results when they appear outside an `io { }` computation expression:
- `DateTime.Now`, `DateTime.UtcNow`, `DateTimeOffset.Now`, `DateTimeOffset.UtcNow`
- `System.Random`, `Guid.NewGuid()`
- `Environment.GetEnvironmentVariable`
- `Stopwatch` usage

**Side effects / outside-world interaction outside `io { ... }`** — flag I/O or external interaction when it appears outside an `io { }` computation expression:
- `System.IO` operations: `File.ReadAllText`, `File.WriteAllText`, `Directory.CreateDirectory`, `StreamReader`, `StreamWriter`, etc.
- `Console.WriteLine`, `Console.ReadLine`, `printfn` (when not in a script/entry point)
- Network calls: `HttpClient`, `WebRequest`, etc.
- Database access outside `io { }`
- Process launching: `System.Diagnostics.Process`

### PureScript Files (`.purs`)

**Any use of `unsafe` functions** — flag every occurrence of functions containing "unsafe" in the name:
- `unsafeCoerce`
- `unsafePartial`
- `unsafePerformEffect`
- `unsafeThrow`
- `unsafeFreeze`, `unsafeThaw`
- Any other function with `unsafe` in the name

## Additional Resources

### Reference Files

For detailed guidance, consult:
- **`references/dependency-analysis-patterns.md`** - Comprehensive strategies for determining dependency order, handling circular dependencies, and language-specific patterns
- **`references/review-focus-patterns.md`** - Detailed patterns for identifying security issues, bugs, performance problems, and areas requiring closer attention

### Example Outputs

See `examples/` directory for sample interactive review walkthroughs:
- **`examples/pr-review-example.md`** - Interactive PR review showing both phases with user Q&A
- **`examples/branch-comparison-example.md`** - Interactive branch comparison review

### Helper Scripts

Available in `scripts/` directory:
- **`scripts/fetch-pr-info.ps1`** - PowerShell script to fetch PR information via `gh` CLI (cross-platform: Windows/Linux/macOS)

## Usage Examples

**Example 1: Review PR by number**
```
User: "Help review PR 456"
→ Fetch PR 456, analyze changes, output Phase 1 overview, wait for "next"
→ User: "next" → show first code element
→ User: "What does this function do?" → answer question about current element
→ User: "next" → show next code element
→ ... continue until "Review complete."
```

**Example 2: Review PR with alternative base**
```
User: "Review PR 789 against develop instead of main"
→ Fetch PR 789, diff against develop, output Phase 1 overview, wait
```

**Example 3: Review branch comparison**
```
User: "Review changes from main to feature-auth"
→ Diff main...feature-auth, output Phase 1 overview, wait
```

## Implementation Notes

### Dependency Analysis Strategy

To determine dependency order:

**For F# projects (simplified approach):**
1. **Read the .fsproj file** to get file ordering (files are already in dependency order)
2. **List changed files** in the order they appear in .fsproj
3. **Within each file**, present changes in the order they appear (F# enforces dependency order within files)
4. No need for call graph analysis, import tracking, or topological sorting

**For other languages:**
1. **Read all changed files** to build full context
2. **Identify imports/dependencies** in each file
3. **Build dependency graph** of changed functions
4. **Topological sort** to order files and functions
5. **Group by layer** (utilities → data → logic → orchestration)

### PR Body Review Order

Check PR body for review order directives:
```markdown
## Review Order
1. First review DataStructures.fs
2. Then Business.fs
3. Finally Program.fs
```

If found, use this order instead of dependency order.

### Balancing Detail and Brevity

Keep each summary at 1-2 sentences by:
- Focusing on **what** changed and **why**, not line-by-line details
- Using active voice and precise verbs ("Refactors X to Y", "Adds validation for Z")
- Omitting obvious changes (formatting, comment updates) unless significant
- Grouping related small changes into single summary

## Best Practices

**DO:**
- Always present changes in dependency order (unless PR specifies otherwise)
- Read actual file contents for context, not just diffs
- Highlight breaking changes prominently
- Note when tests are missing for new functionality
- Flag security and performance concerns

**DON'T:**
- List files in arbitrary order (alphabetical, commit order)
- Summarize line-by-line changes mechanically
- Miss nested structures (functions within functions)
- Ignore PR body's prescribed review order
- Overwhelm with excessive detail in summaries

## Workflow Summary

1. **Parse input** → Determine if PR number, PR + base, or branches
2. **Fetch changes** → Use `gh pr diff` or `git diff`
3. **Ensure branch** → Verify head branch checked out if needed
4. **Read files** → Load changed files for full context
5. **Analyze dependencies** → Determine file order; identify code elements top-to-bottom within each file
6. **Identify suspicious items** → Find the few most concerning items across the entire review
7. **Output Phase 1** → Overall summary + file list with per-file summaries → **stop and wait**
8. **Interactive Phase 2** → On each "next": show one code element (with diff, description, and inline suspicious flag if applicable) → **stop and wait**
9. **Complete** → After last element, print "Review complete."

The review is interactive: always stop after Phase 1 and after each code element to let the reviewer ask questions or move on.
