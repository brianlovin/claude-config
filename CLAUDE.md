# Claude Config

Personal Claude Code settings, skills, agents, and rules, synced across machines via symlinks.

## Commands

```bash
./install.sh              # Set up symlinks (run after cloning)
./install.sh --dry-run    # Preview what would be done
./sync.sh                 # Show sync status
./sync.sh add <type> <name>     # Add a local item to repo
./sync.sh remove <type> <name>  # Remove item from repo (keeps local)
./sync.sh pull            # Pull latest and reinstall symlinks
./sync.sh push            # Commit and push changes
./sync.sh undo            # Restore from last backup
./sync.sh validate        # Validate all skills
./sync.sh backups         # List available backups
bats tests/               # Run tests
```

Types: `skill`, `agent`, `rule`

## Testing

Tests use Bats. Run `bats tests/` to execute all tests. Tests run in isolated temp directories.

See [.claude/rules/testing.md](.claude/rules/testing.md) for testing conventions.

## Key Files

- `install.sh` - Creates symlinks from ~/.claude to this repo
- `sync.sh` - Manages syncing items between local and repo
- `tests/` - Bats test suite

For detailed workflows, see [.claude/rules/workflows.md](.claude/rules/workflows.md).
