local serial = require('serialization')
local fs = require('filesystem')
local component = require('component')
local event = require('event')

local PATH = '/etc/machines.cfg'


local function len(table)
  local count = 0
  for _ in pairs(table) do count = count + 1 end
  return count
end


local function loadConfig()
  if not fs.exists(PATH) then
    return {}
  end
  local file, msg = io.open(PATH,'rb')
  if not file then
    io.stderr:write("Error while trying to read file at "..PATH..": "..msg)
    return
  end
  local sConfig = file:read("*a")
  file:close()
  return serial.unserialize(sConfig)
end

local function saveConfig(config)
  if not fs.exists(fs.path(PATH)) then
    fs.makeDirectory(fs.path(PATH))
  end
  local file, msg = io.open(PATH, 'w')
  if not file then
    io.stderr:write('Error while trying to save config to '..PATH..': '..msg)
    return
  end
  file:write(serial.serialize(config))
  file:close()
end

local function chooseReactor()
  local available = component.list('br_reactor')
  local n = count(available)
  if n == 0 then
    io.stderr:write('Error: no available reactor')
    return
  elseif n == 1 then
    return component.proxy((available()))
  else
    print(n..' reactors are available. Press [y] to choose currently activated reactor, anything else to activate another reactor.')
    local i = 0
    for addr, _ in pairs(available) do
      local reactor = component.proxy(addr)
      local rod_levels = {}
      for j = 1, reactor.getNumberOfControlRods() do
        table.insert(rod_levels, reactor.getControlRodLevel(j - 1))
      end
      reactor.setAllControlRodLevels(100)
      reactor.setActive(true)

      i = i + 1
      print('['..i..'/'..n..']')
      _, _, ch = event.pull('key_down')

      reactor.setActive(false)
      for j = 1, reactor.getNumberOfControlRods() do
        reactor.setControlRodLevel(j - 1, table.remove(rod_levels))
      end
      if string.lower(string.char(ch)) == 'y' then
        return reactor
      end
    end
    io.stderr:write('Error: no reactor was chosen')
  end
end

local function getConfig()
  local addresses = loadConfig()
  local proxies = {}
  if not addresses then
    io.stderr:write('Error while trying to read configuration file')
    return
  end
  if (not addresses.reactor) or
          component.type(addresses.reactor) ~= 'br_reactor' then
    proxies.reactor = chooseReactor()
  else
    proxies.reactor = component.proxy(addresses.reactor)
  end
end


getConfig()