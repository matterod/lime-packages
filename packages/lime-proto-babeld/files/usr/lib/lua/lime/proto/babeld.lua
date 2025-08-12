#!/usr/bin/lua

--! LiMe Proto Babeld
--! Copyright (C) 2018-2024  Gioacchino Mazzurco
--! License: AGPL-3.0-or-later

local network = require("lime.network")
local config  = require("lime.config")
local fs      = require("nixio.fs")
local utils   = require("lime.utils")

babeld = {}
babeld.configured = false

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

-- ¿ifname es miembro (esclavo) del puente br-lan?
-- 1) runtime: /sys/class/net/<ifname>/master -> .../br-lan
-- 2) fallback: UCI (targets viejos con "ports")
function babeld._is_in_lan_bridge(ifname)
	-- Chequeo runtime (DSA y también swconfig)
	local master = fs.readlink("/sys/class/net/" .. ifname .. "/master")
	if master and master:match("br%-lan") then
		return true
	end
	-- Fallback UCI (algunos targets viejos)
	local uci = config.get_uci_cursor()
	local lan_ports = uci:get("network", "lan", "ports") or uci:get("network", "br-lan", "ports")
	if lan_ports then
		for _, p in ipairs(lan_ports) do
			if p == ifname then return true end
		end
	end
	return false
end

-- ¿Existe br-lan en runtime?
local function br_lan_exists()
	return fs.access("/sys/class/net/br-lan") == true
end

-- ¿El bridge tiene miembros Wi-Fi?
local function _bridge_has_wifi_members(brname)
	local dir = "/sys/class/net/"..brname.."/brif"
	if not fs.access(dir) then return false end
	local it = fs.dir(dir)
	if not it then return false end
	for m in it do
		if fs.access("/sys/class/net/"..m.."/phy80211") then
			return true
		end
	end
	return false
end

-- ¿La iface es Wi-Fi?
local function _is_wifi(ifname)
	return fs.access("/sys/class/net/"..ifname.."/phy80211") == true
end

-- ¿Tiene carrier (cable enchufado)?
local function _carrier_up(ifname)
	local path = "/sys/class/net/"..ifname.."/carrier"
	if not fs.access(path) then return true end -- si no existe, no bloqueamos
	local v = fs.readfile(path)
	return v and v:match("^1")
end

-- Set de ifaces cableadas preferidas desde UCI:
--   list babeld_wired_ifaces 'lan4' ...
local function _wired_preferred_set()
	local uci = config.get_uci_cursor()
	local t = {}
	-- La opción está en la sección "network" (lime), ej:
	-- config lime 'network'
	--   list babeld_wired_ifaces 'lan4'
	local listv = uci:get("network", "network", "babeld_wired_ifaces")
	if type(listv) == "table" then
		for _, n in ipairs(listv) do t[n] = true end
	elseif type(listv) == "string" then
		t[listv] = true
	end
	return t
end

-- Crear o borrar la regla ebtables según "babeld_over_batman"
-- Si está en false, evitamos que los Hellos de Babel se desvíen por bat0 (aplana topología)
local function ensure_babel_over_batman_firewall()
	local over_bat = config.get("network", "babeld_over_batman", false)
	local path = "/etc/firewall.lime.d/21-babeld-not-over-bat0-ebtables"

	if over_bat then
		if fs.stat(path) then fs.unlink(path) end
		utils.log("babeld_over_batman=true: no se instala regla ebtables")
	else
		local script = [[
#!/bin/sh
# Evitar que Babel "viaje" por bat0 (aplana la topología)
# Bloquea paquetes IPv6 UDP con destino puerto 6696 saliendo por bat0
ebtables -t broute -A BROUTING -p IPv6 --ip6-protocol udp --ip6-dport 6696 -o bat0 -j DROP
]]
		fs.writefile(path, script)
		fs.chmod(path, 493) -- 0755
		utils.log("babeld_over_batman=false: instalada regla ebtables en " .. path)
	end
end

-- Aplicar perfil wired/wireless a br-lan:
--   option babeld_brlan_profile 'auto|wired|wireless'  (default: auto)
--   option babeld_wired_rxcost '96'                    (si wired)
local function _apply_brlan_profile(uci)
	local profile = tostring(config.get("network", "babeld_brlan_profile", "auto"))
	local want_type
	if profile == "wired" then
		want_type = "wired"
	elseif profile == "wireless" then
		want_type = "wireless"
	else
		want_type = _bridge_has_wifi_members("br-lan") and "wireless" or "wired"
	end
	uci:set("babeld", "br_lan", "type", want_type)

	if want_type == "wired" then
		local rx = tostring(config.get("network", "babeld_wired_rxcost", "96"))
		uci:set("babeld", "br_lan", "rxcost", rx)
	end
	utils.log(("babeld br-lan: profile=%s → type=%s"):format(profile, want_type))
end

