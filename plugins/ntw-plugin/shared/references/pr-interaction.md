# PR Interaction: Deep Links, Inline Comments, and Suggested Changes

Shared protocol for review skills in this plugin. It covers linking each reported item to its exact line on the PR, and posting comments and suggested code changes back.

Each skill defines its own **indexed items** (`#N`, `#N.M`, …) and how an index maps to a `path` plus a line range. Everything below operates on that mapping, so it applies unchanged to any skill that provides it.

Scripts referenced here live in `../scripts/` relative to this file — i.e. `<plugin-root>/shared/scripts/`. From a skill directory that is `../../shared/scripts/`. Always invoke with `pwsh -File "<absolute-path>"` (not `pwsh "<path>"`) so backslashes in a Windows path are not treated as escapes.

---

## 0. Resolving the target when the user gives no input

When a skill is invoked with no PR number and no branch names, **assume the current branch has an open PR and review that PR.** Do not fall straight through to a working-diff comparison, and do not ask which PR — resolve it.

```bash
git branch --show-current
gh pr view --json number,title,body,baseRefName,headRefName,headRefOid,files
```

`gh pr view` with no argument resolves the PR for the current branch. On success, proceed exactly as if the user had typed that PR number — say which PR was resolved in one line (`Reviewing PR #123 — <title>`) so a wrong guess is visible immediately.

If it exits non-zero (`no pull requests found for branch "<name>"`), find out why before falling back:

```bash
gh pr list --head <branch> --state all --json number,state,title
```

- **A closed or merged PR exists** — name it and its state, then ask whether to review it anyway or diff against the default branch. A merged PR is still reviewable; the user may well want it.
- **Nothing at all** — say so, then fall back to comparing the current branch against the default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`). State the fallback explicitly; deep links and comment posting are unavailable without a PR, so the report will be plain text.
- **On the default branch, or detached HEAD** — there is no branch to resolve a PR from. Say so and review the uncommitted working diff instead.

---

## 1. Setup during information gathering

Capture two extra things while fetching the PR:

**The head commit SHA** — add `headRefOid` to the `gh pr view --json` field list. Links and posted comments are anchored to it, so both point at the code that was actually reviewed.

**The diff anchors.** GitHub anchors each file on a PR's Files tab as `#diff-<sha256 of the repo-relative path>`; appending `R<line>` targets a line on the right (new) side, `L<line>` the left (old) side. Compute all of them in one call:

```bash
pwsh -File ../../shared/scripts/diff-anchors.ps1 -Owner <owner> -Repo <repo> -Pr <PR_NUMBER> -Path "<path1>,<path2>,..."
```

Keep the returned base URL per file. Per-item links are then string concatenation: append `R<line>`.

Both are PR-only. Skip them for branch comparisons — there is no PR to link into.

---

## 2. Tracking line numbers

Diff text does not carry line numbers; they have to be counted out of each hunk header. For a hunk `@@ -a,b +c,d @@`:

- The right (new) side starts at line **`c`**; the left (old) side starts at line **`a`**.
- Walk the hunk body. Context lines (leading space) and added lines (`+`) each advance the right-side counter. Removed lines (`-`) do **not** — they exist only on the left side.
- To count left-side lines instead, advance on context and `-` lines, and skip `+`.

Worked example — for `@@ -1,6 +1,6 @@`:

```
 {                            <- R1  (context)
   "name": "ntw-plugin",      <- R2  (context)
-  "version": "0.5.0",        <- (left side only, does not advance R)
+  "version": "0.6.0",        <- R3  (added)
   "description": "...",      <- R4  (context)
```

Record for each indexed item:

- **`anchorLine`** — the first added or changed right-side line in the item. This is what the item's link points at.
- **`startLine` / `endLine`** — the item's full right-side span, used for multi-line comments and suggestions.
- **`side`** — `RIGHT` normally. For an item that is purely deletions there is no right-side line, so use the left-side number and `LEFT`.

Getting this wrong is a loud failure, not a silent one: GitHub rejects a comment on a line outside the diff with HTTP 422. Count carefully rather than estimating.

---

## 3. Linking items in the written report

Render each item's file reference as a link to its exact line:

```markdown
[`path/to/file.ext:<anchorLine>`](https://github.com/<owner>/<repo>/pull/<N>/files#diff-<hash>R<anchorLine>)
```

- The visible link text is `path/to/file.ext:<anchorLine>` so the location stays readable in a plain-text view.
- An item spanning several files gets one linked reference per path, each pointing at that file's anchor line. When there are many, link the two or three that matter and note the rest as `+ 9 more files`.
- For branch comparisons, drop the link and leave `path/to/file.ext:<line>` as plain text.

On a large PR, GitHub collapses or lazy-loads files on the Files tab, so an anchor occasionally lands at the top of the file rather than the exact line. That is a graceful degradation, not a reason to omit the link.

