# Workflows

## Setting up on a new machine

```bash
git clone git@github.com:brianlovin/claude-config.git ~/Developer/claude-config
cd ~/Developer/claude-config
./install.sh
```

Creates symlinks from `~/.claude/` to this repo. Local-only items are preserved.

### Dry-run mode

Preview what would happen without making changes:

```bash
./install.sh --dry-run
```

### Handling conflicts

If a local file differs from the repo version, you'll be prompted:
- `[r]` Use repo version (backs up local first)
- `[l]` Keep local version (skip this item)
- `[d]` Show diff between versions
- `[q]` Quit

Use `--force` to automatically use repo versions (still creates backups).

## Sync status legend

```bash
./sync.sh
```

Shows status grouped by type (Skills, Agents, Rules):

- `✓` synced (symlinked to this repo)
- `○` local only (not in repo)
- `⚠` conflict (exists in both - run `./install.sh` to fix)
- `→` external (symlinked elsewhere)

## Adding items to sync across machines

```bash
./sync.sh add skill <name>   # Add a skill directory
./sync.sh add agent <name>   # Add an agent file (without .md extension)
./sync.sh add rule <name>    # Add a rule file (without .md extension)
./sync.sh push
```

Copies the item to repo, replaces local with symlink, prompts for commit.

Skills are validated before adding - must have SKILL.md with `name` and `description` in frontmatter.

## Removing items from repo

```bash
./sync.sh remove skill <name>
./sync.sh remove agent <name>
./sync.sh remove rule <name>
./sync.sh push
```

Removes from repo but keeps local copy.

## Backups and undo

All destructive operations create timestamped backups in `.backup/`.

```bash
./sync.sh backups            # List available backups
./sync.sh undo               # Restore from last backup
./sync.sh undo --dry-run     # Preview what would be restored
```

## Validating skills

Check that all skills have valid SKILL.md files:

```bash
./sync.sh validate
```

Skills must have frontmatter with `name` and `description`:

```yaml
---
name: my-skill
description: What this skill does
---
```

## Dry-run mode

Preview any command without making changes:

```bash
./sync.sh --dry-run add skill my-skill
./sync.sh -n remove agent my-agent
./install.sh --dry-run
```

## Keeping items local-only

Any item in `~/.claude/` that isn't symlinked stays local. The install script only creates symlinks for what's in this repo—it never deletes local files.

Use this for work-specific or experimental items.

## Directory structure

```
~/.claude/
├── skills/          # Skill directories (each has SKILL.md)
├── agents/          # Subagent markdown files
├── rules/           # Rule markdown files
├── settings.json
└── statusline.sh
```
