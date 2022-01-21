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


local function setReactor()
  local available = component.list('br_reactor')
  local n = len(available)
  if n == 0 then
    io.stderr:write('Error: no available reactor')
    return
  elseif n == 1 then
    local addr = (available())
    return addr, component.proxy(addr)
  else
    print(n..' reactors are available. Press [y] to choose the currently '
           ..'activated reactor, or anything else to activate another reactor. '
           ..'Press [q] to quit.')
    while true do
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
        local cmd = string.lower(string.char(ch))
        if cmd == 'y' then
          return addr, reactor
        elseif cmd == 'q' then
          return
        end
      end
    end
  end
end

local function setTurbines(partial)
  local available = component.list('br_turbine')
  local n = len(available)
  if n == 0 then
    io.stderr:write('Error: no available turbine')
    return
  elseif n == 1 then
    local addr = (available())
    return {addr}, {component.proxy(addr)}
  else
    print('There are '..n..' turbines. How many will be used?')
    local count = tonumber(io.read())
    if (not count) or count <= 0 or count > n then
      io.stderr:write('Error: illegal value')
      return
    end
    local t_addresses = {}
    local t_proxies = {}
    for i = 1, count do
      print('Select '..i..'. turbine, there are '..(n - i + 1)..' turbines '
          ..'available. Press [y] to choose the activated turbine, or anything '
          ..'else to activate another turbine. Press [q] to quit.')
      local selected = false
      while not selected do
        local j = 0
        for addr, _ in pairs(available) do
          local turbine = component.proxy(addr)
          local flow_rate_max = turbine.getFluidFlowRateMax()
          local coils_engaged = turbine.getInductorEngaged()
          turbine.setFluidFlowRateMax(0)
          turbine.setInductorEngaged(false)
          turbine.setActive(true)

          j = j + 1
          print('['..j..'/'..(n - i + 1)..']')
          _, _, ch = event.pull('key_down')

          turbine.setActive(false)
          turbine.setFluidFlowRateMax(flow_rate_max)
          turbine.setInductorEngaged(coils_engaged)
          local cmd = string.lower(string.char(ch))
          if cmd == 'y' then
            table.insert(t_addresses, addr)
            table.insert(t_proxies, turbine)
            available[addr] = nil
            selected = true
            break
          elseif cmd == 'q' then
            return
          end
        end
      end
    end
    return t_addresses, t_proxies
  end
end

local function getConfig()
  local addresses = loadConfig()
  local proxies = {}
  local save = false
  if not addresses then
    io.stderr:write('Error while trying to read configuration file')
    return
  end

  (function ()
    if (not addresses.reactor) or
            component.type(addresses.reactor) ~= 'br_reactor' then
      local new = setReactor()
      if not new then
        return
      end
      addresses.reactor, proxies.reactor = new
      save = true
    else
      proxies.reactor = component.proxy(addresses.reactor)
    end

    if addresses.turbines then
      proxies.turbines = {}
      for _, addr in ipairs(addresses.turbines) do
        if component.type(addr) == 'br_turbine' then
          table.insert(proxies.turbines, component.proxy(addr))
        else
          local new = setTurbines(proxies.turbines)
          if not new then return end
          addresses.turbines, proxies.turbines = new
          save = true
          break
        end
      end
    else
      local new = setTurbines()
      if not new then return end
      addresses.turbines, proxies.turbines = new
      save = true
    end
  end)()

  if save then
    saveConfig(addresses)
  end
end


getConfig()