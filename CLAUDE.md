# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Claude Code plugin marketplace. The marketplace manifest is `.claude-plugin/marketplace.json`, which lists available plugins. Each plugin lives under `plugins/<plugin-name>/` with its own `.claude-plugin/plugin.json` manifest and a `skills/` directory containing one or more skills.

Currently contains one plugin (`ntw-plugin`) with one skill (`help-review`).

## Architecture

```
.claude-plugin/marketplace.json        # Marketplace manifest (lists plugins)
plugins/<plugin-name>/
  .claude-plugin/plugin.json           # Plugin manifest (name, version, description)
  skills/<skill-name>/
    SKILL.md                           # Skill definition (frontmatter + instructions)
    references/                        # Detailed reference docs
    examples/                          # Example outputs
    scripts/                           # Helper scripts
```

- Skills are auto-discovered from the `skills/` directory structure; no manifest update is needed when adding a new skill.
- `SKILL.md` frontmatter (`name`, `description`, `version`) defines how Claude Code discovers and triggers the skill.
- The `description` field in SKILL.md frontmatter is what Claude Code uses to match user requests to skills, so it should include trigger phrases.

## Testing Locally

```bash
# Install marketplace from local path
/plugin marketplace add /path/to/claude-marketplace

# Install a plugin from it
/plugin install ntw-plugin@ntw-plugins
```

## Adding a New Skill

1. Create `plugins/<plugin-name>/skills/<skill-name>/SKILL.md` with frontmatter (`name`, `description`, `version`)
2. Add `references/`, `examples/`, `scripts/` subdirectories as needed
3. No manifest changes required

## Adding a New Plugin

1. Create `plugins/<new-plugin>/` with a `.claude-plugin/plugin.json` manifest
2. Add the plugin entry to `.claude-plugin/marketplace.json`
3. Add skills under `plugins/<new-plugin>/skills/`

## Key Conventions

- Helper scripts are written in PowerShell Core for cross-platform support (Windows/Linux/macOS)
- Skills that interact with GitHub PRs use the `gh` CLI
- Summaries in skill output use dependency order (callees before callers) by default