-----------------------------------------------------------------------
-- configure(): configurar filtros y, si existe, sumar br-lan (una vez)
-----------------------------------------------------------------------
function babeld.configure(args)
	if babeld.configured then return end
	babeld.configured = true

	utils.log("lime.proto.babeld.configure(...)")
	fs.writefile("/etc/config/babeld", "") -- reset limpio

	local uci = config.get_uci_cursor()

	if config.get("network", "babeld_over_librenet6", false) then
		uci:set("babeld", "librenet6", "interface")
		uci:set("babeld", "librenet6", "ifname", "librenet6")
		uci:set("babeld", "librenet6", "type", "tunnel")
	end

	uci:set("babeld", "general", "general")
	uci:set("babeld", "general", "local_port", "30003")
	uci:set("babeld", "general", "ubus_bindings", "true")

	-- Filtros típicos
	uci:set("babeld", "ula6", "filter");     uci:set("babeld", "ula6", "type", "redistribute");  uci:set("babeld", "ula6", "ip", "fc00::/7");     uci:set("babeld", "ula6", "action", "allow")
	uci:set("babeld", "public6", "filter");  uci:set("babeld", "public6", "type", "redistribute"); uci:set("babeld", "public6", "ip", "2000::0/3");  uci:set("babeld", "public6", "action", "allow")
	uci:set("babeld", "default6", "filter"); uci:set("babeld", "default6", "type", "redistribute"); uci:set("babeld", "default6", "ip", "0::0/0");   uci:set("babeld", "default6", "le", "0"); uci:set("babeld", "default6", "action", "allow")
	uci:set("babeld", "mesh4", "filter");    uci:set("babeld", "mesh4", "type", "redistribute");   uci:set("babeld", "mesh4", "ip", "10.0.0.0/8");   uci:set("babeld", "mesh4", "action", "allow")
	uci:set("babeld", "mptp4", "filter");    uci:set("babeld", "mptp4", "type", "redistribute");   uci:set("babeld", "mptp4", "ip", "172.16.0.0/12"); uci:set("babeld", "mptp4", "action", "allow")
	uci:set("babeld", "default4", "filter"); uci:set("babeld", "default4", "type", "redistribute"); uci:set("babeld", "default4", "ip", "0.0.0.0/0"); uci:set("babeld", "default4", "le", "0"); uci:set("babeld", "default4", "action", "allow")
	uci:set("babeld", "localdeny", "filter"); uci:set("babeld", "localdeny", "type", "redistribute"); uci:set("babeld", "localdeny", "local", "true"); uci:set("babeld", "localdeny", "action", "deny")
	uci:set("babeld", "denyany", "filter");   uci:set("babeld", "denyany", "type", "redistribute");  uci:set("babeld", "denyany", "action", "deny")

	-- Añadir br-lan si existe y aún no está agregado
	local mesh_on_lan = tostring(config.get("network", "mesh_on_lan", "1"))
	if br_lan_exists() and mesh_on_lan ~= "0" then
		if not uci:get("babeld", "br_lan") then
			utils.log("lime.proto.babeld: agregando interfaz br-lan a babeld")
			uci:set("babeld", "br_lan", "interface")
			uci:set("babeld", "br_lan", "ifname", "br-lan")
		else
			utils.log("lime.proto.babeld: br-lan ya presente, se omite duplicado")
		end
		_apply_brlan_profile(uci) -- wired/wireless/auto + rxcost si wired
	else
		utils.log("lime.proto.babeld: br-lan no existe o mesh_on_lan=0; no se agrega interfaz global")
	end

	uci:save("babeld")

	-- Ajustar firewall según babeld_over_batman (regla ebtables)
	ensure_babel_over_batman_firewall()
end

-----------------------------------------------------------------------
-- setup_interface(): sumar ifaces mesh/radio que NO estén en br-lan ni sean AP
-- y permitir marcar ifaces cableadas preferidas (wired_ifaces) con rxcost bajo
-----------------------------------------------------------------------
function babeld.setup_interface(ifname, args)
	-- Ignorar APs y miembros del bridge LAN (para no duplicar vs br-lan)
	local is_ap = (not args["specific"]) and ifname:match("^wlan%d+%.ap%d*")
	if is_ap or babeld._is_in_lan_bridge(ifname) then
		utils.log("lime.proto.babeld.setup_interface(%s): ignorada (AP o miembro de br-lan)", ifname)
		return
	end

	utils.log("lime.proto.babeld.setup_interface(%s): agregando a babeld sin VLAN", ifname)

	local uci = config.get_uci_cursor()
	local sec = "babeld_" .. ifname:gsub("[^%w_]", "_")
	uci:set("babeld", sec, "interface")
	uci:set("babeld", sec, "ifname", ifname)

	local wired_set = _wired_preferred_set()
	local prefer_wired = wired_set[ifname] and not _is_wifi(ifname) and _carrier_up(ifname)

	if prefer_wired then
		uci:set("babeld", sec, "type", "wired")
		local rx = tostring(config.get("network", "babeld_wired_rxcost", "96"))
		uci:set("babeld", sec, "rxcost", rx)
	else
		uci:set("babeld", sec, "type", "wireless") -- conservador
	end

	uci:save("babeld")
end

-----------------------------------------------------------------------
-- runOnDevice(): agregar interfaz en caliente vía ubus (sin crear L3)
-----------------------------------------------------------------------
function babeld.runOnDevice(linuxDev, args)
	utils.log("lime.proto.babeld.runOnDevice(%s): add_interface vía ubus (sin VLAN, sin L3)", linuxDev)
	local libubus = require("ubus")
	local ubus = libubus.connect()
	if ubus then
		ubus:call('babeld', 'add_interface', { ifname = linuxDev })
	else
		utils.log("lime.proto.babeld.runOnDevice: ubus no disponible")
	end
end

return babeld
