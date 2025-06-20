#!/bin/sh /etc/rc.common

USE_PROCD=1
START=62            # after odhcpd, before lime-system

start_service() {
    procd_open_instance
    procd_set_param command /usr/lib/lime/lease-syncd.sh
    procd_set_param respawn 5 30 0    # (threshold 5s, timeout 30s, unlimited retries)
    procd_close_instance
}