---

## 4. Posting comments back to the PR

The user can dictate an inline review comment against any indexed item instead of switching to the GitHub UI:

> "#7 comment: this timer can be GC'd — nothing roots it but the local"

Comments **accumulate in a local queue and are submitted as a single review**, so reviewers get one notification rather than one per comment. Nothing is sent until the user explicitly asks to submit.

Two gates, for two different reasons:

| | Queued | Submitted |
|---|---|---|
| **Plain comment** — the user's own words | immediately | on explicit request |
| **Suggested change** — code you wrote | only after the user approves the preview | on explicit request |

### Queueing

Maintain the queue as a JSON array at `<repo-root>/.claude/pr-<PR_NUMBER>-comments.json`, written with the `Write` tool. Each entry:

```json
{
  "path": "src/App.fs",
  "line": 42,
  "side": "RIGHT",
  "start_line": 38,
  "body": "..."
}
```

- `path` and `line` come from the item's recorded line range — `line` is its `anchorLine` for a point comment.
- To cover a whole item, set `start_line` to its `startLine` and `line` to its `endLine`. `start_line` must be ≤ `line`.
- `side` is `RIGHT` unless the item is pure deletions, in which case `LEFT` with the left-side numbers.
- Write the comment in the user's voice — their words are the substance. Tighten wording and add a code reference if it helps a reader who is not in this conversation, but do not editorialize or add opinions they did not express.

After queueing, confirm in one line: the item, the resolved `path:line`, and the queue depth. Do not restate the body.

The user can amend the queue before submitting — "drop the comment on #7", "reword #3's comment", "show me the queue". Rewrite the JSON accordingly.

---

## 5. Writing suggested changes

The user can describe a change in prose and have the actual code written for them, posted as a GitHub suggested change that the author can apply with one click:

> "#7 suggest: hold the timer in a field so it isn't collected"

The user supplies the intent; you supply the code. Steps:

1. **Narrow the range to what actually changes.** The replaced range is usually smaller than the whole item — only the lines the edit touches. A suggestion that restates unchanged lines is noise and conflicts more easily.
2. **Read the exact current text at the reviewed commit:**
   ```bash
   pwsh -File ../../shared/scripts/show-lines.ps1 -Sha <headRefOid> -Path <path> -Start <n> -End <m>
   ```
   Never build a suggestion from the diff text — the `+`/`-` prefixes are not part of the file. Never build it from the working tree either; it may be a different commit or dirty. Use `-Raw` to get the lines with no numbering.
3. **Write the full replacement for that range** — every line in it, not only the changed ones. Anything you omit gets deleted when the author applies it.
4. **Preserve indentation exactly.** GitHub applies leading whitespace literally, and the block carries no diff prefix to absorb a mistake. Match the file's existing tabs/spaces and nesting depth.
5. **Follow the repo's language conventions** — the suggestion is real code that will be committed as-is. Use the relevant conventions skill (`fsharp-conventions`, `purescript-conventions`, `python-conventions`) if one applies.
6. **Anchor it:** `start_line` = first replaced line, `line` = last replaced line (omit `start_line` for a single line), `side` = `RIGHT`. Suggestions cannot be applied to deleted lines, so `LEFT` is rejected.
7. **Show it to the user and wait for approval before queueing it.** See below — this step is not optional.

The replacement does **not** need the same number of lines as the range it replaces — replacing 2 lines with 3, or 5 with 1, is fine.

### Suggestion body format

One or two sentences of why, then exactly one suggestion block:

````markdown
The timer is rooted only by this local, so it can be collected mid-run.

```suggestion
  let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
  timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
  { Cache = cache; EvictionTimer = timer }
```
````

- **One suggestion block per comment.** GitHub applies only one, so a second change to a different range is a second queued comment.
- The replacement must actually differ from the current text — an identical suggestion is rejected as inapplicable.
- Keep it minimal and in the file's style. This is a review suggestion, not a refactor.

When a change cannot be expressed as a suggestion — it spans non-contiguous regions, needs a new file, or requires edits outside the diff — queue a plain comment describing it instead, and say why a suggestion wasn't used.

### Previewing a suggestion before it is queued

A plain comment is queued immediately: the user wrote those words, so there is nothing for them to check. A suggestion is different — **you** wrote the code, and applying it commits it. So a suggestion is **never added to the queue file until the user has seen it and approved it.**

Display the resolved suggestion in full and stop:

````markdown
**Pending suggestion on #7** — `OneInN/Program.fs:24–27` (RIGHT) — *not queued yet*

Replacing lines 24–27, currently:

```fsharp
    let cache = CacheManager.createCache()
    let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
    timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
    cache
```

The comment body that would be posted:

