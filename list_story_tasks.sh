#!/usr/bin/env bash
#
# Modified from taicli.sh by Donni Triosa (donni.triosa94@gmail.com)
# Lists all tasks from a specific User Story ID in Taiga
#
# Usage: ./list_story_tasks.sh <story_ref_id>
#

# Function to log errors
log_error() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local error_log="logs/error.log"
    echo "[${timestamp}] $1" | tee -a "$error_log"
}

# Check if story ref ID is provided as argument
if [ "$#" -ne 1 ]; then
    log_error "Error: No user story reference ID provided"
    echo "Usage: $0 <story_ref_id>"
    echo "Example: $0 123 (where 123 is the story reference number)"
    exit 1
fi

STORY_REF_ID="$1"

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading configuration from .env file"
    source .env
else
    log_error "Error: .env file not found!"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Set User Agent to be sent when using cURL
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

# Login to Taiga and get authentication token
AUTH_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -d "{\"type\":\"normal\",\"username\":\"$TAIGA_USER\",\"password\":\"$TAIGA_PASSWORD\"}" \
    "${TAIGA_URL}/api/v1/auth")

AUTH_TOKEN=$(echo $AUTH_RESPONSE | jq -r '.auth_token')
if [ "$AUTH_TOKEN" == "null" ] || [ -z "$AUTH_TOKEN" ]; then
    log_error "Authentication failed. Please check your credentials in .env file."
    exit 1
fi
echo "Authentication successful"

# Get project ID from project slug
PROJECT_RESPONSE=$(curl -X GET \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -s "${TAIGA_URL}/api/v1/projects/by_slug?slug=${PROJECT_SLUG}")

# Extract the project ID
PROJECT_ID=$(echo $PROJECT_RESPONSE | jq -r '.id')

if [ "$PROJECT_ID" == "null" ] || [ -z "$PROJECT_ID" ]; then
    log_error "Failed to fetch Project ID from Project Slug $PROJECT_SLUG"
    log_error "Error: $PROJECT_RESPONSE"
    exit 1
fi

# Get user story ID from ref ID
STORY_RESPONSE=$(curl -X GET \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -s "${TAIGA_URL}/api/v1/userstories/by_ref?ref=${STORY_REF_ID}&project=${PROJECT_ID}")

# Extract the story ID
STORY_ID=$(echo $STORY_RESPONSE | jq -r '.id')
STORY_SUBJECT=$(echo $STORY_RESPONSE | jq -r '.subject')

if [ "$STORY_ID" == "null" ] || [ -z "$STORY_ID" ]; then
    log_error "Failed to fetch Story ID for Story Reference ID $STORY_REF_ID"
    log_error "Error: $STORY_RESPONSE"
    exit 1
fi

echo "Project ID: $PROJECT_ID"
echo "User Story: #$STORY_REF_ID - $STORY_SUBJECT (ID: $STORY_ID)"
echo "----------------------------------------"

# Create output files with timestamp
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
OUTPUT_FILE="logs/tasks_story_${STORY_REF_ID}_${TIMESTAMP}.log"
SIMPLE_OUTPUT_FILE="logs/tasks_story_${STORY_REF_ID}_${TIMESTAMP}.txt"

# Fetch custom attribute definitions
ATTR_DEF_RESPONSE=$(curl -X GET \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -s "${TAIGA_URL}/api/v1/task-custom-attributes?project=${PROJECT_ID}")

# Extract custom attribute IDs
ACTIVITY_DATE_ID=$(echo $ATTR_DEF_RESPONSE | jq -r '.[] | select(.name=="Activity Date") | .id // "null"')
START_TIME_ID=$(echo $ATTR_DEF_RESPONSE | jq -r '.[] | select(.name=="Start Time") | .id // "null"')
TOTAL_TIME_SPENT_ID=$(echo $ATTR_DEF_RESPONSE | jq -r '.[] | select(.name=="Total Time Spent") | .id // "null"')

# Get tasks for the specific user story with pagination
TASKS_RESPONSE=()
CURRENT_PAGE=1
PAGE_SIZE=100  # Adjust this if the API allows for a larger page size

