--[[
Provides machines.gpus      = {gpu1, ...}
                 .screens   = {screen1, ...}
                 .reactor
                 .turbines  = {turbine1, ...}
                 .steam     = {{tank1, side1, index1}, ...}
                 .water     = {{tank1, side1, index1}, ...}
                 .pumps     = {{redstone_block1, side1}, ...}
]]--

local serial = require('serialization')
local fs = require('filesystem')
local component = require('component')
local event = require('event')
local term = require('term')

local PATH = '/etc/machines.cfg'
local directions = {[0] = 'down', 'up', 'north', 'south', 'west', 'east'}


local first_print = false
local function varprint(...)
  if not first_print then
    first_print = true
    print('Reconfiguring...')
  end
  print(...)
end

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
    io.stderr:write('Error while trying to read file at '..PATH..': '..msg)
    return
  end
  local sConfig = file:read('*a')
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


local function bigPrint(gpu, index)
  local digits = {
    {
      '       ▄██',
      '     ▄████',
      '  ▄▄██▀███',
      '  █▀▀  ███',
      '       ███',
      '       ███',
      '       ███',
      '       ███',
      '       ███',
      '       ███',
      '       ███'
    },
    {
      '  ▄▄██████▄▄  ',
      ' ████▀▀▀▀████ ',
      '███       ▀███',
      '           ███',
      '          ▄██▀',
      '        ▄███  ',
      '      ▄███▀   ',
      '    ▄██▀▀     ',
      '  ▄██▀        ',
      ' ███▄▄▄▄▄▄▄▄▄▄',
      '██████████████'
    },
    {
      '  ▄▄██████▄▄   ',
      ' ████▀▀▀▀▀███▄ ',
      '███▀       ███ ',
      '         ▄▄██▀ ',
      '      ██████   ',
      '      ▀▀▀▀███▄ ',
      '           ▀███',
      '            ███',
      '███▄       ▄██▀',
      ' ████▄▄▄▄▄███▀ ',
      '  ▀▀██████▀▀   '
    },
    {
      '          ▄██  ',
      '        ▄████  ',
      '       ██████  ',
      '     ▄██▀ ███  ',
      '    ███   ███  ',
      '  ▄██▀    ███  ',
      '▄██▀      ███  ',
      '███████████████',
      '▀▀▀▀▀▀▀▀▀▀███▀▀',
      '          ███  ',
      '          ███  '
    }
  }
  for i, line in ipairs(digits[index]) do
    gpu.set(5, i + 4, line)
  end
end
local function setScreens()
  local available_gpus = component.list('gpu')
  local available_screens = component.list('screen')
  local n = math.min(len(available_gpus), len(available_screens))
  if n == 0 then
    varprint('No available gpu/screen.')
    return
  end
  --Temporary solution. Ideally, the system should try all possible combinations
  --and choose bindings such that maximum potential is reached (check with
  --gpu.maxResolution(), because there is no way to distinguish tiers). If a
  --combination has to be suboptimal, ask the user which one.
  if n == 1 then
    varprint('One gpu-screen pair available.')
    local addr_gpu = (available_gpus())
    local addr_screen = (available_screens())
    local gpu = component.proxy(addr_gpu)
    gpu.bind(addr_screen)
    return {addr_gpu}, {gpu}, {addr_screen},
      {component.proxy(addr_screen)}
  end

  varprint(n..' gpu-screen pairs available. The screens will be lighted up, '
               ..'touch them in the order you desire (works only for screens of'
               ..' tier 2 and 3). The last screen will be considered primary.')
  varprint('Press [q] now to quit or [s] to start...')
  if getInput('sq') == 'q' then return -1 end
  local bound_pairs = {}
  local setting_old = {}
  for _ = 1, n do
    local gpu = component.proxy((available_gpus()))
    local addr_screen = available_screens()
    gpu.bind(addr_screen)
    local bc, bp = gpu.getBackground()
    gpu.setBackground(0xFFFFFF, false)
    local fc, fp = gpu.getForeground()
    gpu.setForeground(0, false)
    local width, height = gpu.getResolution()
    gpu.fill(1, 1, width, height, ' ')
    setting_old[addr_screen] = {bc, bp, fc, fp}
    bound_pairs[addr_screen] = gpu
  end
  local addresses_gpu = {}
  local proxies_gpu = {}
  local addresses_screen = {}
  local proxies_screen = {}
  for index = 1, n-1 do
    local _, addr_screen = event.pull('touch')
    local gpu = bound_pairs[addr_screen]
    bigPrint(gpu, index)
    table.insert(addresses_gpu, gpu.address)
    table.insert(proxies_gpu, gpu)
    table.insert(addresses_screen, addr_screen)
    table.insert(proxies_screen, component.proxy(addr_screen))
    bound_pairs[addr_screen] = nil
  end
  do
    local addr_screen, gpu = next(bound_pairs)
    table.insert(addresses_gpu, gpu.address)
    table.insert(proxies_gpu, gpu)
    table.insert(addresses_screen, addr_screen)
    table.insert(proxies_screen, component.proxy(addr_screen))
    component.setPrimary('gpu', gpu.address)
    component.setPrimary('screen', addr_screen)
  end
  for i, addr_screen in pairs(addresses_screen) do
    local bc, bp, fc, fp = table.unpack(setting_old[addr_screen])
    local gpu = proxies_gpu[i]
    gpu.setBackground(bc, bp)
    gpu.setForeground(fc, fp)
    local width, height = gpu.getResolution()
    gpu.fill(1, 1, width, height, ' ')
  end
  return addresses_gpu, proxies_gpu, addresses_screen, proxies_screen
