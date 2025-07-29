#!/usr/bin/env bash
#
# Created By: Donni Triosa (donni.triosa94@gmail.com)
# Contributor:
# - Dimas Restu Hidayanto (drh.dimasrestu@gmail.com)
#
# Creates subtasks in Taiga from a formatted input file with the format:
# First line: Story ID
# Subsequent lines: Summary|Date|Time|TimeSpent
#

# Function to log errors
log_error() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  local error_log="/home/node/TaiCLIMardi/logs/error.log"
  echo "[${timestamp}] $1" | tee -a "$error_log"
}

# Usage: ./taicli.sh <input_file>
# Check if file is provided as argument
if [ "$#" -ne 1 ]; then
  log_error "Error: No input file provided"
  echo "Usage: $0 <input_file>"
  exit 1
fi

INPUT_FILE="$1"

# Load environment variables from .env file
if [ -f .env ]; then
  echo "Loading configuration from .env file"
  source .env
  # check if the input file exists
  if [ ! -f "$INPUT_FILE" ]; then
    log_error "Error: Input file '$INPUT_FILE' not found!"
    exit 1
  fi
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

# Get User ID from authentication response
TAIGA_USER_ID=$(echo $AUTH_RESPONSE | jq -r '.id')

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

# Read the story ID from first line
read -r STORY_REF_ID < "$INPUT_FILE"

# Get user story ID from ref ID
STORY_RESPONSE=$(curl -X GET \
  -H "Content-Type: application/json" \
  -H "User-Agent: ${USER_AGENT}" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -s "${TAIGA_URL}/api/v1/userstories/by_ref?ref=${STORY_REF_ID}&project=${PROJECT_ID}")

# Extract the story ID
STORY_ID=$(echo $STORY_RESPONSE | jq -r '.id')

if [ "$STORY_ID" == "null" ] || [ -z "$STORY_ID" ]; then
  log_error "Failed to fetch Story ID for Story Reference ID $STORY_REF_ID"
  log_error "Error: $STORY_RESPONSE"
  exit 1
fi

# Get task status ID for Done
STATUS_RESPONSE=$(curl -X GET \
  -H "Content-Type: application/json" \
  -H "User-Agent: ${USER_AGENT}" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -s "${TAIGA_URL}/api/v1/task-statuses?project=${PROJECT_ID}")

# Extract the status "Done" ID
STATUS_DONE_ID=$(echo $STATUS_RESPONSE | jq '.[] | select(.name=="Done")' | jq -r '.id')

if [ "$STATUS_DONE_ID" == "null" ] || [ -z "$STATUS_DONE_ID" ]; then
  log_error "Failed to fetch Status for Done ID with Project ID $PROJECT_ID ($PROJECT_SLUG)"
  log_error "Error: $STATUS_RESPONSE"
  exit 1
fi

