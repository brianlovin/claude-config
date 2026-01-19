#!/usr/bin/env bats
# Tests for sync.sh

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Status Display Tests
# =============================================================================

@test "sync.sh shows status by default" {
    run run_sync
    [[ "$output" == *"Claude Config Sync Status"* ]]
    [[ "$output" == *"Legend:"* ]]
}

@test "sync.sh shows usage in status" {
    run run_sync
    [[ "$output" == *"./sync.sh add"* ]]
    [[ "$output" == *"./sync.sh remove"* ]]
    [[ "$output" == *"./sync.sh undo"* ]]
}

@test "sync.sh shows synced skills" {
    create_fake_skill "test-skill"
    run_install
    run run_sync
    [[ "$output" == *"test-skill"* ]]
    [[ "$output" == *"synced"* ]]
}

@test "sync.sh shows local-only skills" {
    # Create a local-only skill (not in repo)
    mkdir -p "$FAKE_HOME/.claude/skills/local-skill"
    echo "---" > "$FAKE_HOME/.claude/skills/local-skill/SKILL.md"
    echo "name: local" >> "$FAKE_HOME/.claude/skills/local-skill/SKILL.md"
    echo "description: local" >> "$FAKE_HOME/.claude/skills/local-skill/SKILL.md"
    echo "---" >> "$FAKE_HOME/.claude/skills/local-skill/SKILL.md"

    run run_sync
    [[ "$output" == *"local-skill"* ]]
    [[ "$output" == *"local only"* ]]
}

# =============================================================================
# Add Skill Tests
# =============================================================================

@test "sync.sh add skill copies to repo and creates symlink" {
    # Create a local skill
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"

    run_sync add skill my-skill

    # Should now be in repo
    assert_dir "$FAKE_REPO/skills/my-skill"
    [[ -f "$FAKE_REPO/skills/my-skill/SKILL.md" ]]

    # Local should be symlink to repo
    assert_symlink "$FAKE_HOME/.claude/skills/my-skill" "$FAKE_REPO/skills/my-skill"
}

@test "sync.sh add skill creates backup" {
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    run_sync add skill my-skill
    assert_backup_exists
    assert_manifest_operation "add-skill"
}

@test "sync.sh add skill --dry-run doesn't modify" {
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    run run_sync --dry-run add skill my-skill

    # Repo should not have the skill
    [[ ! -d "$FAKE_REPO/skills/my-skill" ]]
    # Local should still be a regular directory
    assert_regular_file "$FAKE_HOME/.claude/skills/my-skill/SKILL.md"
}

@test "sync.sh add skill fails if already synced" {
    create_fake_skill "my-skill"
    run_install

    run run_sync add skill my-skill
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"already synced"* ]]
}

@test "sync.sh add skill fails if skill doesn't exist" {
    run run_sync add skill nonexistent
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Add Agent Tests
# =============================================================================

@test "sync.sh add agent copies to repo and creates symlink" {
    create_fake_agent "my-agent" "$FAKE_HOME/.claude/agents"

    run_sync add agent my-agent

    assert_regular_file "$FAKE_REPO/agents/my-agent.md"
    assert_symlink "$FAKE_HOME/.claude/agents/my-agent.md" "$FAKE_REPO/agents/my-agent.md"
}

@test "sync.sh add agent creates backup" {
    create_fake_agent "my-agent" "$FAKE_HOME/.claude/agents"
    run_sync add agent my-agent
    assert_backup_exists
    assert_manifest_operation "add-agent"
}

# =============================================================================
# Add Rule Tests
# =============================================================================

@test "sync.sh add rule copies to repo and creates symlink" {
    create_fake_rule "my-rule" "$FAKE_HOME/.claude/rules"

    run_sync add rule my-rule

    assert_regular_file "$FAKE_REPO/rules/my-rule.md"
    assert_symlink "$FAKE_HOME/.claude/rules/my-rule.md" "$FAKE_REPO/rules/my-rule.md"
}

# =============================================================================
# Remove Skill Tests
# =============================================================================

@test "sync.sh remove skill removes from repo but keeps local" {
    create_fake_skill "my-skill"
    run_install

    # Verify it's synced
    assert_symlink "$FAKE_HOME/.claude/skills/my-skill" "$FAKE_REPO/skills/my-skill"

    run_sync remove skill my-skill

    # Should be removed from repo
    [[ ! -d "$FAKE_REPO/skills/my-skill" ]]

    # Should exist locally as regular directory
    assert_dir "$FAKE_HOME/.claude/skills/my-skill"
    [[ ! -L "$FAKE_HOME/.claude/skills/my-skill" ]]
}

@test "sync.sh remove skill creates backup" {
    create_fake_skill "my-skill"
    run_install
    run_sync remove skill my-skill
    assert_backup_exists
    assert_manifest_operation "remove-skill"
}

@test "sync.sh remove skill --dry-run doesn't modify" {
    create_fake_skill "my-skill"
    run_install

    run run_sync --dry-run remove skill my-skill

    # Repo should still have the skill
    assert_dir "$FAKE_REPO/skills/my-skill"
}

@test "sync.sh remove skill fails if not in repo" {
    run run_sync remove skill nonexistent
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not in repo"* ]]
}

# =============================================================================
# Backups Command Tests
# =============================================================================

@test "sync.sh backups shows 'no backups' when empty" {
    run run_sync backups
    [[ "$output" == *"No backups found"* ]]
}

@test "sync.sh backups lists existing backups" {
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    run_sync add skill my-skill

    run run_sync backups
    [[ "$output" == *"Available Backups"* ]]
    [[ "$output" == *"add-skill"* ]]
}

# =============================================================================
# Undo Tests
# =============================================================================

@test "sync.sh undo fails when no backups exist" {
    run run_sync undo
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No backups found"* ]]
}

@test "sync.sh undo --dry-run shows what would be restored" {
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    run_sync add skill my-skill

    run run_sync --dry-run undo
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"Would restore"* ]]
}

@test "sync.sh undo restores original files" {
    # Create local skill with specific content
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    echo "original content" >> "$FAKE_HOME/.claude/skills/my-skill/SKILL.md"

    # Add to repo (this backs up the original)
    run_sync add skill my-skill

    # Verify it's now a symlink
    assert_symlink "$FAKE_HOME/.claude/skills/my-skill" "$FAKE_REPO/skills/my-skill"

    # Undo (with yes response)
    echo "y" | run_sync undo

    # Should be restored as regular directory
    [[ ! -L "$FAKE_HOME/.claude/skills/my-skill" ]]
    assert_dir "$FAKE_HOME/.claude/skills/my-skill"
}

# =============================================================================
# Dry-run Global Option Tests
# =============================================================================

@test "sync.sh -n works as global dry-run flag" {
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    run run_sync -n add skill my-skill
    [[ "$output" == *"[dry-run]"* ]]
    [[ ! -d "$FAKE_REPO/skills/my-skill" ]]
}

@test "sync.sh --dry-run works anywhere in args" {
    create_fake_skill "my-skill" "$FAKE_HOME/.claude/skills"
    run run_sync add --dry-run skill my-skill
    [[ "$output" == *"[dry-run]"* ]]
}
