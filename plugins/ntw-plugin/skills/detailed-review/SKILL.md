---
name: detailed-review
description: Use this skill when the user asks for a "detailed review", to "walk me through a PR", to "review a PR chunk by chunk", to "show me the changes in implementation order", to "review this like manual mode", or provides a GitHub PR number and wants the changes broken into reviewable chunks with their diffs. Writes a markdown document that replays the changeset as an ordered sequence of indexed edit chunks - each with its diff, a short justification, and a deep link to its exact line on the PR, as if Claude Code had proposed them one at a time in Manual Mode - then answers follow-up questions prefixed by chunk ID, and posts inline review comments back to the PR - including writing the actual code for a suggested change the user only describes in prose.
---

# Detailed Review Assistant

This skill replays a finished changeset as if it had been written from scratch in Claude Code's **Manual Mode**: a sequence of edit-sized chunks, in the order they would actually have been implemented, each with its diff and a one-or-two-sentence justification.

The whole sequence is written to a single markdown document in one pass. Every chunk gets a sequential index (`#1`, `#2`, …). After writing the file, stand ready to answer follow-up questions prefixed by a chunk ID (e.g. "#7 why is the TTL per-call?").

## Core Behavior

1. Gather **everything** about the changeset up front — diff, full file context, review comments.
2. Split it into **chunks** sized the way a careful implementer would have written them.
3. Order the chunks the way the change would actually have been **implemented**.
4. Write the **entire document** in one pass, with each chunk indexed and carrying its diff, a 1–2 sentence justification, and a **deep link to its exact line** on the PR.
5. Report the path, then answer **follow-ups by chunk ID**, and **queue inline comments and suggested code changes by chunk ID** for submission as one review.

Do not pause between chunks and do not ask the user to advance — the document is written complete.

## Input Formats

1. **PR number only**: `123`
2. **PR number with alternative base**: `123` against `develop`
3. **Base and head branches**: `main` and `feature-branch`
4. **No argument**: assume the current branch has an open PR and review it. Resolve it with `gh pr view` (no argument) and proceed as if that number had been typed — see **section 0** of `../../shared/references/pr-interaction.md` for resolution and the fallbacks when there is no open PR. State which PR was resolved before going further.

---

## Phase 1: Gather (before writing anything)

### Step 0: Resolve the target

If the user gave no PR number and no branch names, resolve the current branch's open PR per **section 0** of `../../shared/references/pr-interaction.md`, then continue as a PR review.

### Step 1: Fetch change information

**For a PR number:**
```bash
gh pr view <PR_NUMBER> --json number,title,body,baseRefName,headRefName,headRefOid,files
gh pr diff <PR_NUMBER>
pwsh -File ../../shared/scripts/get-comments.ps1 -url "repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments"
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews --paginate
```

`get-comments.ps1` outputs each inline diff comment as `FILE: <path> | LINE: <line> | USER: <username>` followed by `BODY: <text>`, blocks separated by `---`. The `reviews` call returns top-level review submissions (`body`, `user.login`, `state`, `submitted_at`). Fetch both and keep them — they get attached to chunks in Phase 2.

Resolve `{owner}` and `{repo}` from `gh repo view --json owner,name` or from the PR URL.

**Retain `headRefOid`** — the head commit SHA. Chunk links and any posted comments are anchored to it, so that both point at the code that was actually reviewed.

**For branches:**
```bash
git diff <BASE_BRANCH>...<HEAD_BRANCH>
git diff <BASE_BRANCH>...<HEAD_BRANCH> --name-status
```

### Step 1b: Compute the diff anchors (PR reviews only)

Follow **section 1** of `../../shared/references/pr-interaction.md` to compute the `#diff-<hash>` anchor for every changed file in one call. Keep the returned base URL per file; per-chunk links are then string concatenation with `R<anchorLine>`.

Skip this step for branch comparisons; there is no PR to link into.

### Step 2: Ensure the right code is available

```bash
git branch --show-current
```

If the head branch is not checked out, either check it out or proceed with the diff plus whatever file context is reachable. Note in the document if context was limited.

### Step 3: Read the changed files

Read the current version of every changed file with the `Read` tool. The justifications are only useful if they explain how each chunk fits the surrounding code, and that needs more than the diff hunks.

### Step 4: Map the call graph

Determine what calls what among the changed declarations, and which new declarations existing code depends on. This drives both chunking and ordering. See `../../shared/references/dependency-analysis-patterns.md`.

**For F# projects:** read the `.fsproj` — compilation order is already dependency order.

---

## Phase 2: Chunk

A chunk is one unit of work that a competent implementer would have written in one sitting — the granularity of a single manual-mode edit proposal.

### Sizing rules

