#!/bin/sh
CRDT="odhcpd-leases"

ubus call dhcp ipv4leases '{}' 2>/dev/null |
jsonfilter -e '@.device.*.leases[*]' |
while IFS= read -r lease; do
  ip=$(  jsonfilter -s "$lease" -e '@["address"]')
  mac=$( jsonfilter -s "$lease" -e '@["mac"]')
  hn=$(  jsonfilter -s "$lease" -e '@["hostname"]')
  [ -n "$ip" ] && printf '"%s":{"hostname":"%s","mac":"%s"},' "$ip" "$hn" "$mac"
done | sed 's/,$//' | awk '{print "{"$0"}"}' |
shared-state-async insert "$CRDT"

/usr/sbin/odhcpd-update >/dev/null 2>&1   # keep dnsmasq in sync

