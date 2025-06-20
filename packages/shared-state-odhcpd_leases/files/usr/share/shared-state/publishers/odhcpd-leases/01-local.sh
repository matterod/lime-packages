#!/bin/sh

leasefile="$1"; datatype="odhcpd-leases"

awk '
    BEGIN { OFS="" }
    $1 ~ /^[0-9]+$/ {
        epoch=$1; mac=toupper($2); ip=$3; host=$4
        printf "{\"mac\":\"%s\",\"ip\":\"%s\",\"hostname\":\"%s\",\"expires\":%s}\n",
               mac, ip, host, epoch
    }
' "$leasefile" | while read -r json; do
    echo "$json" | shared-state-async insert "$datatype"
done

