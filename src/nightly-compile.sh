#!/bin/bash
# Cron entry point for the nightly friction compiler.
# Writes a dated proposal file. Cheap: pure file mining, no LLM call.
# Enable with:  crontab -e   then add:
#   0 7 * * *  /bin/bash ~/.claude/quality-loop/nightly-compile.sh
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$QL" || exit 1
mkdir -p logs
OUT=$(python3 nightly-compile.py 2>>logs/compile-errors.log)
echo "$(date '+%Y-%m-%d %H:%M') wrote $OUT" >> logs/compile.log
