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
    term.clear()
    print('There are '..n..' turbines. How many will be used?')
    local count = tonumber(io.read())
    if not count or count <= 0 or count > n then
      io.stderr:write('Error: illegal value')
      return
    end
    local addresses = {}
    local proxies = {}
    for i = 1, count do
      if n == i then
        for addr, _ in pairs(available) do
          table.insert(addresses, addr)
          table.insert(proxies, component.proxy(addr))
          break
        end
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
            table.insert(addresses, addr)
            table.insert(proxies, turbine)
            available[addr] = nil
            selected = true
            break
          elseif cmd == 'q' then
            return
          end
        end
      end
    end
    return addresses, proxies
  end
end

local function getFluids(filter, in_use)
  -- print('entering getFluids, in_use = '..serial.serialize(in_use))
  local tank_controllers = component.list('tank_controller')
  local fluids = {}  -- addr, side, index, name, amount, capacity
  local monolithic = filter and true or false
  for addr, _ in tank_controllers do
    for side = 0, 5 do
      local info = component.invoke(addr, 'getFluidInTank', side)
      for index = 1, info.n do
        local hash = table.concat({addr, side, index}, ',')
        -- print('in_use["'..hash..'"] = '..tostring(in_use[hash]))
        -- getInput(' ')
        if (not in_use[hash]) and (not filter or
                not info[index].name or info[index].name == filter) then
          table.insert(fluids, {addr, side, index, info[index].name,
                                info[index].amount, info[index].capacity})
          if not info[index].name then monolithic = false end
        end
      end
    end
  end
  return fluids, monolithic
end

local function tankToStr(i, tank)
  return '['..i..'] '..tank[1]..': '..tostring(tank[4])..' ('
              ..tostring(tank[5])..'/'..tostring(tank[6])..')'
end

local function printTanks(tanks, count)
  local xRes, yRes = component.gpu.getResolution()
  local xCur, yCur = term.getCursor()
  for i = 1, count do
    if tanks[i] then
      local str = tankToStr(i, tanks[i])
      yCur = yCur + math.ceil(#str / xRes)
      if yCur > yRes then
        term.write("[Press any key to continue]")
        if event.pull("key_down") then
          term.clear()
          xCur, yCur = term.getCursor()
          yCur = yCur + math.ceil(#str / xRes)
        end
      end
      term.write(str..'\n', true)
    end
  end
end

local function setTanks(fluid_name, in_use)
  print('Searching for tanks...')
  local in_use_set = {}
  for _, data in ipairs(in_use or {}) do
    in_use_set[table.concat(data, ',')] = true
  end
  local tanks, nonempty = getFluids(fluid_name, in_use_set)
  local count = #tanks
  if count == 0 then
    io.stderr:write('Error: no available '..fluid_name..' tanks')
    return
  end
  local addresses = {}
  local proxies = {}
  if nonempty then
    for _, data in ipairs(tanks) do
      table.insert(addresses, {data[1], data[2], data[3]})
      table.insert(proxies, {component.proxy(data[1]), data[2],
                             data[3]})
    end
  else
    local function selectTank(i)
      local addr, side, index = table.unpack(tanks[i])
      tanks[i] = nil
      table.insert(addresses, {addr, side, index})
      table.insert(proxies, {component.proxy(addr), side, index})
    end
    -- term.clear()
    print(count..' possible '..fluid_name..' tanks were found. Type delimited '
          ..'list of indices to select some of them. Enter empty line to '
          ..'submit. Use command "l" to list non-selected tanks and "c" to '
          ..'toggle "change mode" - tanks that change the amount of liquid '
          ..'will be selected. Type "q" to quit.')
    printTanks(tanks, count)
    local cmd
    local timer_id
    while cmd ~= '' do
      cmd = io.read()
      if string.lower(cmd) == 'q' then
        return
      elseif string.lower(cmd) == 'l' then
        printTanks(tanks, count)
      elseif string.lower(cmd) == 'c' then
        if timer_id then
          print('Leaving "change_mode"')
          event.cancel(timer_id)
          timer_id = nil
        else
          for i = 1, count do
            if tanks[i] then
              tanks[i][5] = component.invoke(tanks[i][1], 'getFluidInTank',
                                             tanks[i][2])[tanks[i][3]].amount
            end
          end
          print('Entering "change mode"')
          timer_id = event.timer(1, function()
            for i = 1, count do
              if tanks[i] and tanks[i][5] ~= component.invoke(
                      tanks[i][1], 'getFluidInTank', tanks[i][2]
              )[tanks[i][3]].amount then
                print('Selecting '..tankToStr(i, tanks[i]))
                selectTank(i)
              end
            end
          end, math.huge)
        end
      else
        for selected in string.gmatch(cmd, '%d+') do
          if tanks[tonumber(selected)] then
            selectTank(tonumber(selected))
          end
        end
      end
    end
  end
  return addresses, proxies
end

local function getConfig()
  local addresses = loadConfig()
  print(serial.serialize(addresses))
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
          local new = setTanks('steam')
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
      local new = setTanks('steam')
      if not new then
        proxies = nil
        return
      end
      addresses.steam, proxies.steam = new
      save = true
    end

    if addresses.water then
      proxies.water = {}
      for _, data in ipairs(addresses.water) do
        local addr, side, index = table.unpack(data)
        if component.type(addr) == 'tank_controller' and
                not addresses.steam[data] then
          table.insert(proxies.water,
                       {component.proxy(addr), side, index})
        else
          local new = setTanks('water', addresses.steam)
          if not new then
            proxies = nil
            return
          end
          addresses.water, proxies.water = new
          save = true
          break
        end
      end
    else
      local new = setTanks('water', addresses.steam)
      if not new then
        proxies = nil
        return
      end
      addresses.water, proxies.water = new
      save = true
    end
  end)()

  if save then
    saveConfig(addresses)
  end
  return proxies
end


getConfig()