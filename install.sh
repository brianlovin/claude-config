#!/bin/bash
set -e

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$CONFIG_DIR/.backup"
DRY_RUN=false
FORCE=false

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./install.sh [options]"
            echo ""
            echo "Options:"
            echo "  -n, --dry-run  Show what would be done without making changes"
            echo "  -f, --force    Overwrite conflicts without prompting"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Create backup with timestamp
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$timestamp"
    mkdir -p "$backup_path"
    echo "$backup_path"
}

# Backup a file or directory
backup_item() {
    local src="$1"
    local backup_path="$2"
    local relative_path="${src#$HOME/}"
    local dest="$backup_path/$relative_path"

    mkdir -p "$(dirname "$dest")"
    if [ -L "$src" ]; then
        # For symlinks, store the target
        echo "$(readlink "$src")" > "$dest.symlink"
    elif [ -d "$src" ]; then
        cp -r "$src" "$dest"
    else
        cp "$src" "$dest"
    fi
}

# Write manifest
write_manifest() {
    local backup_path="$1"
    local operation="$2"
    shift 2
    local items=("$@")

    cat > "$backup_path/manifest.json" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "operation": "$operation",
    "items": [$(printf '"%s",' "${items[@]}" | sed 's/,$//')],
    "user": "$USER",
    "hostname": "$(hostname)"
}
EOF
}

# Check if item has conflict (exists locally and is not a symlink to our repo)
has_conflict() {
    local path="$1"
    if [ -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi
    if [ -L "$path" ]; then
        local target=$(readlink "$path")
        if [[ "$target" != "$CONFIG_DIR"* ]]; then
            return 0
        fi
    fi
    return 1
}

# Handle conflict interactively
handle_conflict() {
    local src="$1"
    local dest="$2"
    local backup_path="$3"
    local item_name="$4"

    if $FORCE; then
        backup_item "$dest" "$backup_path"
        return 0  # Proceed with overwrite
    fi

    echo ""
    echo -e "${YELLOW}Conflict:${RESET} $item_name exists locally and differs from repo"
    echo "  Local: $dest"
    echo "  Repo:  $src"
    echo ""
    echo "Options:"
    echo "  [r] Use repo version (backup local)"
    echo "  [l] Keep local version (skip)"
    echo "  [d] Show diff"
    echo "  [q] Quit"

    while true; do
        read -p "Choice [r/l/d/q]: " choice
        case $choice in
            r|R)
                backup_item "$dest" "$backup_path"
                return 0  # Proceed with overwrite
                ;;
            l|L)
                return 1  # Skip this item
                ;;
            d|D)
                echo ""
                if [ -d "$src" ]; then
                    diff -r "$dest" "$src" 2>/dev/null || true
                else
                    diff "$dest" "$src" 2>/dev/null || true
                fi
                echo ""
                ;;
            q|Q)
                echo "Aborted."
                exit 1
                ;;
            *)
                echo "Invalid choice. Use r, l, d, or q."
                ;;
        esac
    done
}

# Dry run output
dry_run_msg() {
    echo -e "${BLUE}[dry-run]${RESET} $1"
}

