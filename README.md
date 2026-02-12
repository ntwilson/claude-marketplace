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

### help-review

Provides hierarchical, dependency-ordered code review summaries.

**Features:**
- Hierarchical summaries from overall changes → files → modules → functions
- Dependency ordering (callees before callers)
- Multi-format input: PR numbers, PR with custom base, or branch comparisons
- Review focus highlighting suspicious code and priority areas
- Cross-platform PowerShell scripts

**Usage:**
```
"Help review PR 123"
"Review PR 456 against develop"
"Review changes from main to feature-branch"
```

**Output structure:**
```markdown
# Code Review Summary

## Overall Changes
[1-2 sentence summary]

## Files Changed (in dependency order)
### `file.ext`
[File summary]

#### Function: `functionName(params): returnType`
[Function change summary]

## Review Focus
### ⚠️ Items Requiring Attention
- [Security/bugs/breaking changes]

### 📍 Priority Files/Functions
- **`file:function`** - [Why it needs review]
```

**Input formats:**
1. PR number only: `"Review PR 123"`
2. PR with alternative base: `"Review PR 123 against develop"`
3. Branch comparison: `"Review changes from main to feature-auth"`

**Requirements:**
- GitHub CLI (`gh`) for PR reviews
- Git for branch comparisons
- PowerShell Core (for helper scripts)

See [plugins/ntw-plugin/skills/help-review/](plugins/ntw-plugin/skills/help-review/) for detailed documentation.

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
│       └── skills/
│           └── help-review/     # Code review skill
│               ├── SKILL.md     # Main skill file
│               ├── examples/    # Example outputs
│               ├── references/  # Detailed patterns
│               └── scripts/     # Helper scripts
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
