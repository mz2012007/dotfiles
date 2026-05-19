#!/usr/bin/env bash
# -------------------------------------------
# Open a new terminal, run tmux session inside it
# Capture stdout and stderr to separate logs
# -------------------------------------------

# Configuration
SCRIPT_TO_RUN="sudo $HOME/dev/backup_lvm/backup_lvm.sh"
SESSION_NAME="backup_session"
LOG_DIR_STAT="$HOME/dev/backup_lvm/logs/stat"
LOG_DIR_ERROR="$HOME/dev/backup_lvm/logs/error"

TIMESTAMP=$(date +"%Y-%m-%d_%I:%M:%S%p_%a-%b-%y")
STDOUT_LOG="$LOG_DIR_STAT/backup_$TIMESTAMP.log"
STDERR_LOG="$LOG_DIR_ERROR/backup_error_$TIMESTAMP.log"

TERMINAL_CMD="alacritty -e "

mkdir -p $LOG_DIR_ERROR
mkdir -p $LOG_DIR_STAT
# Kill session if exists
tmux has-session -t "$SESSION_NAME" 2>/dev/null && tmux kill-session -t "$SESSION_NAME"

#alacritty -e tmux new-session -n "mz" "echo 'hello' ; fish"
# Run terminal and tmux session inside it
$TERMINAL_CMD tmux new-session -n "$SESSION_NAME" \
  "bash -c '$SCRIPT_TO_RUN > >(tee -a \"$STDOUT_LOG\") 2> >(tee -a \"$STDERR_LOG\" >&2); exec fish'"

echo "Backup script started in a new terminal with tmux session '$SESSION_NAME'"
echo "STDOUT -> $STDOUT_LOG"
echo "STDERR -> $STDERR_LOG"
