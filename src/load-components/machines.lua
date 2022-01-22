local serial = require('serialization')
local fs = require('filesystem')
local component = require('component')
local event = require('event')
local term = require("term")

local PATH = '/etc/machines.cfg'


local function len(table)
  local count = 0
  for _ in pairs(table) do count = count + 1 end
  return count
end

local function getInput(chars)
  local ch
  while ch == nil or not string.find(chars, ch) do
    local _, _, code = event.pull('key_down')
    ch = string.char(code)
  end
  return ch
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
                  ..'activated reactor, or [n] to activate another reactor. '
                  ..'Press [q] to quit.')
    print('Press [s] to start...')
    local cmd = getInput('sq')
    if cmd == 'q' then return end

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
        cmd = getInput('ynq')

        reactor.setActive(false)
        for j = 1, reactor.getNumberOfControlRods() do
          reactor.setControlRodLevel(j - 1, table.remove(rod_levels))
        end

        if cmd == 'y' then
          return addr, reactor
        elseif cmd == 'q' then
          return
        end
      end
    end
  end
end

local function setTurbines()
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
    if not count or count <= 0 or count > n then
      io.stderr:write('Error: illegal value')
      return
    end
    local t_addresses = {}
    local t_proxies = {}
    for i = 1, count do
      if n == i then
        table.insert(t_addresses, available[1])
        table.insert(t_proxies, component.proxy(available[1]))
        break
      end
      print('Select '..i..'. turbine, there are '..(n - i + 1)..' turbines '
          ..'available. Press [y] to choose the activated turbine, or [n] '
          ..'to activate another turbine. Press [q] to quit.')
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
          local cmd = getInput('ynq')

          turbine.setActive(false)
          turbine.setFluidFlowRateMax(flow_rate_max)
          turbine.setInductorEngaged(coils_engaged)

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

local function getFluids(filter)
  print('entering getFluids()')
  local tank_controllers = component.list('tank_controller')
  local fluids = {}  -- addr, side, index, name, amount, capacity
  local monolithic = filter and true or false
  for addr, _ in tank_controllers do
    print('addr: '..addr)
    for side = 0, 5 do
      print('side: '..side)
      local info = component.invoke(addr, 'getFluidInTank', side)
      for index = 1, info.n do
        print('index: '..index)
        if not filter or not info[index].name or info[index].name == filter
        then
          table.insert(fluids, {addr, side, index, info[index].name,
                                info[index].amount, info[index].capacity})
          if not info[index].name then monolithic = false end
        end
      end
    end
  end
  print('exiting getFluids()')
  return fluids, monolithic
end

local function printTanks(tanks, count)
  print('entering printTanks('..tostring(tanks)..')')
  local xRes, yRes = component.gpu.getResolution()
  local xCur,yCur = term.getCursor()
  for i = 1, count do
    local addr, _, _, name, amount, capacity = tanks[i]
    if addr then
      local str = '['..i..']'..addr..': '..tostring(name)..' ('..tostring(amount)..'/'..tostring(capacity)..')'
      yCur = yCur + math.ceil(#str / xRes)
      if yCur > yRes then
        term.write("[Press any key to continue]")
        if event.pull("key_down") then
          term.clear()
          xCur, yCur = term.getCursor()
          yCur = yCur + math.ceil(#str / xRes)
        end
      end
      term.write(str..'\n')
    end
  end
end

local function setSteam()
  local tanks, nonempty = getFluids('steam')
  local count = #tanks
  if count == 0 then
    io.stderr:write('Error: no available steam tanks')
    return
  end
  local s_addresses = {}
  local s_proxies = {}
  if nonempty then
    for _, data in ipairs(tanks) do
      table.insert(s_addresses, {data[1], data[2], data[3]})
      table.insert(s_proxies, {component.proxy(data[1]), data[2],
                               data[3]})
    end
  else
    print(count..' possible steam tanks were found. Type delimited list '
          ..'of indices to select some of them. Enter empty line to submit. '
          ..'Use command "l" to list non-selected tanks and "c" to toggle '
          ..'"change mode" - tanks that change the amount of liquid will be '
          ..'selected.')
    printTanks(tanks, count)
    local cmd
    while cmd ~= '' do
      cmd = io.read()
      if string.lower(cmd) == 'l' then
        printTanks(tanks, count)
      elseif string.lower(cmd) == 'c' then
        print('Not implemented')
      else
        for selected in string.gmatch(cmd, '%d+') do
          local addr, side, index = tanks[tonumber(selected)]
          table.insert(s_addresses, {addr, side, index})
          table.insert(s_proxies, {component.proxy(addr), side, index})
        end
      end
    end
  end
  return s_addresses, s_proxies
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
        proxies = nil
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
          local new = setTurbines()
          if not new then
            proxies = nil
            return
          end
          addresses.turbines, proxies.turbines = new
          save = true
          break
        end
      end
    else
      local new = setTurbines()
      if not new then
        proxies = nil
        return
      end
      addresses.turbines, proxies.turbines = new
      save = true
    end

    if addresses.steam then
      proxies.steam = {}
      for _, data in ipairs(addresses.steam) do
        local addr, side, index = table.unpack(data)
        if component.type(addr) == 'tank_controller' then
          table.insert(proxies.steam,
                       {component.proxy(addr), side, index})
        else
          local new = setSteam()
          if not new then
            proxies = nil
            return
          end
          addresses.steam, proxies.steam = new
          save = true
          break
        end
      end
    else
      local new = setSteam()
      if not new then
        proxies = nil
        return
      end
      addresses.steam, proxies.steam = new
      save = true
    end
  end)()

  if save then
    saveConfig(addresses)
  end
  return proxies
end


getConfig()