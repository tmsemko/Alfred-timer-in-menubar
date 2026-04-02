#!/bin/bash

# Launch or refresh the menubar timer
# Kills any existing instance and starts a new one so it picks up the latest timers.json

DIR="$(cd "$(dirname "$0")" && pwd)"

# Kill existing instance(s)
pkill -f "${DIR}/menubar_timer" 2>/dev/null

# Only launch if there are active timers
json=$(cat "${alfred_workflow_cache}/timers.json" 2>/dev/null || echo "{}")
if [ "$json" != "{}" ] && [ -n "$json" ]; then
    nohup "${DIR}/menubar_timer" "${alfred_workflow_cache}" > /dev/null 2>&1 &
fi
