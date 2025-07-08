-- packages/shared-state-odhcpd_leases/tests/shared-state-publish_odhcpd_leases_spec.lua

-- 0) Hacemos require del stub de JSON antes que nada
package.preload["luci.jsonc"] = function()
  return {

    parse = function(_)
      return current_leases_stub
    end,

    stringify = function(output_table)
      local parts = {}
      for ip, info in pairs(output_table) do
        table.insert(parts,
          string.format('"%s":{"mac":"%s","hostname":"%s"}',
            ip, info.mac or "", info.hostname or ""
          )
        )
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  }
end

local pub_dir = "packages/shared-state-odhcpd_leases/files/usr/share/shared-state/publishers/"
package.path = pub_dir.."?.lua;"..pub_dir.."?;"..package.path

describe("shared-state-publish_odhcpd_leases", function()
  local real_popen, real_io_open, captured_json

  before_each(function()

    package.loaded["shared-state-publish_odhcpd_leases"] = nil

    real_popen   = io.popen
    captured_json = nil
    io.popen = function(cmd, mode)
      if cmd:match("^shared%-state%-async insert") then
        return {
          write = function(_, s) captured_json = s end,
          close = function() end
        }
      end

      
      if cmd:match("^ubus call dhcp ipv4leases") then
        return {
          read  = function() return "" end,
          close = function() end
        }
      end
      return real_popen(cmd, mode)
    end
  end)

  after_each(function()
    io.popen   = real_popen
    io.open    = real_io_open
  end)

  it("[happy path] publica todas las leases recibidas", function()
    -- 4) Definimos current_leases_stub con dos leases
    current_leases_stub = {
      device = {
        eth0 = {
          leases = {
            { address="10.0.0.5", mac="aa:bb", hostname="h1" },
            { address="10.0.0.6", mac="cc:dd", hostname="h2" }
          }
        }
      }
    }

    -- 5) Cargamos y ejecutamos el publisher
    require("shared-state-publish_odhcpd_leases")

    -- 6) Verificamos que el JSON capturado contenga ambas entradas
    assert.is_string(captured_json, "Se esperaba una cadena JSON")
    assert.matches('"10%.0%.0%.5"%s*:%s*{[^}]-"mac"%s*:%s*"aa:bb"', captured_json)
    assert.matches('"10%.0%.0%.6"%s*:%s*{[^}]-"mac"%s*:%s*"cc:dd"', captured_json)
    assert.matches('"hostname"%s*:%s*"h1"', captured_json)
    assert.matches('"hostname"%s*:%s*"h2"', captured_json)
  end)

  it("[empty] ante cero leases, publica '{}'", function()
    -- 4) Simulamos parse que devuelve tabla sin device
    current_leases_stub = {}

    require("shared-state-publish_odhcpd_leases")

    assert.is_string(captured_json)
    assert.equals("{}", captured_json)
  end)

  it("[malformed] ante parse inesperado, también '{}' sin fallos", function()
    -- 4) Simulamos parse que devuelve nil
    current_leases_stub = nil

    -- protegemos JSON.parse de lanzar error
    package.preload["luci.jsonc"] = function()
      return {
        parse = function(_) return nil end,
        stringify = function(_) return "{}" end
      }
    end

    require("shared-state-publish_odhcpd_leases")

    assert.is_string(captured_json)
    assert.equals("{}", captured_json)
  end)
end)
