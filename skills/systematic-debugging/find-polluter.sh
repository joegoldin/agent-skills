#!/usr/bin/env bash
# Bisection script to find which test creates unwanted files/state
# Usage: ./find-polluter.sh <file_or_dir_to_check> <test_pattern> [test_command]
# Example: ./find-polluter.sh '.git' 'src/**/*.test.ts'
# Example: ./find-polluter.sh '.git' 'src/**/*.test.ts' 'npm test'
#
# If test_command is omitted, auto-detects from project files:
#   package.json → npm test
#   Cargo.toml   → cargo test
#   pytest.ini / pyproject.toml → pytest
#   go.mod       → go test ./...

set -e

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <file_to_check> <test_pattern> [test_command]"
  echo "Example: $0 '.git' 'src/**/*.test.ts'"
  echo "Example: $0 '.git' 'src/**/*.test.ts' 'npm test'"
  echo ""
  echo "If test_command is omitted, auto-detects from project files."
  exit 1
fi

POLLUTION_CHECK="$1"
TEST_PATTERN="$2"

# Determine test command
if [ -n "${3:-}" ]; then
  TEST_CMD="$3"
elif [ -f "package.json" ]; then
  TEST_CMD="npm test"
elif [ -f "Cargo.toml" ]; then
  TEST_CMD="cargo test"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  TEST_CMD="pytest"
elif [ -f "go.mod" ]; then
  TEST_CMD="go test ./..."
else
  echo "Could not auto-detect test command. Pass it as the 3rd argument."
  exit 1
fi

echo "🔍 Searching for test that creates: $POLLUTION_CHECK"
echo "Test pattern: $TEST_PATTERN"
echo "Test command: $TEST_CMD"
echo ""

# Get list of test files
TEST_FILES=$(find . -path "$TEST_PATTERN" | sort)
TOTAL=$(echo "$TEST_FILES" | wc -l | tr -d ' ')

echo "Found $TOTAL test files"
echo ""

COUNT=0
for TEST_FILE in $TEST_FILES; do
  COUNT=$((COUNT + 1))

  # Skip if pollution already exists
  if [ -e "$POLLUTION_CHECK" ]; then
    echo "⚠️  Pollution already exists before test $COUNT/$TOTAL"
    echo "   Skipping: $TEST_FILE"
    continue
  fi

  echo "[$COUNT/$TOTAL] Testing: $TEST_FILE"

  # Run the test
  $TEST_CMD "$TEST_FILE" > /dev/null 2>&1 || true

  # Check if pollution appeared
  if [ -e "$POLLUTION_CHECK" ]; then
    echo ""
    echo "🎯 FOUND POLLUTER!"
    echo "   Test: $TEST_FILE"
    echo "   Created: $POLLUTION_CHECK"
    echo ""
    echo "Pollution details:"
    ls -la "$POLLUTION_CHECK"
    echo ""
    echo "To investigate:"
    echo "  $TEST_CMD $TEST_FILE    # Run just this test"
    echo "  cat $TEST_FILE         # Review test code"
    exit 1
  fi
done

echo ""
echo "✅ No polluter found - all tests clean!"
exit 0