while true; do
    # Fetch tasks for the current page
    RESPONSE=$(curl -X GET \
        -H "Content-Type: application/json" \
        -H "User-Agent: ${USER_AGENT}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -s "${TAIGA_URL}/api/v1/tasks?project=${PROJECT_ID}&user_story=${STORY_ID}&page=${CURRENT_PAGE}&page_size=${PAGE_SIZE}")

    # Check if the response is valid
    if [ "$(echo $RESPONSE | jq 'type')" != "\"array\"" ]; then
        log_error "Failed to fetch tasks for story ID $STORY_ID (ref: $STORY_REF_ID)"
        log_error "Error: $RESPONSE"
        exit 1
    fi

    # Break if no tasks are returned
    TASK_COUNT=$(echo "$RESPONSE" | jq 'length')
    if [ "$TASK_COUNT" -eq 0 ]; then
        break
    fi

    # Append tasks from this page to the main TASKS_RESPONSE array
    TASKS_RESPONSE+=("$RESPONSE")

    # If less tasks than the page size, break (last page)
    if [ "$TASK_COUNT" -lt "$PAGE_SIZE" ]; then
        break
    fi

    # Increment to the next page
    CURRENT_PAGE=$((CURRENT_PAGE + 1))
done

# Consolidate all tasks into a single JSON array
ALL_TASKS=$(printf '%s\n' "${TASKS_RESPONSE[@]}" | jq -s '[.[][]]')
TOTAL_TASKS=$(echo "$ALL_TASKS" | jq 'length')

echo "Total tasks found: $TOTAL_TASKS"

if [ "$TOTAL_TASKS" -eq 0 ]; then
    echo "No tasks found for User Story #$STORY_REF_ID"
    exit 0
fi

# Write header to detailed output file
echo "Task List for User Story #$STORY_REF_ID" > "$OUTPUT_FILE"
echo "Story: $STORY_SUBJECT (ID: $STORY_ID)" >> "$OUTPUT_FILE"
echo "Project: $PROJECT_SLUG (ID: $PROJECT_ID)" >> "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Total Tasks: $TOTAL_TASKS" >> "$OUTPUT_FILE"
echo "=================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Write header to simple output file
echo "$STORY_REF_ID" > "$SIMPLE_OUTPUT_FILE"

# Process each task
echo "$ALL_TASKS" | jq -c '.[]' | while read -r task; do
    # Extract task details
    TASK_ID=$(echo $task | jq -r '.id')
    TASK_REF=$(echo $task | jq -r '.ref')
    TASK_SUBJECT=$(echo $task | jq -r '.subject')
    TASK_STATUS=$(echo $task | jq -r '.status_extra_info.name // "Unknown"')
    TASK_IS_CLOSED=$(echo $task | jq -r '.is_closed')
    TASK_IS_BLOCKED=$(echo $task | jq -r '.is_blocked')
    TASK_CREATED_DATE=$(echo $task | jq -r '.created_date' | cut -d'T' -f1)
    TASK_MODIFIED_DATE=$(echo $task | jq -r '.modified_date' | cut -d'T' -f1)
    ASSIGNED_TO_NAME=$(echo $task | jq -r '.assigned_to_extra_info.full_name // "Unassigned"')
    ASSIGNED_TO_ID=$(echo $task | jq -r '.assigned_to // "null"')

    # Get task custom attributes
    ATTR_RESPONSE=$(curl -X GET \
        -H "Content-Type: application/json" \
        -H "User-Agent: ${USER_AGENT}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -s "${TAIGA_URL}/api/v1/tasks/custom-attributes-values/${TASK_ID}")

    # Initialize custom field variables
    ACTIVITY_DATE="N/A"
    START_TIME="N/A"
    TIME_SPENT="N/A"

    # Extract custom attributes if they exist
    if [ "$(echo $ATTR_RESPONSE | jq 'type')" == "\"object\"" ] && [ "$(echo $ATTR_RESPONSE | jq '.attributes_values')" != "null" ]; then
        # Get values if IDs exist
        if [ "$ACTIVITY_DATE_ID" != "null" ] && [ -n "$ACTIVITY_DATE_ID" ]; then
            ACTIVITY_DATE=$(echo $ATTR_RESPONSE | jq -r ".attributes_values.\"${ACTIVITY_DATE_ID}\" // \"N/A\"")
        fi

        if [ "$START_TIME_ID" != "null" ] && [ -n "$START_TIME_ID" ]; then
            START_TIME=$(echo $ATTR_RESPONSE | jq -r ".attributes_values.\"${START_TIME_ID}\" // \"N/A\"")
        fi

        if [ "$TOTAL_TIME_SPENT_ID" != "null" ] && [ -n "$TOTAL_TIME_SPENT_ID" ]; then
            TIME_SPENT=$(echo $ATTR_RESPONSE | jq -r ".attributes_values.\"${TOTAL_TIME_SPENT_ID}\" // \"N/A\"")
        fi
    fi

    # Write detailed format to .log file
    echo "Task #${TASK_REF} (ID: ${TASK_ID})" | tee -a "$OUTPUT_FILE"
    echo "  Subject: ${TASK_SUBJECT}" | tee -a "$OUTPUT_FILE"
    echo "  Status: ${TASK_STATUS}" | tee -a "$OUTPUT_FILE"
    echo "  Assigned to: ${ASSIGNED_TO_NAME} (ID: ${ASSIGNED_TO_ID})" | tee -a "$OUTPUT_FILE"
    echo "  Closed: ${TASK_IS_CLOSED}" | tee -a "$OUTPUT_FILE"
    echo "  Blocked: ${TASK_IS_BLOCKED}" | tee -a "$OUTPUT_FILE"
    echo "  Created: ${TASK_CREATED_DATE}" | tee -a "$OUTPUT_FILE"
    echo "  Modified: ${TASK_MODIFIED_DATE}" | tee -a "$OUTPUT_FILE"
    echo "  Activity Date: ${ACTIVITY_DATE}" | tee -a "$OUTPUT_FILE"
    echo "  Start Time: ${START_TIME}" | tee -a "$OUTPUT_FILE"
    echo "  Time Spent: ${TIME_SPENT}" | tee -a "$OUTPUT_FILE"
    echo "  ---" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"

    # Write simple format to .txt file (Subject | Activity Date | Start Time | Time Spent)
    echo "${TASK_SUBJECT} | ${ACTIVITY_DATE} | ${START_TIME} | ${TIME_SPENT}" >> "$SIMPLE_OUTPUT_FILE"
done

echo "Task listing completed."
echo "Detailed format saved to: $OUTPUT_FILE"
echo "Simple format saved to: $SIMPLE_OUTPUT_FILE"
echo "Summary: $TOTAL_TASKS tasks found for User Story #$STORY_REF_ID"
exit 0
