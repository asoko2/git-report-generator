#!/bin/bash

# ============================================================================
# Git Commit Report Generator
# Generates work reports from git commits with customizable templates
# ============================================================================

# Help Menu
if [ "$1" == "-h" ]; then
  echo "Usage: ./report-generator.sh <project_directory> <username> <from_date> [to_date] [--csv]"
  echo "Example: ./report-generator.sh /path/to/repo john.doe 2024-08-30"
  echo "Example: ./report-generator.sh /path/to/repo john.doe 2024-08-30 2024-08-31"
  echo "Example: ./report-generator.sh /path/to/repo john.doe 2024-08-30 2024-08-31 --csv"
  exit 1
fi

# Usage validation
if [ "$#" -lt 3 ]; then
  echo "Usage: ./report-generator.sh <project_directory> <username> <from_date> [to_date] [--csv]"
  echo "Example: ./report-generator.sh /path/to/repo john.doe 2024-08-30"
  echo "Example: ./report-generator.sh /path/to/repo john.doe 2024-08-30 2024-08-31"
  echo "Example: ./report-generator.sh /path/to/repo john.doe 2024-08-30 2024-08-31 --csv"
  exit 1
fi

# Parse arguments
PROJECT_DIR=$1
USERNAME=$2
FROM_DATE=$3
TO_DATE=$4
CSV_MODE=false

# Check if last argument is --csv or if TO_DATE is --csv
if [ "$TO_DATE" = "--csv" ]; then
  CSV_MODE=true
  TO_DATE=$FROM_DATE
elif [ "$5" = "--csv" ]; then
  CSV_MODE=true
fi

# Set TO_DATE to FROM_DATE if not provided
[ -z "$TO_DATE" ] && TO_DATE=$FROM_DATE

# Validate project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: Directory '$PROJECT_DIR' does not exist"
  exit 1
fi

# Check if directory is a git repository
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: '$PROJECT_DIR' is not a git repository"
  exit 1
fi

