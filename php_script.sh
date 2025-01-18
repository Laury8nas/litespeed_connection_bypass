#!/bin/bash

# Define log files
LOG_FILE="php_bypass.log"

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
}

# Create log file if it doesn't exist
touch "$LOG_FILE"
log_message "Script started"

# Store script's PID
echo $$ > .script_pid

# Flag to indicate if the script is reverting changes
is_reverting=0

# Function to clean up all temporary files
cleanup_temp_files() {
    log_message "Starting cleanup of temporary files."

    # Remove .script_pid
    if [ -f ".script_pid" ]; then
        rm -f .script_pid
        log_message "Deleted .script_pid"
    fi

    # Remove .timer_pid
    if [ -f ".timer_pid" ]; then
        rm -f .timer_pid
        log_message "Deleted .timer_pid"
    fi

    # Remove .monitor_php_pid
    if [ -f ".monitor_php_pid" ]; then
        rm -f .monitor_php_pid
        log_message "Deleted .monitor_php_pid"
    fi

    # Remove .php_server_pid
    if [ -f ".php_server_pid" ]; then
        rm -f .php_server_pid
        log_message "Deleted .php_server_pid"
    fi
    
    # Remove .php_server_pi
    if [ -f ".background_pid" ]; then
        rm -f .background_pid
        log_message "Deleted .background_pid"
    fi

    log_message "Cleanup of temporary files completed."
}

# Function to handle script exit
on_exit() {
    if [ "$is_reverting" -eq 1 ]; then
        log_message "Script is exiting after reversion. Performing cleanup."
        cleanup_temp_files
    else
        log_message "Script is exiting without performing cleanup."
    fi
}

# Trap signals to ensure cleanup on exit only during reversion
trap on_exit EXIT
trap on_exit SIGINT SIGTERM

# Function to check if script is already running
check_running() {
    if [ -f ".php_server_pid" ]; then
        if ps -p "$(cat .php_server_pid)" > /dev/null 2>&1; then
            echo "Error! Development server is already running! If you want to change the PHP version, please stop the server with option 2 and run it again!"
            log_message "Error: Development server is already running!"
            log_message "Please wait for the timer to finish (59 minutes) or use option 2 to revert changes."
            exit 1
        else
            # Clean up stale PID file
            rm -f .php_server_pid
            log_message "Cleaned up stale PHP server PID file"
        fi
    fi

    # Check for any backup files
    if ls wp-config.php.backup_* 1> /dev/null 2>&1 || ls .htaccess.backup_* 1> /dev/null 2>&1; then
        log_message "Error: Backup files from previous run detected!"
        log_message "Please use option 2 to revert changes before starting a new session."
        exit 1
    fi
}

# Function to check if wp-config.php exists
check_wp_config() {
    if [ ! -f "wp-config.php" ]; then
        log_message "Error: wp-config.php file is missing!"
        exit 1
    fi
}

