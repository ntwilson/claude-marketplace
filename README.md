# Claude Plugin

A plugin for Claude Code containing personal AI-powered development skills.

## Installation

### From GitHub

```bash
cc plugin add https://github.com/ntwilson/claude-plugin
```

### Local Installation

```bash
git clone https://github.com/ntwilson/claude-plugin ~/.claude/plugins/claude-plugin
```

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

See [skills/help-review/](skills/help-review/) for detailed documentation.

## Adding More Skills

This plugin is designed to grow. To add new skills:

1. Create a new directory in `skills/`:
   ```bash
   mkdir -p skills/new-skill-name
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
   skills/new-skill-name/
   ├── SKILL.md
   ├── references/      # Detailed docs
   ├── examples/        # Working examples
   └── scripts/         # Utility scripts
   ```

4. Skills are automatically discovered - no manifest updates needed!

## Development

### Project Structure

```
claude-plugin/
├── .claude-plugin/
│   └── plugin.json      # Plugin manifest
├── skills/
│   └── help-review/     # Code review skill
│       ├── SKILL.md     # Main skill file
│       ├── examples/    # Example outputs
│       ├── references/  # Detailed patterns
│       └── scripts/     # Helper scripts
├── README.md
└── LICENSE
```

### Testing Locally

```bash
# Test the plugin
cc --plugin-dir /path/to/claude-plugin

# Or symlink to plugins directory
ln -s /path/to/claude-plugin ~/.claude/plugins/claude-plugin
```

## Contributing

Contributions welcome! To contribute a new skill:

1. Fork the repository
2. Create a new skill directory in `skills/`
3. Follow the skill structure pattern (see existing skills)
4. Test thoroughly
5. Submit a pull request

## License

MIT - See [LICENSE](LICENSE) file

## Version

Current version: 0.1.0

## Roadmap

Future skills planned:
- Test generation assistance
- API documentation generation
- Performance analysis
- Security audit helpers
- Refactoring assistance

Suggestions welcome via issues!
