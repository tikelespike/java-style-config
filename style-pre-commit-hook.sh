#!/bin/bash

# This script is intended as a git hook that checks whether there are any changed
# java files where the IntelliJ autoformatter can be applied (and yields a change).
# The correctly autoformatted version is checked for checkstyle compliance, and if
# checkstyle errors are found, the commit is aborted. If the formatted file is
# checkstyle-compliant after applying the autoformatter, the user can accept to
# automatically apply the formatter.

echo "Codestyle pre-commit check enabled."

# Configuration
STYLE_REPO=$(dirname $0)
AUTOFORMATTER=$STYLE_REPO/autoformatter.sh
CHECKSTYLE_CONFIG=$STYLE_REPO/checkstyle.xml
AUTOFORMATTER_CONFIG=$STYLE_REPO/autoformat_intellij.xml

print_error() {
    echo -e "\033[31m" "$@" "\033[0m" >&2
}

# Check if required tools are available
if ! command -v $AUTOFORMATTER &> /dev/null; then
    print_error "Codestyle pre-commit validation is enabled, but the IntelliJ IDEA command-line formatter (autoformatter.sh) could not be found. Please fix this or disable this hook."
    exit 1
fi

if ! command -v checkstyle &> /dev/null; then
    print_error "Codestyle pre-commit validation is enabled, but checkstyle could not be found. Please install it or disable this hook."
    exit 1
fi

# Get a list of changed or new Java files
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.java$')

if [ -z "$FILES" ]; then
    echo "No Java files changed."
    exit 0
fi

# Create a temporary directory for autoformatted files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create temporary copies of all changed java files
TEMP_COPIES=()
for FILE in $FILES; do
    ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
    TEMP_FILE="$TEMP_DIR/working-copy/$FILE"
    mkdir -p "$(dirname "$TEMP_FILE")"
    cp "$ORIGINAL_FILE" "$TEMP_FILE"
    TEMP_COPIES+=("$TEMP_FILE")
done

# Run IntelliJ formatter on temp copies
echo "Running autoformatter, this can take some time..."
$AUTOFORMATTER -s $AUTOFORMATTER_CONFIG "${TEMP_COPIES[@]}" &> /dev/null

# Early reject if there are checkstyle issues even after applying the autoformatter
CHECKSTYLE_VIOLATION_FILES=()
for FILE in $FILES; do
    TEMP_FILE="$TEMP_DIR/working-copy/$FILE"
    checkstyle -c "$CHECKSTYLE_CONFIG" "$TEMP_FILE" &> /dev/null
    if [ $? -ne 0 ]; then
        CHECKSTYLE_VIOLATION_FILES+=("$FILE")
    fi
done
if [ ${#CHECKSTYLE_VIOLATION_FILES[@]} -ne 0 ]; then
    print_error "Checkstyle violations found (with formatter applied) in the following file(s):"
    for FILE in "${CHECKSTYLE_VIOLATION_FILES[@]}"; do
        echo "    $FILE"
    done
    print_error "Commit cancelled. Please fix the checkstyle issues."
    exit 1
fi

# Determine changes made by formatter
FILES_TO_FORMAT=()
for FILE in $FILES; do
    ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
    TEMP_FILE="$TEMP_DIR/working-copy/$FILE"

    # Compare original and formatted files
    if ! cmp -s "$ORIGINAL_FILE" "$TEMP_FILE"; then
        FILES_TO_FORMAT+=("$FILE")
    fi
done

# Prompt user if there are files that can be formatted
if [ ${#FILES_TO_FORMAT[@]} -ne 0 ]; then
    QUERY_USER=true
    while [ "$QUERY_USER" = true ]; do
        echo "There are new/changed files that are not yet autoformatted correctly."
        select CHOICE in "Apply Formatter" "View Diff" "Commit Anyway" "Cancel Commit"; do
            case $CHOICE in
                "Apply Formatter")
                    for FILE in "${FILES_TO_FORMAT[@]}"; do
                        ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
                        TEMP_FILE="$TEMP_DIR/working-copy/$FILE"
                        cp "$TEMP_FILE" "$ORIGINAL_FILE"
                        git add "$ORIGINAL_FILE"
                    done
                    QUERY_USER=false
                    break
                    ;;
                "View Diff")
                    mkdir "$TEMP_DIR/original-files" # Original files (but new/changed only) without autoformatting to compare
                    for FILE in $FILES; do
                        echo "File: $FILE"
                        ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
                        mkdir -p "$(dirname "$TEMP_DIR/original-files/$FILE")"
                        cp "$ORIGINAL_FILE" "$TEMP_DIR/original-files/$FILE"
                    done
                    git diff --no-index "$TEMP_DIR/original-files" "$TEMP_DIR/working-copy" 
                    break
                    ;;
                "Commit Anyway")
                    QUERY_USER=false
                    break
                    ;;
                "Cancel Commit")
                    print_error "Commit cancelled."
                    exit 1
                    ;;
            esac
        done < /dev/tty
    done
fi