- **Substantial logic** — 1–2 functions/methods per chunk. A single function with real logic in it is its own chunk. Two functions belong together only when one exists solely to serve the other (a local helper, a private worker called from exactly one place).
- **Types and data structures** — a related cluster of types is one chunk (a record plus the DU it contains, a type plus its module of constructors).
- **Trivial or mechanical changes** — group generously. A rename applied across 12 files, added `open`/`import` lines, formatting, a version bump, regenerated snapshots: one chunk each, however many files they span.
- **Tests** — group the tests covering one unit of behavior into one chunk, rather than one chunk per test case.
- **Config, project files, docs** — one chunk per concern, not per file.

### Sizing sanity check

Aim for chunks that fit on a screen. If a chunk's diff runs past roughly 60 lines and is not mechanical, split it. If its justification needs an "and also, separately, …", split it. If two consecutive chunks would have the same justification, merge them.

For a very large changeset, prefer merging trivia aggressively over producing 40+ chunks. If it still yields more than ~25 chunks, note in the document that trivia has been grouped hard.

### Attach to each chunk

- The **diff** for exactly that chunk — the relevant hunks, trimmed to the chunk's declarations, with enough surrounding context to read.
- A **justification**: 1–2 sentences on why this change was needed and why it looks the way it does. This is the "why", not a restatement of the diff.
- Any **inline review comments** whose line falls inside the chunk.
- Any **concerns** — the chunk is the right place to raise a bug, smell, or risk, because that is where the code sits. Use `references/review-focus-patterns.md` for what is worth flagging, plus anything else you find suspicious.
- Its **line range** — see below. Both the chunk's link and any comment posted on it depend on real line numbers, so this is not optional.

### Tracking line numbers

