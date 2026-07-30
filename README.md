# Claude Marketplace

A Claude Code marketplace containing plugins with AI-powered development skills.

## Installation

Install these via 
- `/plugin marketplace add ntwilson/claude-marketplace`
- **optional:** in the Claude Code UI, enable auto-update for the ntwilson marketplace:
  - `/plugin`
  - arrow right to "Marketplaces"
  - select ntw-plugins
  - select "Enable auto-update"
- `/plugin install ntw-plugin@ntw-plugins`

## Skills

Both skills read the same inputs — a PR number, a PR number with an alternative base, or a base/head branch pair — and both write a markdown report under the repo's `.claude/` directory, then answer follow-up questions by index. **Invoked with no input at all, they resolve the open PR for the branch you're on** and review that, so the common case is just `/summarize-review` or `/detailed-review` with nothing after it. They differ in how they slice the changes: `summarize-review` by file and declaration, `detailed-review` by edit-sized chunk in implementation order.

Both also share the same PR-interaction capabilities, defined once in `plugins/ntw-plugin/shared/references/pr-interaction.md`:

- **Deep links** — every indexed item links to its exact line on the PR's Files tab
- **Inline comments** — dictate one against an index; it queues locally and posts as a single review
- **Suggested changes** — describe a fix in prose and get the real replacement code as an applicable GitHub suggestion, shown for your approval before it queues

### summarize-review

A layered review report you drill into by index.

**Contents:**
- Overview: summary and architecture, including a call-graph view of the changed code
- Suspicious items and noteworthy concerns, each indexed `#N`
- File-by-file breakdown in dependency order, each file indexed `#N` with its changed declarations sub-indexed `#N.M`
- Every index deep-linked to its exact line on the PR's Files tab
- Inline PR review comments attached to the file they were left on

**Usage:**
```
"Summarize PR 123"
"Summarize review of PR 456 against develop"
"Give me a layered summary of main to feature-branch"
```

Then: `"tell me more about #19"`, `"is #3 actually a bug?"`, `"explain #12.2"`, `"#7 comment: this will throw on an empty list"`, `"#12.2 suggest: use tryHead instead"`.

See [plugins/ntw-plugin/skills/summarize-review/](plugins/ntw-plugin/skills/summarize-review/).

### detailed-review

Replays a finished changeset as if Claude Code had proposed it edit by edit in Manual Mode.

**Contents:**
- The changeset split into edit-sized chunks — 1–2 functions for substantial logic, trivia grouped generously across files
- Ordered the way the change would actually have been implemented: foundations → leaf logic → callers → wiring → tests → trivia
- Each chunk indexed `#N` with its diff, a 1–2 sentence justification, any concerns, and any inline review comments landing in it
- A deep link on every chunk to its exact line on the PR's Files tab
- An indexed plan list up front and a wrap-up at the end

**Posting comments back:** dictate an inline comment against a chunk (`"#7 comment: this timer can be GC'd"`) and it queues locally. Say `"submit the review"` and all queued comments go up as a single review — one notification, dry-run and confirmation first.

**Suggested changes:** describe a fix in prose (`"#7 suggest: hold the timer so it can't be collected"`) and the actual replacement code gets written for you as a GitHub suggestion block the author can apply with one click. The code is built against the exact text and indentation of the reviewed commit, so it applies cleanly. Since it's generated code, it's shown to you for approval first and only joins the queue once you say so.

**Usage:**
```
"Walk me through PR 123"
"Review PR 456 chunk by chunk"
"Show me main to feature-branch in implementation order"
```

Then: `"#7 why is the TTL per-call?"`, `"#12 is this actually a race?"`, `"compare #4 and #6"`.

See [plugins/ntw-plugin/skills/detailed-review/](plugins/ntw-plugin/skills/detailed-review/).

**Requirements (both skills):**
- GitHub CLI (`gh`) for PR reviews
- Git for branch comparisons
- PowerShell Core (for helper scripts)

## Adding More Skills

Each plugin lives under `plugins/<plugin-name>/` and can contain multiple skills. To add a new skill to an existing plugin:

1. Create a new directory under the plugin's `skills/` folder:
   ```bash
   mkdir -p plugins/ntw-plugin/skills/new-skill-name
   ```

2. Create `SKILL.md` with frontmatter:
   ```markdown
   ---
   name: New Skill Name
   description: This skill should be used when the user asks to "trigger phrase"...
   version: 0.1.0
   ---

   # Skill content
   ```

3. Add supporting resources as needed:
   ```
   plugins/ntw-plugin/skills/new-skill-name/
   ├── SKILL.md
   ├── references/      # Detailed docs
   ├── examples/        # Working examples
   └── scripts/         # Utility scripts
   ```

4. Skills are automatically discovered - no manifest updates needed!

To add an entirely new plugin to the marketplace, create a new directory under `plugins/` with its own `.claude-plugin/plugin.json` manifest.

## Development

### Project Structure

```
claude-marketplace/
├── plugins/
│   └── ntw-plugin/              # A plugin in the marketplace
│       ├── .claude-plugin/
│       │   └── plugin.json      # Plugin manifest
│       ├── shared/                  # Shared by both review skills
│       │   ├── references/
│       │   │   ├── pr-interaction.md               # Links, comments, suggestions, submitting
│       │   │   └── dependency-analysis-patterns.md
│       │   └── scripts/             # gh/PR helper scripts (PowerShell Core)
│       └── skills/
│           ├── summarize-review/    # Layered, indexed review report
│           │   ├── SKILL.md         # Main skill file
│           │   └── references/      # Skill-specific patterns
│           └── detailed-review/     # Chunk-by-chunk implementation-order walkthrough
│               ├── SKILL.md
│               ├── examples/        # Example output document
│               └── references/
├── README.md
└── LICENSE
```

### Testing Locally

```bash
# Install the marketplace from a local path
/plugin marketplace add /path/to/claude-marketplace

# Then install a plugin from it
/plugin install ntw-plugin@ntw-plugins
```

## Contributing

Contributions welcome! To contribute a new skill or plugin:

1. Fork the repository
2. Add a skill to an existing plugin under `plugins/<plugin-name>/skills/`, or create a new plugin under `plugins/`
3. Follow the skill/plugin structure patterns (see existing plugins)
4. Test locally
5. Submit a pull request
