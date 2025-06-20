#!/usr/bin/env lua

local json = require "luci.jsonc".parse(io.read("*a"))
local leasetime = math.max(json.expires - os.time(), 60)
os.execute(string.format(
  "ubus call dhcp add_lease '{\"mac\":\"%s\",\"ip\":\"%s\",\"name\":\"%s\",\"leasetime\":%d}'",
  json.mac, json.ip, json.hostname or "", leasetime
))

