#!/bin/sh
leasefile="/tmp/hosts/odhcpd"
datatype="odhcpd-leases"
publisher="/usr/share/shared-state/publishers/$datatype/01-local.sh"

# Starts publisher when boot
[ -f "$leasefile" ] && "$publisher" "$leasefile"

# Watches real time notify 
inotifywait -mq -e modify "$leasefile" | while read -r _; do
    "$publisher" "$leasefile"
done