end

local function setReactor()
  local available = component.list('br_reactor')
  local n = len(available)
  if n == 0 then
    varprint('No available reactor.')
    return
  end
  varprint('Do you want to choose a reactor [y/n/q]?')
  local cmd = getInput('ynq')
  if cmd == 'n' then return end
  if cmd == 'q' then return -1 end
  if n == 1 then
    local addr = (available())
    return addr, component.proxy(addr)
  end
  varprint(n..' reactors are available. Press [y] to choose the currently '
         ..'activated reactor, or [n] to activate another reactor. '
         ..'Press [q] to quit.')
  varprint('Press [s] to start...')
  if getInput('sq') == 'q' then return -1 end

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
      varprint('['..i..'/'..n..']')
      cmd = getInput('ynq')

      reactor.setActive(false)
      for j = 1, reactor.getNumberOfControlRods() do
        reactor.setControlRodLevel(j - 1, table.remove(rod_levels))
      end

      if cmd == 'y' then
        return addr, reactor
      elseif cmd == 'q' then
        return -1
      end
    end
  end
end

local function setTurbines()
  local available = component.list('br_turbine')
  local n = len(available)
  if n == 0 then
    varprint('No available turbine.')
    return
  end
  if n == 1 then
    varprint('One turbine was found, do you want to use it [y/n/q]?')
    local cmd = getInput('ynq')
    if cmd == 'n' then return end
    if cmd == 'q' then return -1 end
    local addr = (available())
    return {addr}, {component.proxy(addr)}
  end
  varprint('There are '..n..' turbines. How many will be used?')
  local count = tonumber(io.read())
  if not count or count < 0 or count > n or count % 1 ~= 0 then
    io.stderr:write('Error: illegal value')
    return -1
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
    varprint('Select '..i..'. turbine, there are '..(n - i + 1)..' turbines '
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
        varprint('['..j..'/'..(n - i + 1)..']')
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
          return -1
        end
      end
    end
  end
  return addresses, proxies
end

local function getFluids(filter, in_use)
  local tank_controllers = component.list('tank_controller')
  local fluids = {}  -- addr, side, index, name, amount, capacity
  local monolithic = filter and true or false
  for addr, _ in tank_controllers do
    for side = 0, 5 do
      local info = component.invoke(addr, 'getFluidInTank', side)
      for index = 1, info.n do
        if (not in_use[table.concat({addr, side, index}, ',')]) and
                (not filter or not info[index].name or
                        info[index].name == filter) then
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
  return '['..i..'] '..tank[1]..' ('..directions[tank[2]]..'): '..
      tostring(tank[4])..' ('..tostring(tank[5])..'/'..tostring(tank[6])..')'
end

local function printTanks(tanks, count)
  local xRes, yRes = component.gpu.getResolution()
  local xCur, yCur = term.getCursor()
  for i = 1, count do
    if tanks[i] then
      local str = tankToStr(i, tanks[i])
      yCur = yCur + math.ceil(#str / xRes)
      if yCur > yRes then
        term.write('[Press any key to continue]')
        if event.pull('key_down') then
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
  varprint('Searching for '..fluid_name..' tanks...')
  local tanks, nonempty = getFluids(fluid_name, in_use)
  local count = #tanks
  if count == 0 then
    varprint('No available '..fluid_name..' tanks.')
    return {}, {}
  end
  local addresses = {}
  local proxies = {}
  if nonempty then
    for _, data in ipairs(tanks) do
      table.insert(addresses, {data[1], data[2], data[3]})
      table.insert(proxies, {component.proxy(data[1]), data[2],
                             data[3]})
    end
    varprint('Done.')
  else
    local selected_count = 0
    local function selectTank(i)
      local addr, side, index = table.unpack(tanks[i])
      tanks[i] = nil
      table.insert(addresses, {addr, side, index})
      table.insert(proxies, {component.proxy(addr), side, index})
      selected_count = selected_count + 1
    end
    local function updateTank(i)
      if tanks[i] then
        local new_info = component.invoke(
            tanks[i][1], 'getFluidInTank', tanks[i][2])[tanks[i][3]]
        if tanks[i][5] ~= new_info.amount or tanks[i][4] ~= new_info.name
            or tanks[i][6] ~= new_info.capacity then
          tanks[i][4], tanks[i][5], tanks[i][6] =
              new_info.name, new_info.amount, new_info.capacity
          return true
        end
      end
      return false
    end

    varprint(count..' possible '..fluid_name..' tanks were found. Type '
                 ..'delimited list of indices to select some of them. Enter '
                 ..'empty line to submit. Use command [l] to list non-selected '
                 ..'tanks and [c] to toggle "change mode" - tanks that change '
                 ..'the amount of liquid will be selected. Type [q] to quit.')
    printTanks(tanks, count)
    local cmd
    while cmd ~= '' do
      cmd = io.read()
      if string.lower(cmd) == 'q' then
        return -1
      end
      for i = 1, count do
        updateTank(i)
      end
      if string.lower(cmd) == 'l' then
        printTanks(tanks, count)
      elseif string.lower(cmd) == 'c' then
        varprint('Entering "change mode"')
        while true do
          local _, _, code = event.pull(0.5, 'key_down')
          cmd = code and string.lower(string.char(code))
          if cmd == 'q' then
            return -1
          elseif cmd == 'c' then
            break
          end
          for i = 1, count do
            if updateTank(i) then
              varprint('Selecting '..tankToStr(i, tanks[i]))
              selectTank(i)
            end
          end
          if cmd == 'l' then
            printTanks(tanks, count)
          end
          if selected_count == count then
            varprint('All available tanks were chosen.')
            return addresses, proxies
          end
        end
        varprint('Leaving "change_mode"')
      else
        for selected in string.gmatch(cmd, '%d+') do
          if tanks[tonumber(selected)] then
            selectTank(tonumber(selected))
          end
        end
        if selected_count == count then
          varprint('All available tanks were chosen.')
          return addresses, proxies
        end
      end
    end
  end
  return addresses, proxies
end

local function setPumps()
  local redstone_blocks = component.list('redstone')
  if #redstone_blocks == 0 then
    varprint('No available redstone block.')
    return {}, {}
  end
  varprint(#redstone_blocks..' redstone block(s) is(are) available. Change the '
            ..'input value of the sides you want to be used to control the '
            ..'water pumps. Press [Enter] to submit and [q] to quit.')
  varprint('Before selecting, you can change the polarity used to turn on the '
           ..'pumps using [+] and [-]. Current turn-on polarity: OFF')
  varprint('Press [s] to start...')
  if getInput('sq') == 'q' then return -1 end
  local redstone_input = {}
  local i = 0
  for addr, _ in redstone_blocks do
    i = i + 1
    redstone_blocks[addr] = {}
    redstone_blocks[i] = component.proxy(addr)
    redstone_input[i] = redstone_blocks[i].getInput()
  end
  local addresses = {}
  local proxies = {}
  local polarity = false
  while true do
    local _, _, code = event.pull(0.2, 'key_down')
    local cmd = code and string.lower(string.char(code))
    if cmd == 'q' then
      return -1
    elseif cmd == '-' then
      polarity = false
      varprint('Current turn-on polarity: OFF')
    elseif cmd == '+' then
      polarity = true
      varprint('Current turn-on polarity: ON')
    elseif cmd == '\r' then
      return addresses, proxies
    end
    for j, redstone_block in ipairs(redstone_blocks) do
      local new = redstone_block.getInput()
      for s = 0, 5 do
        if not redstone_blocks[redstone_block.address][s] and
            new[s] ~= redstone_input[j][s] then
          varprint('Selecting '..redstone_block.address..' ('..directions[s]
                       ..')')
          redstone_blocks[redstone_block.address][s] = true
          table.insert(addresses, {redstone_block.address, s, polarity})
          table.insert(proxies, {redstone_block, s, polarity})
        end
      end
    end
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

  local set_functions = {
    reactor = setReactor,
    turbines = setTurbines,
    steam = function() return setTanks('steam', {}) end,
    water = function(in_use) return setTanks('water', in_use) end,
    pumps = setPumps
  }
  local function set(type, ...)
    local a, p = set_functions[type](...)
    if a == -1 then
      proxies = nil
      return false
    end
    addresses[type], proxies[type] = a, p
    save = true
    return true
  end
  local function setGpusScreens()
    local ag, pg, as, ps = setScreens()
    if ag == -1 then
      proxies = nil
      return false
    end
    addresses.gpus, proxies.gpus = ag, pg
    addresses.screens, proxies.screens = as, ps
    save = true
    return true
  end

  (function ()
    if addresses.screens and addresses.gpus and
        len(addresses.screens) == len(addresses.gpus) then
      proxies.gpus = {}
      proxies.screens = {}
      for i, addr_gpu in ipairs(addresses.gpus) do
        local addr_screen = addresses.screens[i]
        if component.type(addr_gpu) == 'gpu' and
            component.type(addr_screen) == 'screen' then
          local gpu = component.proxy(addr_gpu)
          gpu.bind(addr_screen)
          table.insert(proxies.gpus, gpu)
          table.insert(proxies.screens, component.proxy(addr_screen))
        else
          if not setGpusScreens() then return end
          break
        end
      end
    else
      if not setGpusScreens() then return end
    end

    if (not addresses.reactor) or
            component.type(addresses.reactor) ~= 'br_reactor' then
      if not set('reactor') then return end
    else
      proxies.reactor = component.proxy(addresses.reactor)
    end

    if addresses.turbines then
      proxies.turbines = {}
      for _, addr in ipairs(addresses.turbines) do
        if component.type(addr) == 'br_turbine' then
          table.insert(proxies.turbines, component.proxy(addr))
        else
          if not set('turbines') then return end
          break
        end
      end
    else
      if not set('turbines') then return end
    end

    if addresses.steam then
      proxies.steam = {}
      for _, data in ipairs(addresses.steam) do
        local addr, side, index = table.unpack(data)
        if component.type(addr) == 'tank_controller' then
          table.insert(proxies.steam,
                       {component.proxy(addr), side, index})
        else
          if not set('steam') then return end
          break
        end
      end
    else
      if not set('steam') then return end
    end

    local in_use = {}
    for _, data in ipairs(addresses.steam) do
      in_use[table.concat(data, ',')] = true
    end
    if addresses.water then
      proxies.water = {}
      for _, data in ipairs(addresses.water) do
        local addr, side, index = table.unpack(data)
        if component.type(addr) == 'tank_controller' and
                not in_use[table.concat(data, ',')] then
          table.insert(proxies.water,
                       {component.proxy(addr), side, index})
        else
          if not set('water', in_use) then return end
          break
        end
      end
    else
      if not set('water', in_use) then return end
    end

    if addresses.pumps then
      proxies.pumps = {}
      for _, data in ipairs(addresses.pumps) do
        local addr, side = table.unpack(data)
        if component.type(addr) == 'redstone' then
          table.insert(proxies.pumps, {component.proxy(addr), side})
        else
          if not set('pumps') then return end
          break
        end
      end
    else
      if not set('pumps') then return end
    end
    if save then
      saveConfig(addresses)
    end
  end)()

  return proxies
end


return getConfig()