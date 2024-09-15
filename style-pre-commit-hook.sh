#!/bin/bash

# This script is intended as a git hook that checks whether there are any changed
# java files where the IntelliJ autoformatter can be applied (and yields a change).
# The correctly autoformatted version is checked for checkstyle compliance, and if
# checkstyle errors are found, the commit is aborted. If the formatted file is
# checkstyle-compliant after applying the autoformatter, the user can accept to
# automatically apply the formatter.

# Configuration default values
NO_FORMATTING_WHEN_CHECKSTYLE_OK="${NO_FORMATTING_WHEN_CHECKSTYLE_OK:-false}" # Set this to true to skip the (slow) IntelliJ autoformatter when there are no checkstyle violations on the changed files
USE_AUTOFORMATTER="${USE_AUTOFORMATTER:-true}" # Set this to false to only run checkstyle and abort directly if violations are found (even if they could be fixed by running the autoformatter)
USE_CHECKSTYLE="${USE_CHECKSTYLE:-true}" # Set this to false to disable checkstyle and only apply the autoformatter
ALLOW_IGNORE_CHECKSTYLE="${ALLOW_IGNORE_CHECKSTYLE:-true}" # Set this to true to allow committing even if this results in checking in checkstyle violations (warning will be shown)

STYLE_REPO=$(dirname $0)
CHECKSTYLE_CONFIG="${CHECKSTYLE_CONFIG:-$STYLE_REPO/checkstyle.xml}" # Change this to use a different checkstyle configuration
AUTOFORMATTER_CONFIG="${AUTOFORMATTER_CONFIG:-$STYLE_REPO/autoformat_intellij.xml}" # Change this to use a different checkstyle configuration

# Constants
CHECKSTYLE_LOG_FORMATTED=$STYLE_REPO/checkstyle-log-formatted.txt
CHECKSTYLE_LOG_ORIGINAL=$STYLE_REPO/checkstyle-log-original.txt
AUTOFORMATTER=$STYLE_REPO/autoformatter.sh
USER_OPTION_APPLY_WITH_VIOLATION="Apply Formatter & Commit (VIOLATES CHECKSTYLE!)"
USER_OPTION_APPLY_NO_VIOLATION="Apply Formatter & Commit"
USER_OPTION_DIFF="View Formatter Diff"
USER_OPTION_CANCEL="Cancel Commit"
USER_OPTION_COMMIT_NO_FORMATTING_WITH_VIOLATION="Commit Without Formatting (VIOLATES CHECKSTYLE!)"
USER_OPTION_COMMIT_NO_FORMATTING_NO_VIOLATION="Commit Without Formatting"

LOG_PREFIX="[STYLE]"

print_info() {
    echo "$LOG_PREFIX" "$@"
}

print_info_inline() {
    echo -n "$LOG_PREFIX" "$@"
}

print_error() {
    echo -e "$LOG_PREFIX" "\033[31m""$@""\033[0m" >&2
}

print_info "Java codestyle pre-commit hook enabled."

if [ "$USE_CHECKSTYLE" = false ] && [ "$USE_AUTOFORMATTER" = false ]; then
    print_info "No checks enabled."
    exit 0
fi

# Check if required tools are available
if [ "$USE_AUTOFORMATTER" = true ] && [ ! command -v $AUTOFORMATTER &> /dev/null ]; then
    print_error "Codestyle pre-commit validation is enabled, but the IntelliJ IDEA command-line formatter (autoformatter.sh) could not be found. Please make sure autoformatter.sh exists and works, set USE_AUTOFORMATTER to false to skip the autoformatter, or disable this hook completely."
    exit 1
fi

if [ "$USE_CHECKSTYLE" = true ] && [ ! command -v checkstyle &> /dev/null ]; then
    print_error "Codestyle pre-commit validation is enabled, but checkstyle could not be found. Please install checkstyle, set USE_CHECKSTYLE to false to disable checkstyle, or disable this hook completely."
    exit 1
fi

# Get a list of changed or new Java files
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.java$')

if [ -z "$FILES" ]; then
    print_info "No Java files changed."
    exit 0
fi

