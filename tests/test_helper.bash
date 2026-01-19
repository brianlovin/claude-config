#!/bin/bash
# Test helper for claude-config tests
# Provides setup/teardown and utility functions

# Get the directory containing the test files
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

# Create isolated test environment
setup_test_env() {
    # Create temporary directories
    export TEST_TMP="$(mktemp -d)"
    export FAKE_HOME="$TEST_TMP/home"
    export FAKE_REPO="$TEST_TMP/repo"

    mkdir -p "$FAKE_HOME/.claude"
    mkdir -p "$FAKE_REPO"

    # Copy scripts to fake repo
    cp "$PROJECT_DIR/install.sh" "$FAKE_REPO/"
    cp "$PROJECT_DIR/sync.sh" "$FAKE_REPO/"

    # Make scripts use fake HOME
    # We'll override HOME when running scripts
    export ORIGINAL_HOME="$HOME"
    export HOME="$FAKE_HOME"

    # Change to fake repo
    cd "$FAKE_REPO"
}

# Clean up test environment
teardown_test_env() {
    # Restore original HOME
    export HOME="$ORIGINAL_HOME"

    # Remove temporary directory
    if [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

# Create a fake skill with valid SKILL.md
create_fake_skill() {
    local name="$1"
    local location="${2:-$FAKE_REPO/skills}"

    mkdir -p "$location/$name"
    cat > "$location/$name/SKILL.md" << EOF
---
name: $name
description: A test skill called $name
---

# $name

This is a test skill.
EOF
}

# Create a fake skill with invalid SKILL.md (missing frontmatter)
create_invalid_skill() {
    local name="$1"
    local location="${2:-$FAKE_REPO/skills}"

    mkdir -p "$location/$name"
    cat > "$location/$name/SKILL.md" << EOF
# $name

This skill has no frontmatter.
EOF
}

# Create a fake skill with missing SKILL.md
create_skill_no_md() {
    local name="$1"
    local location="${2:-$FAKE_REPO/skills}"

    mkdir -p "$location/$name"
    echo "Some content" > "$location/$name/README.md"
}

# Create a fake agent file
create_fake_agent() {
    local name="$1"
    local location="${2:-$FAKE_REPO/agents}"

    mkdir -p "$location"
    cat > "$location/$name.md" << EOF
---
name: $name
---

# $name Agent

This is a test agent.
EOF
}

# Create a fake rule file
create_fake_rule() {
    local name="$1"
    local location="${2:-$FAKE_REPO/rules}"

    mkdir -p "$location"
    cat > "$location/$name.md" << EOF
# $name Rule

This is a test rule.
EOF
}

# Create settings.json
create_fake_settings() {
    local location="${1:-$FAKE_REPO}"
    cat > "$location/settings.json" << EOF
{
    "theme": "dark",
    "test": true
}
EOF
}

# Create statusline.sh
create_fake_statusline() {
    local location="${1:-$FAKE_REPO}"
    cat > "$location/statusline.sh" << 'EOF'
#!/bin/bash
echo "test statusline"
EOF
    chmod +x "$location/statusline.sh"
}

# Assert that a symlink exists and points to expected target
assert_symlink() {
    local path="$1"
    local expected_target="$2"

    if [[ ! -L "$path" ]]; then
        echo "Expected symlink at $path but it doesn't exist or isn't a symlink"
        return 1
    fi

    local actual_target
    actual_target="$(readlink "$path")"

    # Normalize trailing slashes for comparison
    actual_target="${actual_target%/}"
    expected_target="${expected_target%/}"

    if [[ "$actual_target" != "$expected_target" ]]; then
        echo "Symlink $path points to $actual_target, expected $expected_target"
        return 1
    fi

    return 0
}

# Assert that a file exists and is not a symlink
assert_regular_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        echo "Expected file at $path but it doesn't exist"
        return 1
    fi

    if [[ -L "$path" ]]; then
        echo "Expected regular file at $path but it's a symlink"
        return 1
    fi

    return 0
}

# Assert that a directory exists
assert_dir() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        echo "Expected directory at $path but it doesn't exist"
        return 1
    fi

    return 0
}

# Assert that a backup was created
assert_backup_exists() {
    local backup_dir="$FAKE_REPO/.backup"

    if [[ ! -d "$backup_dir" ]]; then
        echo "No .backup directory found"
        return 1
    fi

    local backup_count
    backup_count="$(ls -1 "$backup_dir" 2>/dev/null | wc -l | tr -d ' ')"

    if [[ "$backup_count" -eq 0 ]]; then
        echo "No backups found in $backup_dir"
        return 1
    fi

    return 0
}

# Get the latest backup directory
get_latest_backup() {
    local backup_dir="$FAKE_REPO/.backup"
    ls -1t "$backup_dir" 2>/dev/null | head -1
}

# Assert manifest contains expected operation
assert_manifest_operation() {
    local expected_op="$1"
    local backup_dir="$FAKE_REPO/.backup"
    local latest
    latest="$(get_latest_backup)"

    if [[ -z "$latest" ]]; then
        echo "No backup found"
        return 1
    fi

    local manifest="$backup_dir/$latest/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        echo "No manifest.json in backup"
        return 1
    fi

    if ! grep -q "\"operation\": \"$expected_op\"" "$manifest"; then
        echo "Manifest doesn't contain operation: $expected_op"
        cat "$manifest"
        return 1
    fi

    return 0
}

# Run install.sh with fake environment
run_install() {
    cd "$FAKE_REPO"
    HOME="$FAKE_HOME" bash ./install.sh "$@"
}

# Run sync.sh with fake environment
run_sync() {
    cd "$FAKE_REPO"
    HOME="$FAKE_HOME" bash ./sync.sh "$@"
}
