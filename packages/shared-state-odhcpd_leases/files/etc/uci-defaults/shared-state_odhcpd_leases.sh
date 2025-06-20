#!/bin/sh

uci -q get shared-state.odhcpd_leases || {
    uci add shared-state odhcpd_leases
    uci set shared-state.@odhcpd_leases[-1].name='odhcpd-leases'
    uci set shared-state.@odhcpd_leases[-1].scope='community'
    uci set shared-state.@odhcpd_leases[-1].ttl='4200'          
    uci commit shared-state
}