Follow **section 2** of `../../shared/references/pr-interaction.md`. For each chunk, record its `anchorLine` (the first added or changed right-side line — what the chunk's link points at), its `startLine`/`endLine` span, and its `side`.

Getting this wrong is a loud failure, not a silent one: GitHub rejects a comment on a line outside the diff with HTTP 422. Count carefully rather than estimating.

---

## Phase 3: Order

Order chunks in **implementation order** — the sequence in which someone would actually have built this, which is close to but not identical to dependency order:

1. **Foundations first** — types, data structures, schema, constants. Nothing else compiles without them.
2. **Then leaf logic** — pure functions and helpers that depend only on the foundations.
3. **Then the logic that calls it**, working up the call graph.
4. **Then the wiring** — call sites, routes, DI registration, entry points; the places existing code starts using the new code.
5. **Then tests** for the above.
6. **Last, the trivia** — formatting, project files, config, docs, dependency bumps.

Keep chunks belonging to the same feature contiguous. When a changeset contains two independent features, finish one before starting the other rather than interleaving by layer.

**Exception:** if the PR body specifies a review order, follow it.

---

## Phase 4: Write the document

Write the whole document in one pass — no pausing between chunks. Write it under the repo's `.claude/` directory: `<repo-root>/.claude/pr-<PR_NUMBER>-walkthrough.md` for a PR, or `<repo-root>/.claude/walkthrough-<BASE>-<HEAD>.md` for a branch comparison. The `Write` tool creates `.claude/` if it does not exist.

**Index numbering:** a single sequential counter across the whole document, one number per chunk, in presentation order. Render each as a bold `#N` at the start of the chunk heading so it is easy to scan and quote back.

### Document structure

````markdown
# Walkthrough — <PR #N / base...head> — <title>

[1–3 sentences: what this change does and why]

## Plan

1. **#1** — `<chunk name>` — `path/to/file.ext`
2. **#2** — `<chunk name>` — `path/to/file.ext`
3. …

---

## #1 — <chunk name>

[`path/to/file.ext:<anchorLine>`](https://github.com/<owner>/<repo>/pull/<N>/files#diff-<hash>R<anchorLine>)

```diff
[the diff for this chunk]
```

[1–2 sentence justification: why this change, why this shape]

⚠️ [concern, if any — one or two sentences]

**@username** on line N:
> [review comment body]

---

## #2 — <chunk name>

…

---

## Wrap-up

That's the whole change — <N> chunks across <M> files.

[1–2 sentences: the concerns worth a second look, referenced by chunk ID, or a plain statement that nothing stood out]
````

Rules for each chunk entry:

- Show the diff **before** the justification. The diff is what is being reviewed; the prose explains it.
- Name the chunk after what it is (`withRetry combinator`, `RetryPolicy type`, `import updates across 12 files`), not after the file it lives in.
- **Link the file reference** to the chunk's exact line on the PR, using the anchor from Step 1b plus `R<anchorLine>`. The visible link text is `path/to/file.ext:<anchorLine>` so the location is readable even in a plain-text view.
- Multi-file chunks get one linked reference per path, each pointing at that file's anchor line. When a chunk spans many files, link the two or three that matter and note the rest as `+ 9 more files`.
- For branch comparisons, drop the link and leave `path/to/file.ext:<line>` as plain text.
- Keep the justification to 1–2 sentences. If a chunk genuinely needs a paragraph, that is a sign it should be split.
- Include inline review comments verbatim as blockquotes, attributed to the reviewer.
- Raise concerns inline on the chunk with a ⚠️ prefix — the wrap-up only re-references them by chunk ID.

On a large PR, GitHub collapses or lazy-loads files on the Files tab, so an anchor occasionally lands at the top of the file rather than the exact line. That is a graceful degradation, not a reason to omit the link.

### The Plan section

Every chunk appears in the plan list, one short phrase each, in the same order and with the same indexes as the body. This is the table of contents the user scans to pick a chunk to ask about.

### After writing

Tell the user the path and the chunk count, and that they can ask questions by chunk ID or dictate an inline PR comment with `#N comment: …`. Keep it to a couple of lines — do not restate the document.

---

## Answering Follow-up Questions

The user asks questions prefixed by a chunk ID: "#7 why is the TTL per-call?", "#12 is this actually a race?", "explain #3". Resolve the ID to the chunk that was assigned that index and answer from the full context gathered in Phase 1 — the surrounding file, the call graph, the review comments — not just the diff that appears in the document.

- A question with no ID applies to the whole changeset; answer it that way.
- Several IDs in one question ("compare #4 and #6") is fine — answer across them.
- Answer directly. Do not re-emit the chunk or the document unless asked to show more code.
- Requests to show more code ("#5 show the whole function") are answered with the fuller code, still scoped to that chunk.

---

## Posting Comments and Suggestions Back to the PR

Follow `../../shared/references/pr-interaction.md` — **section 4** (comments), **section 5** (suggested changes and the approval preview), **section 6** (submitting), and **section 7** (failure modes). That document is the authority on the queue format, the two-gate rule, and the submit checklist.

For this skill, an index resolves as follows:

- **`#N`** — chunk `N`. Its `anchorLine` is the default target for a point comment; its `startLine`–`endLine` span is the target for a comment or suggestion covering the whole chunk.
- A chunk spanning several files needs a file named too ("#9 comment on the fsproj: …"). If it is ambiguous, ask which file rather than guessing.

Usage looks like:

> "#7 comment: this timer can be GC'd — nothing roots it but the local"
> "#7 suggest: hold the timer in a field so it isn't collected"

A comment queues immediately; a suggestion is shown for approval first and queues only once the user says so.
---

## Additional Resources

Paths are relative to this skill's directory. `../../shared/` is the plugin-level shared directory, used by both review skills in this plugin.

### Shared — `../../shared/`

- **`../../shared/references/pr-interaction.md`** — the authority on deep links, line-number tracking, queueing comments, writing and previewing suggested changes, submitting, and failure modes. Sections are referenced by number from Phase 1, Phase 2, and "Posting Comments and Suggestions Back to the PR" above.
- **`../../shared/references/dependency-analysis-patterns.md`** — determining the call graph and dependency order across languages, which drives chunking and ordering
- **`../../shared/scripts/`** — `fetch-pr-info.ps1`, `get-comments.ps1`, `diff-anchors.ps1`, `show-lines.ps1`, `submit-review.ps1`. All require PowerShell Core; see section 8 of `pr-interaction.md` for what each does. Always invoke with `pwsh -File "<absolute-path-to-script>"` (not `pwsh "<path>"`) so backslashes in the path are not treated as escapes on Windows.

### Skill-specific — `references/`

- **`references/review-focus-patterns.md`** — what is worth flagging as a concern: security issues, bugs, performance problems, and language-specific suspicious patterns (F# mutation and throwing functions, PureScript `unsafe*`, etc.). This copy is tuned for this skill and intentionally differs from `summarize-review`'s.

### Examples

- **`examples/walkthrough-example.md`** — a worked output document showing the plan, chunk sizing across substantial and trivial changes, inline concerns, and the wrap-up

---

## Workflow Summary

1. **Parse input** → PR number, PR + base, or branches; **with no input, resolve the current branch's open PR** and treat it as a PR review
2. **Gather** → diff, changed files, inline review comments, top-level reviews, head SHA
3. **Anchor** → compute the `#diff-<hash>` anchor for every changed file (PRs only)
4. **Map** → call graph and dependencies among the changed declarations
5. **Chunk** → 1–2 functions for substantial logic, type clusters together, trivia grouped generously; record each chunk's real line range from the hunk headers
6. **Order** → foundations → leaf logic → callers → wiring → tests → trivia
7. **Write** → the full document under `.claude/`, in one pass: purpose, indexed plan, then every chunk (`#N`: linked file reference, diff, justification, review comments, concerns), then the wrap-up
8. **Report the path** → path, chunk count, invitation to ask by chunk ID or dictate comments
9. **Answer follow-ups** → resolve `#N` prefixes to chunks and answer from the gathered context
10. **Queue comments** → `#N comment: …` appends to `.claude/pr-<N>-comments.json`; nothing is sent yet
11. **Write suggestions** → `#N suggest: …` reads the exact lines at the head commit and writes the replacement code as an applicable ` ```suggestion ` block, then **shows it and waits** — it enters the queue only once the user approves
12. **Submit on request** → dry-run, re-check the head SHA, confirm no suggestion is still pending, then post all queued comments as one review
