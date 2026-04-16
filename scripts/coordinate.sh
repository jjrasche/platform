#!/usr/bin/env bash
# coordinate.sh — Spawn focused Claude Code workers per repo
#
# Usage:
#   ./scripts/coordinate.sh "Deploy the finance domain end-to-end"
#   ./scripts/coordinate.sh --repo family-agent "Add the allowance execute handler"
#   ./scripts/coordinate.sh --status           # Check running workers
#   ./scripts/coordinate.sh --review           # Quality review across all repos
#
# Workers run headless (claude -p) in the target repo directory.
# Results are logged to ~/.claude/coordination/logs/
# The shared contract lives at ~/.claude/coordination/contracts.md

set -euo pipefail

WORKSPACE="$HOME/Documents/workspace"
COORD_DIR="$HOME/.claude/coordination"
LOG_DIR="$COORD_DIR/logs"
CONTRACTS="$COORD_DIR/contracts.md"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Known repos in the ecosystem
declare -A REPOS=(
  [platform]="$WORKSPACE/platform"
  [family-agent]="$WORKSPACE/family-agent"
  [thalamus]="$WORKSPACE/thalamus"
  [unified-memory]="$WORKSPACE/unified-memory"
  [house-ops]="$WORKSPACE/house-ops"
)

mkdir -p "$LOG_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Spawn a headless Claude worker in a specific repo
spawn_worker() {
  local repo="$1"
  local prompt="$2"
  local repo_path="${REPOS[$repo]}"
  local log_file="$LOG_DIR/${repo}-${TIMESTAMP}.md"

  if [[ ! -d "$repo_path" ]]; then
    log "SKIP $repo — repo not found at $repo_path"
    return 1
  fi

  local full_prompt="You are a worker agent in the $repo repo, part of the family agent platform ecosystem.
Read CLAUDE.md and the ecosystem table first.
Read ~/.claude/coordination/contracts.md for shared interface contracts.

TASK: $prompt

RULES:
- Stay within this repo's ownership boundaries (see ecosystem table)
- If you need to change a shared contract, DO NOT change it — write the proposed change to ~/.claude/coordination/proposals/${repo}-${TIMESTAMP}.md
- Run tests before committing
- Follow coding standards from ~/.claude/references/coding-standards.md
- When done, write a summary to ~/.claude/coordination/logs/${repo}-${TIMESTAMP}-result.md"

  log "SPAWN $repo → $log_file"
  claude -p "$full_prompt" --cwd "$repo_path" > "$log_file" 2>&1 &
  echo $! > "$LOG_DIR/${repo}-${TIMESTAMP}.pid"
  log "  PID: $(cat "$LOG_DIR/${repo}-${TIMESTAMP}.pid")"
}

# Check status of running workers
check_status() {
  log "=== Worker Status ==="
  for pid_file in "$LOG_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    local pid=$(cat "$pid_file")
    local name=$(basename "$pid_file" .pid)
    if kill -0 "$pid" 2>/dev/null; then
      log "  RUNNING: $name (PID $pid)"
    else
      log "  DONE:    $name (PID $pid)"
      rm -f "$pid_file"
    fi
  done
}

# Quality review — spawn a reviewer that checks all recent results
run_review() {
  local review_prompt="Review all files in ~/.claude/coordination/logs/ from today.
For each worker result:
1. Did it stay within its repo's ownership boundary?
2. Did it follow coding standards?
3. Are there any proposed contract changes that need coordination?
4. Are there test gaps?
Write a consolidated review to ~/.claude/coordination/logs/review-${TIMESTAMP}.md"

  log "SPAWN review worker"
  claude -p "$review_prompt" --cwd "$WORKSPACE/platform" > "$LOG_DIR/review-${TIMESTAMP}.md" 2>&1 &
  log "  Review PID: $!"
}

# Main
case "${1:-}" in
  --status)
    check_status
    ;;
  --review)
    run_review
    ;;
  --repo)
    repo="$2"
    shift 2
    spawn_worker "$repo" "$*"
    ;;
  --help|-h)
    head -8 "$0" | tail -7
    ;;
  *)
    if [[ -z "${1:-}" ]]; then
      echo "Usage: $0 <goal> | --repo <name> <task> | --status | --review"
      exit 1
    fi
    # High-level goal — the coordinator (you, in an interactive session)
    # breaks this into per-repo tasks and calls spawn_worker for each.
    # This is the manual dispatch mode — pass a goal and repo:
    echo "For high-level goals, use the interactive coordinator session."
    echo "It will break the goal into tasks and call: $0 --repo <name> <task>"
    echo ""
    echo "Or dispatch directly:"
    echo "  $0 --repo platform 'Run the finance domain migration'"
    echo "  $0 --repo family-agent 'Add the allowance execute handler'"
    ;;
esac
