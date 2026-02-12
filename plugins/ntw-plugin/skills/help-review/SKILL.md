---
name: help-review
description: This skill should be used when the user asks to "review a PR", "review pull request", "review changes", "summarize a PR", "analyze code changes", "help review", or provides a GitHub PR number for review. Provides hierarchical, dependency-ordered summaries of code changes with actionable insights.
version: 0.1.0
---

# Code Review Assistant

This skill provides structured, hierarchical code review summaries organized in dependency order to help reviewers understand changes systematically.

## Purpose

Generate comprehensive code review summaries that:
- Present changes in dependency order (callees before callers)
- Provide hierarchical summaries from high-level to detailed
- Highlight suspicious code and areas requiring closer attention
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

If not on head branch and files need to be read for context, ask user to check out the branch or proceed with available information.

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

Order files and functions so that:
- Dependencies appear before dependents (callees before callers)
- Lower-level utilities come before higher-level orchestration
- Shared/common code comes before specific implementations

**Exception:** If the PR body includes a section specifying review order (e.g., "Review order:", "Files to review in order:"), use that order instead.

### Step 5: Build Hierarchical Summary

Construct a multi-level hierarchy:

**Level 1: Overall Summary**
- 1-2 sentences describing the entire changeset's purpose and scope

**Level 2: File Summaries**
- For each changed file (in dependency order):
  - File path
  - 1-2 sentences summarizing changes in this file

**Level 3: Module/Class Summaries** (conditional)
- If file contains multiple modules/classes with changes:
  - Module/class name
  - 1-2 sentences summarizing changes in this module/class
- Skip this level if file has only one module/class

**Level 4: Function/Type Summaries**
- For each changed function, method, or type definition:
  - Function/type name and signature
  - 1-2 sentences describing the change
  - For nested functions, indent under parent function

**Level 5+: Deeper Nesting** (as applicable)
- Continue hierarchy for nested structures

### Step 6: Identify Review Focus Areas

Create a section (at top or bottom of summary) listing:

**Suspicious or Noteworthy Items:**
- Potential bugs or logic errors
- Missing error handling
- Unexpected complexity
- Breaking changes
- Security concerns
- Performance implications

**Files/Functions Requiring Closer Attention:**
- Core business logic changes
- Complex refactorings
- High-risk modifications
- Areas with subtle bugs

## Output Format

Structure the output as markdown with clear hierarchy:

```markdown
# Code Review Summary

## Overall Changes
[1-2 sentence summary of entire changeset]

## Files Changed (in dependency order)

### `path/to/file1.ext`
[1-2 sentence file summary]

#### Module: `ModuleName` (if multiple modules)
[1-2 sentence module summary]

##### Function: `functionName(params): returnType`
[1-2 sentence function change summary]

###### Nested: `nestedFunction()`
[1-2 sentence nested function summary]

### `path/to/file2.ext`
[Continue pattern...]

## Review Focus

### ⚠️ Items Requiring Attention
- [Suspicious item 1]
- [Security concern]
- [Complex logic requiring scrutiny]

### 📍 Priority Files/Functions
- **`file.ext:functionName`** - [Why this needs closer review]
- **`other.ext:ClassName`** - [Why this needs closer review]
```

## Formatting Guidelines

**File paths:** Use backticks and full relative paths from repo root

**Function signatures:** Include parameter types and return types when available:
- F#: `functionName: param1Type -> param2Type -> returnType`
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
- Highlight pipeline changes (`|>`, `>>`)
- Flag mutable state (`mutable`, `ref`)

### Python Codebases

- Identify class vs function changes
- Note decorator changes
- Highlight type hint modifications
- Flag async/await additions

### General Principles

- Adapt hierarchy to language idioms
- Use language-native terminology (module vs class vs namespace)
- Recognize language-specific risks (null references, type safety, etc.)

## Additional Resources

### Reference Files

For detailed guidance, consult:
- **`references/dependency-analysis-patterns.md`** - Comprehensive strategies for determining dependency order, handling circular dependencies, and language-specific patterns
- **`references/review-focus-patterns.md`** - Detailed patterns for identifying security issues, bugs, performance problems, and areas requiring closer attention

### Example Outputs

See `examples/` directory for sample review summaries:
- **`examples/pr-review-example.md`** - Full PR review with hierarchy
- **`examples/branch-comparison-example.md`** - Branch comparison review

### Helper Scripts

Available in `scripts/` directory:
- **`scripts/fetch-pr-info.ps1`** - PowerShell script to fetch PR information via `gh` CLI (cross-platform: Windows/Linux/macOS)

## Usage Examples

**Example 1: Review PR by number**
```
User: "Help review PR 456"
→ Fetch PR 456, analyze changes, generate hierarchical summary in dependency order
```

**Example 2: Review PR with alternative base**
```
User: "Review PR 789 against develop instead of main"
→ Fetch PR 789, diff against develop, generate summary
```

**Example 3: Review branch comparison**
```
User: "Review changes from main to feature-auth"
→ Diff main...feature-auth, generate summary
```

## Implementation Notes

### Dependency Analysis Strategy

To determine dependency order:

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

### Handling Large PRs

For PRs with >20 files changed:
- Ask user if they want full summary or focused summary
- Offer to summarize only specific files or modules
- Prioritize core business logic over test/config changes

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
5. **Analyze dependencies** → Build dependency graph
6. **Order output** → Sort by dependencies (or PR body order)
7. **Generate hierarchy** → Overall → Files → Modules → Functions
8. **Identify focus areas** → Suspicious items and priority areas
9. **Format output** → Markdown with clear visual hierarchy

Focus on creating actionable, easy-to-navigate summaries that help reviewers understand complex changes efficiently.
