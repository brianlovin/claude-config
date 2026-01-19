# Testing

This project uses [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) for testing the shell scripts.

## Running Tests

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/install.bats
bats tests/sync.bats
bats tests/validation.bats

# Run with verbose output (show test names)
bats --tap tests/
```

## Test Structure

```
tests/
├── test_helper.bash    # Shared setup/teardown and utilities
├── install.bats        # Tests for install.sh
├── sync.bats           # Tests for sync.sh commands
└── validation.bats     # Tests for skills validation
```

## Writing Tests

### Test File Format

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "description of what this tests" {
    # Arrange
    create_fake_skill "my-skill"

    # Act
    run_install

    # Assert
    assert_symlink "$FAKE_HOME/.claude/skills/my-skill" "$FAKE_REPO/skills/my-skill"
}
```

### Key Conventions

1. **Always use the test environment** - Call `setup_test_env` in setup and `teardown_test_env` in teardown
2. **Use helper functions** - Use `run_install`, `run_sync`, `create_fake_skill`, etc. from test_helper.bash
3. **Test in isolation** - Tests use temp directories (`$FAKE_HOME`, `$FAKE_REPO`) and never touch real config

### Available Test Helpers

**Environment:**
- `setup_test_env` - Creates isolated temp directories
- `teardown_test_env` - Cleans up temp directories
- `$FAKE_HOME` - Temp directory simulating user's home
- `$FAKE_REPO` - Temp directory simulating the repo

**Creating Test Data:**
- `create_fake_skill "name"` - Creates a valid skill with SKILL.md
- `create_invalid_skill "name"` - Creates skill without frontmatter
- `create_skill_no_md "name"` - Creates skill without SKILL.md
- `create_fake_agent "name"` - Creates an agent file
- `create_fake_rule "name"` - Creates a rule file
- `create_fake_settings` - Creates settings.json
- `create_fake_statusline` - Creates statusline.sh

**Running Scripts:**
- `run_install [args]` - Runs install.sh in test environment
- `run_sync [args]` - Runs sync.sh in test environment

**Assertions:**
- `assert_symlink "path" "expected_target"` - Verifies symlink exists and points to target
- `assert_regular_file "path"` - Verifies file exists and is not a symlink
- `assert_dir "path"` - Verifies directory exists
- `assert_backup_exists` - Verifies a backup was created
- `assert_manifest_operation "op"` - Verifies manifest contains operation

**Backup Helpers:**
- `get_latest_backup` - Returns name of most recent backup

### Testing Tips

1. **Test both success and failure cases** - Verify error messages and exit codes
2. **Test dry-run mode** - Ensure `--dry-run` doesn't modify anything
3. **Test idempotency** - Running the same command twice should work
4. **Group related tests** - Use comment headers to organize test sections

## Adding New Tests

When adding new functionality to install.sh or sync.sh:

1. Add tests to the appropriate .bats file
2. Add any new helper functions to test_helper.bash
3. Run `bats tests/` to verify all tests pass
4. Consider edge cases (missing files, conflicts, dry-run)

## CI Integration

Tests run automatically on push/PR via GitHub Actions. See `.github/workflows/test.yml`.

The workflow:
1. Runs on `macos-latest` (matches dev environment)
2. Installs bats-core via Homebrew
3. Runs all tests with `bats tests/`
4. Validates all skills with `./sync.sh validate`

To run locally before pushing:
```bash
bats tests/ && ./sync.sh validate
```
