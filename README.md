# TaiCLI (Taiga Automation Scripts)
A scripts to automate task creation in Taiga project management tool.

## Overview
These scripts help you create tasks in Taiga from the command line or from a bulk input file, with support for custom fields like Activity Date, Start Time, and Total Time Spent.

## Prerequisites
- Bash
- cURL
- JQ (JSON Query CLI)
- Taiga Account with API Access

## Installation
1. Clone the repository:
    ```bash
    git clone https://github.com/donnitriosa/TaiCLI.git
    cd taicli
    ```
2. Make the scripts executable:
    ```bash
    chmod +x *.sh
    ```
   This grants execute permissions to all shell scripts in the directory.
3. Install JSON Query CLI
    ```bash
    sudo apt-get -y install jq
    ```
4. Create directories for logs and tasks:
    ```bash
    mkdir -p logs tasks
    ```

## Setup
1.  Create a .env file in the script directory with the following variables:
```
TAIGA_URL="https://your-taiga-domain.com"
TAIGA_USER="your_email_or_username"
TAIGA_PASSWORD="your_password"
PROJECT_SLUG="ABCD"
```
Replace the values with your actual Taiga credentials and IDs.

## Scripts
Create multiple tasks from a structured input file.
`./taicli.sh tasks/task.txt`

#### Input File Format
```
STORY_REF_ID
Task Subject | YYYY-MM-DD | HH:MM | Minutes
Another Task | YYYY-MM-DD | HH:MM | Minutes

```
- File should be in Unix format or using "LF" instead of "CRLF"
- First line: The ID of the user story where tasks will be created
- Following lines: Task data with fields separated by  `|`  character:
  - Task subject
  - Activity date (YYYY-MM-DD format)
  - Start time (HH:MM format)
  - Time spent (in minutes)
- Don't forget to add empty line in the buttom of file

## Logs
All operations are logged in the  logs  directory:
- `error.log`: Contains error messages
- `created_tasks_YYYY-MM.log`: Lists tasks created in a specific year and month

## Example   
#### Example Task File
```
597462
Daily Standup Meeting | 2025-06-02 | 09:30 | 30
Code Review Session | 2025-06-02 | 14:00 | 120

```
Run With:
`./taicli.sh tasks/task.txt`