# Main installation
main() {
    if $DRY_RUN; then
        echo -e "${BOLD}Dry run - showing what would be done:${RESET}"
        echo ""
    else
        echo "Installing Claude Code config from $CONFIG_DIR"
        echo ""
    fi

    local backup_path=""
    local backed_up_items=()
    local has_changes=false

    if ! $DRY_RUN; then
        mkdir -p ~/.claude
    fi

    # Settings
    if [ -f "$CONFIG_DIR/settings.json" ]; then
        if $DRY_RUN; then
            if has_conflict ~/.claude/settings.json; then
                dry_run_msg "Would backup and replace ~/.claude/settings.json"
            else
                dry_run_msg "Would link settings.json"
            fi
        else
            if has_conflict ~/.claude/settings.json; then
                [ -z "$backup_path" ] && backup_path=$(create_backup)
                if handle_conflict "$CONFIG_DIR/settings.json" ~/.claude/settings.json "$backup_path" "settings.json"; then
                    backed_up_items+=("settings.json")
                    rm -rf ~/.claude/settings.json
                    ln -sf "$CONFIG_DIR/settings.json" ~/.claude/settings.json
                    echo -e "${GREEN}✓${RESET} settings.json (replaced, backup saved)"
                    has_changes=true
                else
                    echo -e "${YELLOW}○${RESET} settings.json (kept local)"
                fi
            else
                ln -sf "$CONFIG_DIR/settings.json" ~/.claude/settings.json
                echo -e "${GREEN}✓${RESET} settings.json"
                has_changes=true
            fi
        fi
    fi

    # Statusline
    if [ -f "$CONFIG_DIR/statusline.sh" ]; then
        if $DRY_RUN; then
            if has_conflict ~/.claude/statusline.sh; then
                dry_run_msg "Would backup and replace ~/.claude/statusline.sh"
            else
                dry_run_msg "Would link statusline.sh"
            fi
        else
            if has_conflict ~/.claude/statusline.sh; then
                [ -z "$backup_path" ] && backup_path=$(create_backup)
                if handle_conflict "$CONFIG_DIR/statusline.sh" ~/.claude/statusline.sh "$backup_path" "statusline.sh"; then
                    backed_up_items+=("statusline.sh")
                    rm -rf ~/.claude/statusline.sh
                    ln -sf "$CONFIG_DIR/statusline.sh" ~/.claude/statusline.sh
                    echo -e "${GREEN}✓${RESET} statusline.sh (replaced, backup saved)"
                    has_changes=true
                else
                    echo -e "${YELLOW}○${RESET} statusline.sh (kept local)"
                fi
            else
                ln -sf "$CONFIG_DIR/statusline.sh" ~/.claude/statusline.sh
                echo -e "${GREEN}✓${RESET} statusline.sh"
                has_changes=true
            fi
        fi
    fi

    # Skills (directory symlinks per skill)
    if [ -d "$CONFIG_DIR/skills" ] && [ -n "$(ls -A "$CONFIG_DIR/skills" 2>/dev/null)" ]; then
        mkdir -p ~/.claude/skills
        for skill in "$CONFIG_DIR/skills"/*/; do
            [ -d "$skill" ] || continue
            skill_name=$(basename "$skill")
            local dest=~/.claude/skills/"$skill_name"

            if $DRY_RUN; then
                if has_conflict "$dest"; then
                    dry_run_msg "Would backup and replace skills/$skill_name"
                else
                    dry_run_msg "Would link skills/$skill_name"
                fi
            else
                if has_conflict "$dest"; then
                    [ -z "$backup_path" ] && backup_path=$(create_backup)
                    if handle_conflict "$skill" "$dest" "$backup_path" "skills/$skill_name"; then
                        backed_up_items+=("skills/$skill_name")
                        rm -rf "$dest"
                        ln -sfn "$skill" "$dest"
                        echo -e "${GREEN}✓${RESET} skills/$skill_name (replaced, backup saved)"
                        has_changes=true
                    else
                        echo -e "${YELLOW}○${RESET} skills/$skill_name (kept local)"
                    fi
                else
                    ln -sfn "$skill" "$dest"
                    echo -e "${GREEN}✓${RESET} skills/$skill_name"
                    has_changes=true
                fi
            fi
        done
    fi

    # Agents (file symlinks per agent)
    if [ -d "$CONFIG_DIR/agents" ] && ls "$CONFIG_DIR/agents"/*.md &>/dev/null; then
        mkdir -p ~/.claude/agents
        for agent in "$CONFIG_DIR/agents"/*.md; do
            [ -f "$agent" ] || continue
            agent_name=$(basename "$agent")
            local dest=~/.claude/agents/"$agent_name"

            if $DRY_RUN; then
                if has_conflict "$dest"; then
                    dry_run_msg "Would backup and replace agents/$agent_name"
                else
                    dry_run_msg "Would link agents/$agent_name"
                fi
            else
                if has_conflict "$dest"; then
                    [ -z "$backup_path" ] && backup_path=$(create_backup)
                    if handle_conflict "$agent" "$dest" "$backup_path" "agents/$agent_name"; then
                        backed_up_items+=("agents/$agent_name")
                        rm -rf "$dest"
                        ln -sf "$agent" "$dest"
                        echo -e "${GREEN}✓${RESET} agents/$agent_name (replaced, backup saved)"
                        has_changes=true
                    else
                        echo -e "${YELLOW}○${RESET} agents/$agent_name (kept local)"
                    fi
                else
                    ln -sf "$agent" "$dest"
                    echo -e "${GREEN}✓${RESET} agents/$agent_name"
                    has_changes=true
                fi
            fi
        done
    fi

    # Rules (file symlinks per rule)
    if [ -d "$CONFIG_DIR/rules" ] && ls "$CONFIG_DIR/rules"/*.md &>/dev/null; then
        mkdir -p ~/.claude/rules
        for rule in "$CONFIG_DIR/rules"/*.md; do
            [ -f "$rule" ] || continue
            rule_name=$(basename "$rule")
            local dest=~/.claude/rules/"$rule_name"

            if $DRY_RUN; then
                if has_conflict "$dest"; then
                    dry_run_msg "Would backup and replace rules/$rule_name"
                else
                    dry_run_msg "Would link rules/$rule_name"
                fi
            else
                if has_conflict "$dest"; then
                    [ -z "$backup_path" ] && backup_path=$(create_backup)
                    if handle_conflict "$rule" "$dest" "$backup_path" "rules/$rule_name"; then
                        backed_up_items+=("rules/$rule_name")
                        rm -rf "$dest"
                        ln -sf "$rule" "$dest"
                        echo -e "${GREEN}✓${RESET} rules/$rule_name (replaced, backup saved)"
                        has_changes=true
                    else
                        echo -e "${YELLOW}○${RESET} rules/$rule_name (kept local)"
                    fi
                else
                    ln -sf "$rule" "$dest"
                    echo -e "${GREEN}✓${RESET} rules/$rule_name"
                    has_changes=true
                fi
            fi
        done
    fi

    echo ""

    if $DRY_RUN; then
        echo "Run without --dry-run to apply changes."
    else
        if [ -n "$backup_path" ] && [ ${#backed_up_items[@]} -gt 0 ]; then
            write_manifest "$backup_path" "install" "${backed_up_items[@]}"
            echo -e "${BLUE}Backup saved:${RESET} $backup_path"
            echo "Run './sync.sh undo' to restore."
            echo ""
        fi

        echo "Done! Claude Code config installed."
        echo ""
        echo "Local-only items in ~/.claude/ are preserved."
        echo "Use ./sync.sh to manage what gets shared."
    fi
}

main