# If autoformatter disabled, simply run checkstyle on all files
if [ "$USE_AUTOFORMATTER" = false ]; then
    CHECKSTYLE_VIOLATION_FILES=()
    CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=false
    [ -e "$CHECKSTYLE_LOG_ORIGINAL" ] && rm "$CHECKSTYLE_LOG_ORIGINAL"
    for FILE in $FILES; do
        ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
        echo "File: $ORIGINAL_FILE" >> "$CHECKSTYLE_LOG_ORIGINAL"
        checkstyle -c "$CHECKSTYLE_CONFIG" "$ORIGINAL_FILE" &>> "$CHECKSTYLE_LOG_ORIGINAL"
        if [ $? -ne 0 ]; then
            CHECKSTYLE_VIOLATION_FILES+=("$FILE")
            CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=true
        fi
        print_info "" >> "$CHECKSTYLE_LOG_FORMATTED"
    done
    
    if [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = false ]; then
        exit 0
    fi
    
    print_info ""
    print_error "Checkstyle violations found in the following file(s):"
    for FILE in "${CHECKSTYLE_VIOLATION_FILES[@]}"; do
        print_error "    $FILE"
    done
    print_info ""
    
    if [ "$ALLOW_IGNORE_CHECKSTYLE" = true ]; then
        print_info_inline "There are checkstyle violations. Commit anyway (y/n)? "
        read COMMIT_WITH_VIOLATIONS < /dev/tty

        if [ "$COMMIT_WITH_VIOLATIONS" != "${COMMIT_WITH_VIOLATIONS#[Yy]}" ]; then
            exit 0
        fi
    fi
    
    print_error "Commit cancelled. Please fix the checkstyle issues."
    exit 1
fi

# If corresponding setting enabled, skip autoformatter when no checkstyle violations are found
CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=unknown
if [ "$USE_CHECKSTYLE" = true ] && [ "$NO_FORMATTING_WHEN_CHECKSTYLE_OK" = true ]; then
    print_info "Running checkstyle..."
    CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=false
    for FILE in $FILES; do
        ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
        checkstyle -c "$CHECKSTYLE_CONFIG" "$ORIGINAL_FILE" &> /dev/null
        if [ $? -ne 0 ]; then
            print_info "Checkstyle violation found in file $FILE."
            CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=true
            break # We can skip checking other files because we will now definitly run the autoformatter
        fi
    done
    if [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = false ]; then
        print_info "Checkstyle ok, skipping autoformatter."
        exit 0
    fi
fi

# Create a temporary directory for autoformatted files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
WORKING_COPY_DIR=$TEMP_DIR/working-copy

# Create temporary copies of all changed java files
TEMP_COPIES=()
for FILE in $FILES; do
    ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
    TEMP_FILE="$WORKING_COPY_DIR/$FILE"
    mkdir -p "$(dirname "$TEMP_FILE")"
    cp "$ORIGINAL_FILE" "$TEMP_FILE"
    TEMP_COPIES+=("$TEMP_FILE")
done

# Run IntelliJ formatter on temp copies
print_info "Running autoformatter, this can take a few seconds..."
$AUTOFORMATTER -s $AUTOFORMATTER_CONFIG "${TEMP_COPIES[@]}" &> /dev/null

# Early reject if there are checkstyle issues even after applying the autoformatter
CHECKSTYLE_VIOLATION_FILES=()
CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES=false
if [ "$USE_CHECKSTYLE" = true ]; then
    [ -e "$CHECKSTYLE_LOG_FORMATTED" ] && rm "$CHECKSTYLE_LOG_FORMATTED"
    for FILE in $FILES; do
        TEMP_FILE="$WORKING_COPY_DIR/$FILE"
        echo "File: $TEMP_FILE" >> "$CHECKSTYLE_LOG_FORMATTED"
        checkstyle -c "$CHECKSTYLE_CONFIG" "$TEMP_FILE" &>> "$CHECKSTYLE_LOG_FORMATTED"
        if [ $? -ne 0 ]; then
            CHECKSTYLE_VIOLATION_FILES+=("$FILE")
            CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES=true
        fi
        print_info "" >> "$CHECKSTYLE_LOG_FORMATTED"
    done
    if [ "$CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES" = true ]; then
        print_info ""
        print_error "Checkstyle violations found (with formatter applied) in the following file(s):"
        for FILE in "${CHECKSTYLE_VIOLATION_FILES[@]}"; do
            print_error "    $FILE"
        done
        print_info ""
        if [ "$ALLOW_IGNORE_CHECKSTYLE" = false ]; then
            print_error "Commit cancelled. Please fix the checkstyle issues."
            exit 1
        fi
    fi
fi

# Determine changes made by formatter
FILES_TO_FORMAT=()
for FILE in $FILES; do
    ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
    TEMP_FILE="$WORKING_COPY_DIR/$FILE"

    # Compare original and formatted files
    if ! cmp -s "$ORIGINAL_FILE" "$TEMP_FILE"; then
        FILES_TO_FORMAT+=("$FILE")
    fi
done