```suggestion
    let cache = CacheManager.createCache()
    let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
    timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
    { Cache = cache; EvictionTimer = timer }
```

Say **queue it** to add this to the review, or tell me what to change.
````

Rules for the preview:

- Show the **current lines** (verbatim from `show-lines.ps1`) and the **exact body** that would be posted, including the fence. Do not paraphrase either — a translation layer is somewhere an indentation error can hide.
- State the resolved `path:start–end` and `side` so the anchor can be checked, and label it plainly as not yet queued.
- Show the prose part of the body too if it is more than a sentence.
- Preview **one suggestion at a time**. If the user asks for several at once, resolve and present them one after another, each with its own approval.

Handling the response:

- **"queue it"**, "yes", "looks good" → write it to the queue file, then confirm the item, resolved range, and new queue depth in one line.
- **Any correction** ("use a `use` binding instead", "keep it on one line") → rewrite and re-show the full preview. Still not queued.
- **"drop it"**, "never mind" → discard; the queue is untouched.
- **The user changes subject without answering** → leave it pending, do not queue it. If they later ask to submit, list any pending-but-unapproved suggestions and ask before submitting anything.

Never queue a suggestion as a side effect of writing it, and never submit a review containing a suggestion the user has not seen.

---

## 6. Submitting

Only when the user asks to submit ("submit the review", "send those comments"):

```bash
pwsh -File ../../shared/scripts/submit-review.ps1 -Owner <owner> -Repo <repo> -Pr <PR_NUMBER> `
  -CommentsFile "<repo-root>/.claude/pr-<PR_NUMBER>-comments.json" `
  -CommitId <headRefOid> -Body "<optional review-level summary>" -Event COMMENT
```

1. **Always dry-run first** (`-DryRun`) and show the user the resolved payload — path, line, and side for every comment. This is their last chance to catch a mis-anchored line.
2. **Re-check the head SHA** before submitting: `gh pr view <N> --json headRefOid`. If it no longer matches the `headRefOid` captured during gathering, the PR has been pushed to since the report was written. Say so — line numbers may have moved, and the comments will show as outdated against the reviewed commit.
   Also check for any **pending suggestion** the user never approved. Name it and ask; do not silently include or drop it.
3. **Confirm explicitly.** Submitting notifies every reviewer immediately and cannot be undone from here. Never submit as a side effect of queueing.
4. Report the returned review URL.
5. Clear the queue file after a successful submit so a later comment starts a fresh review.

`-Event` defaults to `COMMENT`. Use `REQUEST_CHANGES` or `APPROVE` only when the user says so in as many words.

---

## 7. Failure modes

- **HTTP 422** — a commented line is not part of the diff. GitHub only accepts inline comments on added, removed, or nearby-context lines. Re-derive the line from the hunk header (section 2) rather than nudging the number and retrying.
- **Comment lands on the wrong line** — the right-side counting skipped or double-counted a `-` line. Recount the whole hunk.
- **Empty queue** — the script exits non-zero rather than posting an empty review.
- **Suggestion has no "Apply" button** — the block is malformed: the fence must be exactly ` ```suggestion `, and it must be closed. `submit-review.ps1` catches an unterminated fence, a `LEFT`-side anchor, and more than one block per comment before posting.
- **Applying the suggestion mangles indentation** — the replacement was written with the diff's `+` prefix still attached, or against the working tree rather than the reviewed commit. Rebuild it from `show-lines.ps1`.
- **Applying the suggestion deletes a line that should have stayed** — the replacement omitted a line inside the anchored range. The block must contain the whole range.

---

## 8. Scripts

- **`../scripts/fetch-pr-info.ps1`** — fetches PR information via the `gh` CLI.
- **`../scripts/get-comments.ps1`** — fetches existing inline diff comments and formats them as `FILE | LINE | USER` / `BODY` blocks. Example: `pwsh -File "<path>/get-comments.ps1" -url "repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments"`
- **`../scripts/diff-anchors.ps1`** — computes the `#diff-<sha256(path)>` anchor for each changed file, optionally as a full PR URL. Call once with every changed path; append `R<line>`/`L<line>` per item. Accepts either `-Path a,b,c` or `-Path a b c`.
- **`../scripts/show-lines.ps1`** — prints an exact, numbered line range from a file **at a specific commit** (`-Sha`), so a suggested change can be built against the precise text and indentation being reviewed rather than the working tree. `-Raw` omits the numbering for pasting straight into a suggestion block.
- **`../scripts/submit-review.ps1`** — validates a queued-comment JSON file and posts all of it as one review in a single API call. Supports `-DryRun`, `-CommitId` to pin the review to the reviewed commit, and `-Event` for `COMMENT`/`REQUEST_CHANGES`/`APPROVE`. Validates every entry before touching the network, since a partly-posted batch is worse than none.
