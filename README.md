# claude-config

My [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration - settings and skills.

## Quick start

```bash
git clone https://github.com/brianlovin/claude-config.git
cd claude-config
./install.sh
```

## What's included

### Settings
- `settings.json` - Global permissions and preferences
- `statusline.sh` - Custom statusline showing token usage

### Skills
Reusable capabilities that Claude can invoke (use `/skill-name` in Claude):

| Skill | Description |
|-------|-------------|
| `agent-browser` | Browser automation for web testing and interaction |
| `favicon` | Generate favicons from a source image |
| `knip` | Find and remove unused files, dependencies, and exports |
| `rams` | Run accessibility and visual design review |
| `reclaude` | Refactor CLAUDE.md files for progressive disclosure |
| `simplify` | Code simplification specialist |
| `deslop` | Remove AI-generated code slop |

## Managing your config

```bash
# See what's synced vs local-only
./sync.sh

# Preview what install would do
./install.sh --dry-run

# Add a local skill to the repo
./sync.sh add skill my-skill
./sync.sh push

# Pull changes on another machine
./sync.sh pull

# Remove a skill from repo (keeps local copy)
./sync.sh remove skill my-skill
./sync.sh push
```

### Safe operations with backups

All destructive operations create timestamped backups:

```bash
# List available backups
./sync.sh backups

# Restore from last backup
./sync.sh undo
```

### Validate skills

```bash
./sync.sh validate
```

Skills must have a `SKILL.md` with frontmatter containing `name` and `description`.

## Testing

Tests use [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

```bash
# Install bats (one-time)
brew install bats-core

# Run all tests
bats tests/

# Run specific test file
bats tests/install.bats
bats tests/sync.bats
bats tests/validation.bats
```

Tests run in isolated temp directories and don't affect your actual `~/.claude` config.

## Local-only config

Not everything needs to be synced. The install script only creates symlinks for what's in this repo - it won't delete your local-only skills.

Machine-specific permissions accumulate in `~/.claude/settings.local.json` (auto-created by Claude, not synced).

## Creating your own

Fork this repo and customize! The structure is simple:

```
claude-config/
├── settings.json      # Claude Code settings
├── statusline.sh      # Optional statusline script
├── skills/            # Skills (subdirectories with SKILL.md)
├── agents/            # Subagent definitions
├── rules/             # Rule files
└── tests/             # Bats tests
```

## See also

- [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code)
- [My dotfiles](https://github.com/brianlovin/dotfiles) - Shell, git, SSH config
