-- packages/shared-state-odhcpd_leases/tests/test_publish_odhcpd_leases.lua
--
-- Unit-tests del publisher `shared-state-publish_odhcpd_leases`
-- alineados con TESTING.md de LibreMesh.
--

local testUtils = require "tests.utils"
local stub      = require "luassert.stub"

----------------------------------------------------------------------
-- 1. Cargar el publisher (no es módulo .lua) como función ejecutable.
----------------------------------------------------------------------

local publisher_file =
  "packages/shared-state-odhcpd_leases/files/usr/share/shared-state/publishers/" ..
  "shared-state-publish_odhcpd_leases"
local run_publisher = testUtils.load_lua_file_as_function(publisher_file)

----------------------------------------------------------------------
-- 2. Variables de ayuda
----------------------------------------------------------------------

local captured_json   -- JSON que escribe el publisher
local ubus_reply      -- tabla simulando respuesta de `ubus`

----------------------------------------------------------------------
-- 3. Stubs de io.popen y os.execute  (para aislar efectos colaterales)
----------------------------------------------------------------------

local popen_stub, execute_stub

local function stub_system_calls()
  popen_stub = stub(io, "popen", function(cmd, _)
    if cmd:match("^ubus call dhcp ipv4leases") then
      -- el JSON se ignora: parse() ya devuelve ubus_reply
      return { read = function() return "" end, close = function() end }

    elseif cmd:match("^shared%-state%-async insert") then
      -- capturamos lo que publica
      return {
        write = function(_, s) captured_json = s end,
        close = function() end
      }

    else  -- cualquier otro comando
      return { read = function() return "" end, close = function() end }
    end
  end)

  execute_stub = stub(os, "execute", function() return true end)
end

local function revert_system_stubs()
  if popen_stub   then popen_stub:revert()   end
  if execute_stub then execute_stub:revert() end
end

----------------------------------------------------------------------
-- 4. Suite de pruebas
----------------------------------------------------------------------

describe("shared-state-odhcpd_leases publisher #odhcpd-leases", function()

  ----------------------------------------------------------------------------
  -- before_each: reinstala stub de luci.jsonc y system-calls para *cada* test
  ----------------------------------------------------------------------------
  before_each(function()
    captured_json = nil
    ubus_reply    = nil

    -- Elimina cualquier versión previa de luci.jsonc cargada por otros tests
    package.loaded["luci.jsonc"]  = nil
    package.preload["luci.jsonc"] = function()
      return {
        parse = function() return ubus_reply end,
        -- luci.jsonc.stringify({})  →  "[]"   (array vacía)
        stringify = function(tbl)
          if next(tbl) == nil then return "[]" end
          local parts = {}
          for ip, info in pairs(tbl) do
            parts[#parts + 1] = string.format(
              '"%s":{"mac":"%s","hostname":"%s"}',
              ip, info.mac or "", info.hostname or "")
          end
          return "{" .. table.concat(parts, ",") .. "}"
        end
      }
    end

    stub_system_calls()
  end)

  ----------------------------------------------------------------------------
  after_each(function()
    revert_system_stubs()
    package.preload["luci.jsonc"] = nil   -- no contamina otros suites
  end)

  --------------------------------------------------------------------------
  -- 4.1 Camino feliz: dos leases publicadas
  --------------------------------------------------------------------------
  it("#happy_path publica todas las leases", function()
    ubus_reply = {
      device = {
        eth0 = {
          leases = {
            { address = "10.0.0.5", mac = "aa:bb", hostname = "h1" },
            { address = "10.0.0.6", mac = "cc:dd", hostname = "h2" }
          }
        }
      }
    }

    run_publisher()

    assert.is_string(captured_json, "Se esperaba JSON")
    assert.matches('"10%.0%.0%.5"%s*:%s*{[^}]-"mac"%s*:%s*"aa:bb"', captured_json)
    assert.matches('"10%.0%.0%.6"%s*:%s*{[^}]-"mac"%s*:%s*"cc:dd"', captured_json)
    assert.matches('"hostname"%s*:%s*"h1"', captured_json)
    assert.matches('"hostname"%s*:%s*"h2"', captured_json)
  end)

  --------------------------------------------------------------------------
  -- 4.2 Sin leases: se publica '[]'
  --------------------------------------------------------------------------
  it("#empty ante cero leases publica '[]'", function()
    ubus_reply = {}      -- parse() devuelve tabla vacía
    run_publisher()
    assert.equals("[]", captured_json)
  end)

  --------------------------------------------------------------------------
  -- 4.3 Respuesta malformada / nil: también '[]'
  --------------------------------------------------------------------------
  it("#malformed ante parse nil publica '[]'", function()
    ubus_reply = nil     -- parse() devuelve nil
    run_publisher()
    assert.equals("[]", captured_json)
  end)
end)