# Process each line after the first one until blank line
tail -n +2 "$INPUT_FILE" | while IFS='|' read -r TASK_SUBJECT ACTIVITY_DATE START_TIME TIME_SPENT; do
  # Trim whitespace
  TASK_SUBJECT=$(echo "$TASK_SUBJECT" | xargs)
  ACTIVITY_DATE=$(echo "$ACTIVITY_DATE" | xargs)
  START_TIME=$(echo "$START_TIME" | xargs)
  TIME_SPENT=$(echo "$TIME_SPENT" | xargs)

  #skip empty lines
  if [[ -z "$TASK_SUBJECT" ]]; then
    continue
  fi
  
  # Validate date format
  if ! [[ $ACTIVITY_DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    log_error "Invalid date format for task '$TASK_SUBJECT': $ACTIVITY_DATE (expected YYYY-MM-DD)"
    continue
  fi

  # Extract the month and year from the DATE field
  TASK_YEAR=$(echo "$ACTIVITY_DATE" | cut -d '-' -f 1)
  TASK_MONTH=$(echo "$ACTIVITY_DATE" | cut -d '-' -f 2)

  # Create the log file name based on the task month
  CREATED_TASKS_FILE="logs/created_tasks_$TASK_YEAR-$TASK_MONTH.log"

  # Check if the subtask has already been created
  if grep -q "$TASK_SUBJECT | $ACTIVITY_DATE | $START_TIME | $TIME_SPENT" "$CREATED_TASKS_FILE"; then
    echo "Task '$TASK_SUBJECT' already created, skipping."
    continue
  fi

  # Create the task
  TASK_RESPONSE=$(curl -X POST \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -d "{
      \"subject\": \"${TASK_SUBJECT}\",
      \"assigned_to\": ${TAIGA_USER_ID},
      \"status\": ${STATUS_DONE_ID},
      \"project\": ${PROJECT_ID},
      \"user_story\": ${STORY_ID},
      \"is_blocked\": false,
      \"is_closed\": true
    }" \
    -s "${TAIGA_URL}/api/v1/tasks")

  # Extract the task ID
  TASK_ID=$(echo $TASK_RESPONSE | jq -r '.id')

  if [ "$TASK_ID" == "null" ] || [ -z "$TASK_ID" ]; then
    log_error "Failed to create task: $TASK_SUBJECT"
    log_error "Error: $TASK_RESPONSE"
    continue
  fi

  # Get task custom attributes
  ATTR_RESPONSE=$(curl -X GET \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -s "${TAIGA_URL}/api/v1/task-custom-attributes?task=${TASK_ID}&project=${PROJECT_ID}")

  # Extract the custom attribute ID for "Activity Date"
  ACTIVITY_DATE_ID=$(echo $ATTR_RESPONSE | jq '.[] | select(.name=="Activity Date")' | jq -r '.id')

  if [ "$ACTIVITY_DATE_ID" == "null" ] || [ -z "$ACTIVITY_DATE_ID" ]; then
    log_error "Failed to fetch Custom Attribute ID for 'Activity Date' with Project ID $PROJECT_ID ($PROJECT_SLUG) and Task ID $TASK_ID"
    log_error "Error: $ATTR_RESPONSE"
    continue
  fi

  # Extract the custom attribute ID for "Start Time"
  START_TIME_ID=$(echo $ATTR_RESPONSE | jq '.[] | select(.name=="Start Time")' | jq -r '.id')

  if [ "$START_TIME_ID" == "null" ] || [ -z "$START_TIME_ID" ]; then
    log_error "Failed to fetch Custom Attribute ID for 'Start Time' with Project ID $PROJECT_ID ($PROJECT_SLUG)  and Task ID $TASK_ID"
    log_error "Error: $ATTR_RESPONSE"
    continue
  fi

  # Extract the custom attribute ID for "Total Time Spent"
  TOTAL_TIME_SPENT_ID=$(echo $ATTR_RESPONSE | jq '.[] | select(.name=="Total Time Spent")' | jq -r '.id')

  if [ "$TOTAL_TIME_SPENT_ID" == "null" ] || [ -z "$TOTAL_TIME_SPENT_ID" ]; then
    log_error "Failed to fetch Custom Attribute ID for 'Total Time Spent' with Project ID $PROJECT_ID ($PROJECT_SLUG)  and Task ID $TASK_ID"
    log_error "Error: $ATTR_RESPONSE"
    continue
  fi

  # Update the custom attributes
  CUSTOM_FIELDS_RESPONSE=$(curl -X PATCH \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -d "{
      \"attributes_values\": {
        \"${ACTIVITY_DATE_ID}\": \"${ACTIVITY_DATE}\",
        \"${START_TIME_ID}\": \"${START_TIME}\",
        \"${TOTAL_TIME_SPENT_ID}\": \"${TIME_SPENT}\"
      },
      \"version\": 1
    }" \
    -s "${TAIGA_URL}/api/v1/tasks/custom-attributes-values/${TASK_ID}")

  if echo "$CUSTOM_FIELDS_RESPONSE" | grep -q "error"; then
    log_error "Failed to update custom fields for task: $TASK_ID"
    log_error "Error: $CUSTOM_FIELDS_RESPONSE"
    continue
  fi
    
  echo "$TASK_SUBJECT | $ACTIVITY_DATE | $START_TIME | $TIME_SPENT" >> "$CREATED_TASKS_FILE"
  echo "Subtask '$TASK_SUBJECT' created and the custom fields updated."
done

echo "All tasks done. Check logs for details."
exit 0
