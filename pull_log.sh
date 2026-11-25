#!/bin/bash
# Pull /tmp/legacymusic.log off a LegacyMusic device over SSH.
# Usage: ./pull_log.sh [host]   (default 3GS)
HOST="${1:-10.42.0.105}"
export SSHPASS=alpine
SSH="sshpass -e ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
LOG=$(timeout 20 $SSH root@"$HOST" "find /private/var/mobile -name legacymusic.log 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')
if [ -z "$LOG" ]; then
  echo "No legacymusic.log found on $HOST — has the app been launched?"
  exit 1
fi
echo "Log at: $LOG on $HOST"
timeout 30 $SSH root@"$HOST" "cat '$LOG'" 2>/dev/null | grep -E "DoH|SOCKS|DIAG|LTNW|Unblock|doh|socks"