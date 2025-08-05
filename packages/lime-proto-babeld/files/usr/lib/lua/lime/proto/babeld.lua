#!/usr/bin/lua

--! LiMe Proto Babeld
--! Copyright (C) 2018-2024  Gioacchino Mazzurco <gio@altermundi.net>
--!
--! This program is free software: you can redistribute it and/or modify
--! it under the terms of the GNU Affero General Public License as
--! published by the Free Software Foundation, either version 3 of the
--! License, or (at your option) any later version.
--!
--! This program is distributed in the hope that it will be useful,
--! but WITHOUT ANY WARRANTY; without even the implied warranty of
--! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--! GNU Affero General Public License for more details.
--!
--! You should have received a copy of the GNU Affero General Public License
--! along with this program.  If not, see <http://www.gnu.org/licenses/>.

local network = require("lime.network")
local config = require("lime.config")
local fs = require("nixio.fs")
local utils = require("lime.utils") -- Asegurarnos de tener utils

babeld = {}

babeld.configured = false

--- CAMBIO EMPIEZA AQUÍ ---
-- Nueva función "ayudante" para saber si una interfaz está en el puente LAN
function babeld._is_in_lan_bridge(ifname)
	local uci = config.get_uci_cursor()
	local lan_ports = uci:get("network", "lan", "ports") or uci:get("network", "br-lan", "ports")

	if lan_ports then
		for _, port in ipairs(lan_ports) do
			if port == ifname then
				return true
			end
		end
	end
	return false
end
--- CAMBIO TERMINA AQUÍ ---


function babeld.configure(args)
	if babeld.configured then return end
	babeld.configured = true

	utils.log("lime.proto.babeld.configure(...)")

	fs.writefile("/etc/config/babeld", "")

	local uci = config.get_uci_cursor()

	if config.get("network", "babeld_over_librenet6", false) then
		uci:set("babeld", "librenet6", "interface")
		uci:set("babeld", "librenet6", "ifname", "librenet6")
		uci:set("babeld", "librenet6", "type", "tunnel")
	end

	uci:set("babeld", "general", "general")
	uci:set("babeld", "general", "local_port", "30003")
	uci:set("babeld", "general", "ubus_bindings", "true")

	uci:set("babeld", "ula6", "filter")
	uci:set("babeld", "ula6", "type", "redistribute")
	uci:set("babeld", "ula6", "ip", "fc00::/7")
	uci:set("babeld", "ula6", "action", "allow")

	uci:set("babeld", "public6", "filter")
	uci:set("babeld", "public6", "type", "redistribute")
	uci:set("babeld", "public6", "ip", "2000::0/3")
	uci:set("babeld", "public6", "action", "allow")

	uci:set("babeld", "default6", "filter")
	uci:set("babeld", "default6", "type", "redistribute")
	uci:set("babeld", "default6", "ip", "0::0/0")
	uci:set("babeld", "default6", "le", "0")
	uci:set("babeld", "default6", "action", "allow")

	uci:set("babeld", "mesh4", "filter")
	uci:set("babeld", "mesh4", "type", "redistribute")
	uci:set("babeld", "mesh4", "ip", "10.0.0.0/8")
	uci:set("babeld", "mesh4", "action", "allow")

	uci:set("babeld", "mptp4", "filter")
	uci:set("babeld", "mptp4", "type", "redistribute")
	uci:set("babeld", "mptp4", "ip", "172.16.0.0/12")
	uci:set("babeld", "mptp4", "action", "allow")

	uci:set("babeld", "default4", "filter")
	uci:set("babeld", "default4", "type", "redistribute")
	uci:set("babeld", "default4", "ip", "0.0.0.0/0")
	uci:set("babeld", "default4", "le", "0")
	uci:set("babeld", "default4", "action", "allow")

	-- Avoid redistributing extra local addesses
	uci:set("babeld", "localdeny", "filter")
	uci:set("babeld", "localdeny", "type", "redistribute")
	uci:set("babeld", "localdeny", "local", "true")
	uci:set("babeld", "localdeny", "action", "deny")

	-- Avoid redistributing enything else
	uci:set("babeld", "denyany", "filter")
	uci:set("babeld", "denyany", "type", "redistribute")
	uci:set("babeld", "denyany", "action", "deny")

	--- CAMBIO EMPIEZA AQUÍ ---
	-- Añadimos la configuración para que babel funcione sobre el puente LAN 'br-lan'
	utils.log("lime.proto.babeld: Adding babeld configuration for br-lan bridge.")
	uci:set("babeld", "br_lan", "interface")
	uci:set("babeld", "br_lan", "ifname", "br-lan")
	uci:set("babeld", "br_lan", "type", "wireless") -- 'wireless' es más seguro y evita problemas de temporización
	--- CAMBIO TERMINA AQUÍ ---

	uci:save("babeld")

end


--- CAMBIO EMPIEZA AQUÍ ---
-- Esta es la función principal que se modifica por completo.
function babeld.setup_interface(ifname, args)
	-- Si la interfaz es un punto de acceso (AP) o está en el puente LAN, la ignoramos.
	-- El puente LAN ya se configuró de forma global en la función configure().
	if (not args["specific"] and ifname:match("^wlan%d+.ap")) or babeld._is_in_lan_bridge(ifname) then
		utils.log("lime.proto.babeld.setup_interface(%s, ...) ignored because it's an AP or in LAN bridge.", ifname)
		return
	end

	utils.log("lime.proto.babeld.setup_interface(%s, ...) configuring directly without VLAN.", ifname)

	local uci = config.get_uci_cursor()

	-- Ya no usamos createVlanIface. En su lugar, creamos una interfaz estática simple.
	local owrtInterfaceName = network.sanitizeIfaceName(ifname .. "_babeld_if")
	local ipv4, _ = network.primary_address()

	-- Creamos la sección de interfaz en /etc/config/network
	uci:set("network", owrtInterfaceName, "interface")
	uci:set("network", owrtInterfaceName, "proto", "static")
	uci:set("network", owrtInterfaceName, "device", ifname) -- ¡Usamos el dispositivo físico directamente!
	uci:set("network", owrtInterfaceName, "ipaddr", ipv4:host():string())
	uci:set("network", owrtInterfaceName, "netmask", "255.255.255.255")
	uci:save("network")

	-- Creamos la sección de interfaz para babeld en /etc/config/babeld
	local babeldSectionName = "babeld_" .. ifname:gsub("[^%w_]", "_")
	uci:set("babeld", babeldSectionName, "interface")
	uci:set("babeld", babeldSectionName, "ifname", ifname) -- ¡Le decimos a babeld que use la interfaz física!
	uci:set("babeld", babeldSectionName, "type", "wireless")

	uci:save("babeld")
end
--- CAMBIO TERMINA AQUÍ ---


function babeld.runOnDevice(linuxDev, args)
	utils.log("lime.proto.babeld.runOnDevice(%s, ...)", linuxDev)

	--- CAMBIO EMPIEZA AQUÍ ---
	-- También modificamos esta función para que no use VLAN
	utils.log("lime.proto.babeld.runOnDevice(%s, ...) running directly without VLAN.", linuxDev)

	-- Ya no creamos una VLAN. Usamos el dispositivo directamente.
	network.createStatic(linuxDev)

	local libubus = require("ubus")
	local ubus = libubus.connect()
	-- Le decimos a ubus que añada la interfaz física, no una vlan.
	ubus:call('babeld', 'add_interface', { ifname = linuxDev })
	--- CAMBIO TERMINA AQUÍ ---
end

return babeld