# Validate date format
if ! [[ "$FROM_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: Invalid date format for FROM_DATE. Use YYYY-MM-DD"
  exit 1
fi

if [ -n "$TO_DATE" ] && [ "$TO_DATE" != "--csv" ] && ! [[ "$TO_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: Invalid date format for TO_DATE. Use YYYY-MM-DD"
  exit 1
fi

# Get script directory to find template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/report_template.txt"

# Load template from file (skip for CSV mode)
if [ "$CSV_MODE" = false ]; then
  if [ -f "$TEMPLATE_FILE" ]; then
    TEMPLATE=$(cat "$TEMPLATE_FILE")
  else
    echo "Error: Template file not found at $TEMPLATE_FILE"
    echo "Please ensure 'report_template.txt' exists in the same directory as this script"
    exit 1
  fi
fi

# Define time range
SINCE="${FROM_DATE}T00:00:00"
UNTIL="${TO_DATE}T23:59:59"

# Extract project name from directory
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Create project-specific output directory
OUTPUT_DIR="${SCRIPT_DIR}/${PROJECT_NAME}"

# Create directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR"
  echo "✓ Created output directory: $OUTPUT_DIR"
fi

# Generate dynamic filename in project-specific directory
if [ "$CSV_MODE" = true ]; then
  REPORT_FILE="${OUTPUT_DIR}/report_${USERNAME}_${PROJECT_NAME}_${FROM_DATE}"
  if [ "$FROM_DATE" != "$TO_DATE" ]; then
    REPORT_FILE="${REPORT_FILE}_to_${TO_DATE}"
  fi
  REPORT_FILE="${REPORT_FILE}.csv"
else
  REPORT_FILE="${OUTPUT_DIR}/report_${USERNAME}_${PROJECT_NAME}_${FROM_DATE}"
  if [ "$FROM_DATE" != "$TO_DATE" ]; then
    REPORT_FILE="${REPORT_FILE}_to_${TO_DATE}"
  fi
  REPORT_FILE="${REPORT_FILE}.txt"
fi

# Format date range for display
if [ "$FROM_DATE" == "$TO_DATE" ]; then
  DATE_RANGE=$(date -d "$FROM_DATE" +"%d/%m/%Y" 2>/dev/null || date -j -f "%Y-%m-%d" "$FROM_DATE" +"%d/%m/%Y" 2>/dev/null || echo "$FROM_DATE")
else
  FROM_DISPLAY=$(date -d "$FROM_DATE" +"%d/%m/%Y" 2>/dev/null || date -j -f "%Y-%m-%d" "$FROM_DATE" +"%d/%m/%Y" 2>/dev/null || echo "$FROM_DATE")
  TO_DISPLAY=$(date -d "$TO_DATE" +"%d/%m/%Y" 2>/dev/null || date -j -f "%Y-%m-%d" "$TO_DATE" +"%d/%m/%Y" 2>/dev/null || echo "$TO_DATE")
  DATE_RANGE="${FROM_DISPLAY} to ${TO_DISPLAY}"
fi

# Extract commits from git repository using case-insensitive partial match
# Use --reverse to show commits from first to latest
# Include commit hash (%h)
COMMITS_WITH_DETAILS=$(git -C "$PROJECT_DIR" log --author="$USERNAME" --since="$SINCE" --until="$UNTIL" --pretty=format:"%an|%s|%ad|%h" --date=short --all --regexp-ignore-case --reverse)

# Filter out merge and delete branch commits
if [ -n "$COMMITS_WITH_DETAILS" ]; then
  COMMITS_WITH_DETAILS=$(echo "$COMMITS_WITH_DETAILS" | grep -Ev "\|(Merge branch|Delete branch)\|")
fi

# Get unique author names that matched
if [ -n "$COMMITS_WITH_DETAILS" ]; then
  MATCHED_AUTHORS=$(echo "$COMMITS_WITH_DETAILS" | cut -d'|' -f1 | sort -u | tr '\n' ', ' | sed 's/, $//')

  # Count total commits
  TOTAL_COMMITS=$(echo "$COMMITS_WITH_DETAILS" | wc -l | tr -d ' ')

  # ============================================================================
  # CSV MODE - Simple CSV output
  # ============================================================================
  if [ "$CSV_MODE" = true ]; then
    # CSV Header
    COMMITS="No,Commit,Author,Commit Date,Hash"

    # CSV Data rows - escape quotes and handle commas
    echo "$COMMITS_WITH_DETAILS" | awk -F'|' 'BEGIN {OFS=","} {
      no = NR
      commit = $2
      author = $1
      date = $3
      hash = $4
      
      # Escape double quotes by doubling them
      gsub(/"/, "\"\"", commit)
      gsub(/"/, "\"\"", author)
      
      # Wrap in quotes if contains comma, quote, or newline
      if (commit ~ /[,"\n]/) {
        commit = "\"" commit "\""
      }
      if (author ~ /[,"\n]/) {
        author = "\"" author "\""
      }
      
      print no, commit, author, date, hash
    }' >>"$REPORT_FILE.tmp"

    # Combine header and data
    echo "$COMMITS" >"$REPORT_FILE"
    cat "$REPORT_FILE.tmp" >>"$REPORT_FILE"
    rm "$REPORT_FILE.tmp"

  else
    # ============================================================================
    # TABLE FORMATTING - Dynamic column widths with commit message wrapping
    # ============================================================================

    # Set maximum width for commit column (wrapping threshold)
    MAX_COMMIT_WIDTH=50

    # Prepare data with row numbers (now includes hash as 5th field)
    TEMP_DATA=$(echo "$COMMITS_WITH_DETAILS" | awk -F'|' '{print NR"|"$2"|"$1"|"$3"|"$4}')

    # Calculate maximum width for each column
    MAX_NO=$(echo "$TEMP_DATA" | awk -F'|' '{print length($1)}' | sort -rn | head -1)
    MAX_AUTHOR=$(echo "$TEMP_DATA" | awk -F'|' '{print length($3)}' | sort -rn | head -1)
    MAX_DATE=10 # Fixed width for dates (YYYY-MM-DD)
    MAX_HASH=7  # Fixed width for commit hash

    # Ensure minimum widths including headers
    [ "$MAX_NO" -lt 2 ] && MAX_NO=2
    [ "$MAX_AUTHOR" -lt 6 ] && MAX_AUTHOR=6

    # Use fixed max width for commit column
    MAX_COMMIT=$MAX_COMMIT_WIDTH

    # Build the table
    COMMITS=""

    # Header row
    COMMITS+="| $(printf "%-${MAX_NO}s" "No") | $(printf "%-${MAX_COMMIT}s" "Commit") | $(printf "%-${MAX_AUTHOR}s" "Author") | $(printf "%-${MAX_DATE}s" "Commit Date") | $(printf "%-${MAX_HASH}s" "Hash") |"$'\n'

    # Separator line
    COMMITS+="| $(printf '%*s' $MAX_NO '' | tr ' ' '-') | $(printf '%*s' $MAX_COMMIT '' | tr ' ' '-') | $(printf '%*s' $MAX_AUTHOR '' | tr ' ' '-') | $(printf '%*s' $MAX_DATE '' | tr ' ' '-') | $(printf '%*s' $MAX_HASH '' | tr ' ' '-') |"$'\n'

    # Data rows with text wrapping using awk for better handling
    COMMITS+=$(echo "$TEMP_DATA" | awk -F'|' -v max_no="$MAX_NO" -v max_commit="$MAX_COMMIT" -v max_author="$MAX_AUTHOR" -v max_date="$MAX_DATE" -v max_hash="$MAX_HASH" '
    function wrap_line(text, width, lines) {
        delete lines
        if (length(text) <= width) {
            lines[1] = text
            return 1
        }
        
        line_count = 0
        current_line = ""
        word_count = split(text, words, " ")
        
        for (i = 1; i <= word_count; i++) {
            word = words[i]
            if (current_line == "") {
                current_line = word
            } else if (length(current_line " " word) <= width) {
                current_line = current_line " " word
            } else {
                line_count++
                lines[line_count] = current_line
                current_line = word
            }
        }
        if (current_line != "") {
            line_count++
            lines[line_count] = current_line
        }
        return line_count
    }
    
    {
        no = $1
        commit = $2
        author = $3
        date = $4
        hash = $5
        
        line_count = wrap_line(commit, max_commit, wrapped_lines)
        
        printf "| %-" max_no "s | %-" max_commit "s | %-" max_author "s | %-" max_date "s | %-" max_hash "s |\n", no, wrapped_lines[1], author, date, hash
        
        for (i = 2; i <= line_count; i++) {
            printf "| %-" max_no "s | %-" max_commit "s | %-" max_author "s | %-" max_date "s | %-" max_hash "s |\n", "", wrapped_lines[i], "", "", ""
        }
    }
    ')

    # Replace placeholders in template
    REPORT_CONTENT="${TEMPLATE//\{\{USERNAME\}\}/$USERNAME}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{PROJECT_NAME\}\}/$PROJECT_NAME}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{DATE_RANGE\}\}/$DATE_RANGE}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{FROM_DATE\}\}/$FROM_DATE}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{TO_DATE\}\}/$TO_DATE}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{COMMITS\}\}/$COMMITS}"

    # Write report to file using printf to preserve formatting
    printf "%s" "$REPORT_CONTENT" >"$REPORT_FILE"
  fi

else
  MATCHED_AUTHORS=""
  COMMITS=""
  TOTAL_COMMITS=0
fi

# Handle no commits found
if [ -z "$COMMITS" ] || [ "$TOTAL_COMMITS" -eq 0 ]; then
  echo "Warning: No commits found for author matching '$USERNAME' in '$PROJECT_DIR' between $FROM_DATE and $TO_DATE"
  echo ""
  echo "Searching for possible author names in the repository..."

  # Show all unique authors that might match
  POSSIBLE_AUTHORS=$(git -C "$PROJECT_DIR" log --all --pretty=format:"%an" | sort -u | grep -i "$USERNAME")

  if [ -n "$POSSIBLE_AUTHORS" ]; then
    echo "Found these author names containing '$USERNAME':"
    echo "$POSSIBLE_AUTHORS"
    echo ""
    echo "Tip: Your search already uses partial matching. If you see your name above,"
    echo "     there might be no commits in the specified date range."
  else
    echo "No authors found matching '$USERNAME'"
    echo ""
    echo "All authors in this repository:"
    git -C "$PROJECT_DIR" log --all --pretty=format:"%an" | sort -u
  fi

  if [ "$CSV_MODE" = true ]; then
    echo "No,Commit,Author,Commit Date,Hash" >"$REPORT_FILE"
  else
    COMMITS="No commits found for this period."
    REPORT_CONTENT="${TEMPLATE//\{\{USERNAME\}\}/$USERNAME}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{PROJECT_NAME\}\}/$PROJECT_NAME}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{DATE_RANGE\}\}/$DATE_RANGE}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{FROM_DATE\}\}/$FROM_DATE}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{TO_DATE\}\}/$TO_DATE}"
    REPORT_CONTENT="${REPORT_CONTENT//\{\{COMMITS\}\}/$COMMITS}"
    printf "%s" "$REPORT_CONTENT" >"$REPORT_FILE"
  fi
  TOTAL_COMMITS=0
fi

# Display success message with summary
COMMIT_COUNT=$TOTAL_COMMITS

echo ""
echo "✓ Work report generated successfully!"
echo "  File: $REPORT_FILE"
echo "  Directory: $OUTPUT_DIR"
echo "  Repository: $PROJECT_NAME"
if [ -n "$MATCHED_AUTHORS" ]; then
  echo "  Author(s) matched: $MATCHED_AUTHORS"
fi
echo "  Search term: $USERNAME"
echo "  Period: $DATE_RANGE"
echo "  Commits: $COMMIT_COUNT"