# Function to modify wp-config.php
modify_wp_config() {
    # Create backup with timestamp
    backup_name="wp-config.php.backup_$(date +%s)"
    cp wp-config.php "$backup_name"
    log_message "Created backup of wp-config.php as $backup_name"

    # Create temporary file
    tmp_file=$(mktemp)

    # Process the file line by line
    while IFS= read -r line; do
        echo "$line" >> "$tmp_file"
        # After table_prefix line, add our new configurations
        if [[ $line == *"table_prefix"* ]]; then
            echo "
define('FORCE_SSL_ADMIN', true);
if (strpos(\$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false)
    \$_SERVER['HTTPS']='on';
" >> "$tmp_file"
        fi
    done < wp-config.php

    # Replace original file with modified version
    mv "$tmp_file" wp-config.php
    log_message "Modified wp-config.php with SSL configurations"
}

# Function to handle .htaccess
modify_htaccess() {
    if [ -f ".htaccess" ]; then
        mv .htaccess ".htaccess.backup_$(date +%s)"
        log_message "Created backup of .htaccess"
    fi

    cat <<EOL > .htaccess
RewriteEngine On

RewriteRule .* - [E=noabort:1]
RewriteRule .* - [E=noconntimeout:1]

<IfModule mod_rewrite.c>
    RewriteEngine On

    RewriteRule ^plugins\.php$ /wp-admin/plugins.php [R=301,L]
    RewriteRule ^themes\.php$ /wp-admin/themes.php [R=301,L]
    RewriteRule ^users\.php$ /wp-admin/users.php [R=301,L]
    RewriteRule ^options\.php$ /wp-admin/options.php [R=301,L]
    RewriteRule ^admin\.php$ /wp-admin/admin.php [R=301,L]
    RewriteRule ^options-general\.php$ /wp-admin/options-general.php [R=301,L]
    RewriteRule ^edit\.php$ /wp-admin/edit.php [R=301,L]
    RewriteRule ^post\.php$ /wp-admin/post.php [R=301,L]
    RewriteRule ^upload\.php$ /wp-admin/upload.php [R=301,L]
    RewriteRule ^media-new\.php$ /wp-admin/media-new.php [R=301,L]
    RewriteRule ^nav-menus\.php$ /wp-admin/nav-menus.php [R=301,L]
    RewriteRule ^widgets\.php$ /wp-admin/widgets.php [R=301,L]
    RewriteRule ^tools\.php$ /wp-admin/tools.php [R=301,L]
    RewriteRule ^update-core\.php$ /wp-admin/update-core.php [R=301,L]
    RewriteRule ^edit-comments\.php$ /wp-admin/edit-comments.php [R=301,L]


    RewriteRule ^(.*)\$ http://0.0.0.0:12345/\$1 [P,L]
</IfModule>
EOL
    log_message "Created new .htaccess file with proxy rules"
}

# Function to kill PHP development server
kill_php_server() {
    # Kill all PHP development server processes
    pkill php
    log_message "Stopped all PHP development server processes"

    # Clean up PID file if it exists
    if [ -f ".php_server_pid" ]; then
        rm -f .php_server_pid
        log_message "Removed PHP server PID file"
    fi
}

# Function to monitor PHP server and restart on memory exhaustion
monitor_php_server() {
    local php_version="$1"
    local restart_count=0
    local max_restarts=10

    while true; do
        if [ -f ".php_server_pid" ]; then
            php_pid=$(cat .php_server_pid)
            if ! ps -p "$php_pid" > /dev/null 2>&1; then
                log_message "PHP development server (PID: $php_pid) has terminated."

                # Check if php_server.log contains memory exhaustion error
                if grep -i "allowed memory size" php_server.log; then
                    if [ "$restart_count" -lt "$max_restarts" ]; then
                        log_message "Detected memory exhaustion error. Restarting PHP server. (Restart count: $((restart_count + 1)))"
                        restart_count=$((restart_count + 1))
                        start_php_server "$php_version"
                    else
                        log_message "Maximum restart attempts reached. Not restarting PHP server."
                        break
                    fi
                else
                    if [ "$restart_count" -lt "$max_restarts" ]; then
                        log_message "PHP server terminated due to unexpected reason. Trying to restart. (Restart count: $((restart_count + 1)))"
                        restart_count=$((restart_count + 1))
                        start_php_server "$php_version"
                    else
                        log_message "PHP server failed to launch. Not restarting anymore."
                    fi
                fi
            fi
        fi
        sleep 10
    done
}

# Function to kill all related processes except the current one
kill_all_processes() {
    # Kill PHP server
    kill_php_server

    # Kill the monitor_php_server process if it exists
    if [ -f ".monitor_php_pid" ]; then
        monitor_pid=$(cat .monitor_php_pid)
        if ps -p "$monitor_pid" > /dev/null 2>&1; then
            kill "$monitor_pid" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "Killed monitor_php_server process (PID: $monitor_pid)"
            else
                log_message "Failed to kill monitor_php_server process (PID: $monitor_pid) or it does not exist"
            fi
        fi
        rm -f .monitor_php_pid
        cleanup_temp_files
        log_message "Removed .monitor_php_pid"
    fi

    # Kill the countdown_timer process if its PID is stored
    if [ -f ".timer_pid" ]; then
        timer_pid=$(cat .timer_pid)
        if ps -p "$timer_pid" > /dev/null 2>&1; then
            kill "$timer_pid" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "Killed countdown_timer process (PID: $timer_pid)"
            else
                log_message "Failed to kill countdown_timer process (PID: $timer_pid) or it does not exist"
            fi
        fi
        rm -f .timer_pid
        log_message "Removed .timer_pid"
    fi

    # Kill any sleep processes started by the countdown_timer
    if [ -n "$timer_pid" ] && ps -p "$timer_pid" > /dev/null 2>&1; then
        # Find all sleep processes with timer_pid as parent
        sleep_pids=$(pgrep -P "$timer_pid" sleep)
        if [ -n "$sleep_pids" ]; then
            kill -9 $sleep_pids 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "Killed sleep processes associated with countdown_timer (PIDs: $sleep_pids)"
            else
                log_message "Failed to kill some sleep processes associated with countdown_timer"
            fi
        fi
    fi

    log_message "All related processes have been killed."
}

# Function to revert changes
revert_changes() {
    is_reverting=1
    log_message "Starting reversion of all changes"

    # Restore wp-config.php
    latest_wp_config_backup=$(ls -t wp-config.php.backup_* 2>/dev/null | head -1)
    if [ -n "$latest_wp_config_backup" ]; then
        mv "$latest_wp_config_backup" wp-config.php
        log_message "Restored wp-config.php from backup ($latest_wp_config_backup)"
    else
        log_message "No wp-config.php backup found to restore"
    fi

    # Restore .htaccess
    latest_htaccess_backup=$(ls -t .htaccess.backup_* 2>/dev/null | head -1)
    if [ -n "$latest_htaccess_backup" ]; then
        mv "$latest_htaccess_backup" .htaccess
        log_message "Restored .htaccess from backup ($latest_htaccess_backup)"
    else
        log_message "No .htaccess backup found to restore"
    fi

    # Clean up any remaining backup files
    rm -f wp-config.php.backup_* .htaccess.backup_* 2>/dev/null
    log_message "Cleaned up all backup files"

    # Kill all related processes after restoration
    kill_all_processes

    log_message "All changes have been reverted successfully"
    echo "All changes have been reverted successfully. Check $LOG_FILE for details."

    # Explicitly call cleanup to ensure all temp files are deleted
    cleanup_temp_files

    exit 0
}

# Function to start PHP server
start_php_server() {
    local php_version=$1

    # Kill any existing PHP development servers first
    kill_php_server

    # Clear previous PHP server log
    #> php_server.log

    # Start new PHP server with additional configuration parameters
    PHP_CLI_SERVER_WORKERS=10 /opt/alt/php${php_version}/usr/bin/php \
      -d upload_max_filesize=32G \
      -d post_max_size=32G \
      -d memory_limit=32G \
      -d max_input_time=3600 \
      -d max_execution_time=3600 \
      -S 0.0.0.0:12345 >> php_server.log 2>&1 &
    php_server_pid=$!
    echo "$php_server_pid" > .php_server_pid
    log_message "Started PHP $php_version development server on port 12345 (PID: $php_server_pid)"
}

# Function to display countdown timer
countdown_timer() {
    local end_time=$(($(date +%s) + 3540)) # 59 minutes in seconds

    while [ $(date +%s) -lt $end_time ]; do
        remaining=$((end_time - $(date +%s)))
        minutes=$((remaining / 60))
        seconds=$((remaining % 60))
        log_message "Time remaining: ${minutes}m ${seconds}s"
        sleep 60
    done

    log_message "Timer completed. Starting automatic reversion."
    revert_changes
}

start_timer() {
    # Check if the timer PID file exists
    if [ -f ".timer_pid" ]; then
        # Check if the timer process is still running
        timer_pid=$(cat .timer_pid)
        if ps -p "$timer_pid" > /dev/null 2>&1; then
            log_message "Timer is already running (PID: $timer_pid). Skipping timer start."
            return
        else
            # Stale PID file, remove it
            rm -f .timer_pid
            log_message "Stale timer PID file detected and removed."
        fi
    fi

    # Start the timer
    countdown_timer &
    timer_pid=$!
    echo "$timer_pid" > .timer_pid
    log_message "Started countdown_timer in background (PID: $timer_pid)"
}

# Function to start monitor_php_server in background
start_monitor() {
    monitor_php_server "$1" &
    monitor_pid=$!
    echo "$monitor_pid" > .monitor_php_pid
    log_message "Started monitor_php_server in background (PID: $monitor_pid)"
}

# Function to perform all setup steps in background
background_setup() {
    php_version="$1"

    # Perform necessary checks and modifications
    check_running
    check_wp_config
    modify_wp_config
    modify_htaccess

    # Start PHP server
    start_php_server "$php_version"

    # Start monitoring PHP server
    start_monitor "$php_version"

    # Start countdown timer
    start_timer

    log_message "Development environment setup complete"
    echo "Development environment setup complete!"
    echo "PHP server running on http://0.0.0.0:12345"
    echo "Changes will be automatically reverted in 59 minutes"
    echo "Process is running in background. You can close this terminal."
    echo "Check $LOG_FILE for detailed logs"

    exit 0
}

# Main menu function
main_menu() {
    
    if [ -f ".timer_pid" ]; then
        log_message "Timer is already running. Skipping timer start."
    else
        # Start the timer since it is not running
        countdown_timer &
        timer_pid=$!
        echo "$timer_pid" > .timer_pid
        log_message "Started countdown_timer in background (PID: $timer_pid)"
    fi
    
    echo "Select an option:"
    echo "1. Create bypassing scheme"
    echo "2. Revert changes"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            echo "Select PHP version:"
            echo "0. PHP 5.6"
            echo "1. PHP 7.2"
            echo "2. PHP 7.4"
            echo "3. PHP 8.0"
            echo "4. PHP 8.1"
            echo "5. PHP 8.2"
            echo "6. PHP 8.3"
            read -p "Enter your choice (1-6): " php_choice

            case $php_choice in
                0) php_version="56";;
                1) php_version="72";;
                2) php_version="74";;
                3) php_version="80";;
                4) php_version="81";;
                5) php_version="82";;
                6) php_version="83";;
                *)
                    log_message "Invalid PHP version selected"
                    echo "Invalid choice"
                    if [ -f ".php_server_pid" ] && ps -p "$(cat .php_server_pid)" > /dev/null 2>&1; then
                        # PHP is running, keep the PID files
                        log_message "PHP server is still running, keeping PID files"
                    else
                        # PHP is not running, clean up PID files
                        if [ -f ".script_pid" ]; then
                            rm -f .script_pid
                            log_message "Cleaned up .script_pid"
                        fi
                        if [ -f ".timer_pid" ]; then
                            rm -f .timer_pid
                            log_message "Cleaned up .timer_pid"
                        fi
                    fi
                    exit 1
                    ;;
            esac
            
            check_running
            
            # Start the background setup process
            nohup bash "$0" --background "$php_version" >/dev/null 2>&1 &
            background_pid=$!
            echo "$background_pid" > .background_pid
            log_message "Development environment setup is running in the background (PID: $background_pid)"
            echo "Development environment setup is running in the background."
            echo "You can close this terminal."
            echo "Check $LOG_FILE for detailed logs"
            exit 0
            ;;
        2)
            revert_changes
            ;;
        *)
            log_message "Invalid option selected"
            echo "Invalid choice"
            if [ -f ".php_server_pid" ] && ps -p "$(cat .php_server_pid)" > /dev/null 2>&1; then
                # PHP is running, keep the PID files
                log_message "PHP server is still running, keeping PID files"
            else
                # PHP is not running, clean up PID files
                if [ -f ".script_pid" ]; then
                    rm -f .script_pid
                    log_message "Cleaned up .script_pid"
                fi
                if [ -f ".timer_pid" ]; then
                    rm -f .timer_pid
                    log_message "Cleaned up .timer_pid"
                fi
            fi
            exit 1
            ;;
    esac
}

# Background mode execution
if [ "$1" == "--background" ]; then
    php_version="$2"

    # Perform all setup steps in the background
    background_setup "$php_version"
fi

# If not in background mode, display the main menu
main_menu

# Keep the script running to prevent EXIT trap from triggering cleanup
# This ensures that the main script doesn't exit and clean up temp files
# You can remove the following lines if you prefer the script to exit,
# but ensure that the EXIT trap doesn't perform cleanup in that case
wait