# Autoformatter already applied
if [ ${#FILES_TO_FORMAT[@]} -eq 0 ]; then
    if [ "$CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES" = false ]; then
        print_info "Files already correctly formatted."
        exit 0
    fi

    print_info ""
    print_info_inline "Nothing to do for the autoformatter, but there are still checkstyle violations. Commit anyway (y/n)? "
    read COMMIT_WITH_VIOLATIONS < /dev/tty

    if [ "$COMMIT_WITH_VIOLATIONS" != "${COMMIT_WITH_VIOLATIONS#[Yy]}" ]; then
        exit 0
    fi
    
    print_error "Commit cancelled due to checkstyle violations."
    exit 1
fi


# Determine if there are checkstyle violations on the original files, requiring the user to accept the autoformatted changes

# Performance improvement: Assume that formatter does not introduce checkstyle violations
if [ "$CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES" = true ]; then
    CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=true
fi

# If checkstyle disabled, proceed as if they are no violations
if [ "$USE_CHECKSTYLE" = false ]; then
    CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=false
fi

if [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = unknown ]; then
    [ -e "$CHECKSTYLE_LOG_ORIGINAL" ] && rm "$CHECKSTYLE_LOG_ORIGINAL"
    print_info "Running checkstyle on original files..."
    CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=false
    for FILE in $FILES; do
        ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
        echo "File: $ORIGINAL_FILE" >> "$CHECKSTYLE_LOG_ORIGINAL"
        checkstyle -c "$CHECKSTYLE_CONFIG" "$ORIGINAL_FILE" &>> "$CHECKSTYLE_LOG_ORIGINAL"
        if [ $? -ne 0 ]; then
            CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES=true
            break # We can skip checking other files because the user will now definitly have to accept the autoformatter
        fi
        print_info "" >> "$CHECKSTYLE_LOG_ORIGINAL"
    done
fi

# Prompt the user about the proposed changes
USER_OPTIONS=()
if [ "$CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES" = true ]; then
    USER_OPTIONS+=("$USER_OPTION_APPLY_WITH_VIOLATION")
else
    USER_OPTIONS+=("$USER_OPTION_APPLY_NO_VIOLATION")
fi
USER_OPTIONS+=("$USER_OPTION_DIFF" "$USER_OPTION_CANCEL")
if [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = false ]; then
    USER_OPTIONS+=("$USER_OPTION_COMMIT_NO_FORMATTING_NO_VIOLATION")
fi
if [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = true ] && [ "$ALLOW_IGNORE_CHECKSTYLE" = true ]; then
    USER_OPTIONS+=("$USER_OPTION_COMMIT_NO_FORMATTING_WITH_VIOLATION")
fi
QUERY_USER=true
while [ "$QUERY_USER" = true ]; do
    print_info ""
    print_info "There are new/changed files that are not yet autoformatted correctly."
    if [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = true ] && [ "$CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES" = false ]; then
        print_info "There are also checkstyle violations, but they can be fixed automatically."
    elif [ "$CHECKSTYLE_VIOLATIONS_ON_ORIGINAL_FILES" = true ] && [ "$CHECKSTYLE_VIOLATIONS_ON_FORMATTED_FILES" = true ]; then
        print_info "There are also checkstyle violations that cannot be fixed automatically."
    fi
    select CHOICE in "${USER_OPTIONS[@]}"; do
        case $CHOICE in
            "$USER_OPTION_APPLY_NO_VIOLATION"|"$USER_OPTION_APPLY_WITH_VIOLATION")
                for FILE in "${FILES_TO_FORMAT[@]}"; do
                    ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
                    TEMP_FILE="$WORKING_COPY_DIR/$FILE"
                    cp "$TEMP_FILE" "$ORIGINAL_FILE"
                    git add "$ORIGINAL_FILE"
                done
                QUERY_USER=false
                break
                ;;
            "$USER_OPTION_DIFF")
                ORIGINAL_FILES_DIR="$TEMP_DIR/original-files"
                if [ ! -d "$ORIGINAL_FILES_DIR" ]; then
                    mkdir "$ORIGINAL_FILES_DIR" # Original files (but new/changed only) without autoformatting to compare
                    for FILE in $FILES; do
                        ORIGINAL_FILE=$(git rev-parse --show-toplevel)/$FILE
                        mkdir -p "$(dirname "$ORIGINAL_FILES_DIR/$FILE")"
                        cp "$ORIGINAL_FILE" "$ORIGINAL_FILES_DIR/$FILE"
                    done
                fi
                git diff --no-index "$ORIGINAL_FILES_DIR" "$WORKING_COPY_DIR" 
                break
                ;;
            "$USER_OPTION_COMMIT_NO_FORMATTING_NO_VIOLATION"|"$USER_OPTION_COMMIT_NO_FORMATTING_WITH_VIOLATION")
                QUERY_USER=false
                break
                ;;
            "$USER_OPTION_CANCEL")
                print_error "Commit cancelled."
                exit 1
                ;;
        esac
    done < /dev/tty
done
