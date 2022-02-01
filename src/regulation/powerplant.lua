-- local r, t1, t2, t3, s1, s2, w = table.unpack(require('loadComp'))
-- local t = {t1, t2, t3}
local machines = require('machines')
local regulation = require('regulation')
local event = require('event')
local keyboard = require('keyboard')
local modem = require('component').modem
local sides = require('sides')

local target_t = {}
local enable_coil = {}
local INDUCTION_THRESHOLD = 64

local target_r = 0.93  -- the fraction of available steam storage space that we
                       -- want to be filled
local mode_r = 'balance'  -- can be 'balance', 'standby' or 'stop'
local mode_t = 'standby'  -- can be 'standby', 'power_1', 'power_2', 'power_3',
                          -- 'power_4' or 'stop'
local mode_tn = 0
local MAX_CRL = 90  -- when control rods are almost fully inserted, the reaction
                    -- starts to weirdly fluctuate
local WATER_EMERGENCY_STOP = 0.5
local PRESSURE_THRESHOLD = 0.97  --enter standby mode. During very low steam
  -- consumption the pressure oscillates around the target with a deviation
  -- of (PRESSURE_THRESHOLD - target_r).

local EVENT_WAIT = 0.005
local MODEM_PERIOD = 3
local MODEM_INFO_PORT = 1
local timer = event.timer(MODEM_PERIOD, function()
  modem.broadcast(MODEM_INFO_PORT, 't_targets', table.unpack(target_t))
end, math.huge)

-- local K_POWER1 = string.byte('1')
-- local K_POWER2 = string.byte('2')
-- local K_POWER3 = string.byte('3')
-- local K_POWER4 = string.byte('4')
-- local K_TURBINES_STANDBY = string.byte('0')
local K_POWER_P = string.byte('+')
local K_POWER_M = string.byte('-')
local K_POWER = string.byte('p')
local K_REACTOR_STANDBY = string.byte('s')
local K_BALANCE = string.byte('b')
local K_TURBINES_STOP = string.byte('t')
local K_REACTOR_STOP = string.byte('r')
local K_STOP = string.byte(' ')
local K_GET_STATE = string.byte('g')
local K_HELP = string.byte('h')

local regulators_t = {}
for _, turbine in ipairs(machines.turbines) do
  table.insert(regulators_t, regulation.PDM(
    turbine.getRotorSpeed,
    turbine.setFluidFlowRateMax,
    0,
    0.03, 0.1,
    2000, false
  ))
end


local function get_pressure()
  local amount = 0
  local capacity = 0
  for _, tank in ipairs(machines.steam) do
    local info = tank[1].getFluidInTank(tank[2])[tank[3]]
    amount = amount + (info.amount or 0)
    capacity = capacity + (info.capacity or 0)
  end
  if capacity ~= 0 then return amount / capacity end
  return 1
end


local regulator_r = regulation.PDM(
  get_pressure,
  machines.reactor.setAllControlRodLevels,
  target_r, 0.8, 30,
  MAX_CRL, true
)


local function init_reactor()
  local init_crl = 0
  for i = 0, machines.reactor.getNumberOfControlRods() - 1 do
    init_crl = init_crl + machines.reactor.getControlRodLevel(i)
  end
  regulator_r.init(init_crl / machines.reactor.getNumberOfControlRods())
end


local function _change_mode_turbine(key)
  if key == K_TURBINES_STOP or key == K_STOP then
    print('Turbines - STOP')
    mode_t = 'stop'
    for i, turbine in ipairs(machines.turbines) do
      target_t[i] = 0
      enable_coil[i] = true
      turbine.setActive(false)
      regulators_t[i].set_setpoint(target_t[i])
    end
    return
  end
  if key == K_POWER1 then
    print('Turbines - power_1')
    mode_t = 'power_1'
    target_t = {900, 900, 60}
    enable_coil = {true, false, false}
  elseif key == K_POWER2 then
    print('Turbines - power_2')
    mode_t = 'power_2'
    target_t = {900, 1845, 900}
    enable_coil = {true, true, false}
  elseif key == K_POWER3 then
    print('Turbines - power_3')
    mode_t = 'power_3'
    target_t = {900, 1845, 1845}
    enable_coil = {true, true, true}
  elseif key == K_POWER4 then
    print('Turbines - power_4')
    mode_t = 'power_4'
    target_t = {1845, 1845, 1845}
    enable_coil = {true, true, true}
  elseif key == K_TURBINES_STANDBY then
    print('Turbines - standby')
    mode_t = 'standby'
    target_t = {60, 60, 60}
    enable_coil = {false, false, false}
  else
    return
  end
  for i, turbine in ipairs(machines.turbines) do
    turbine.setActive(true)
    regulators_t[i].set_setpoint(target_t[i])
  end
end

local function change_mode_turbine(key)
  if key == K_TURBINES_STOP or key == K_STOP then
    print('Turbines - STOP')
    mode_t = 'stop'
    for i, turbine in ipairs(machines.turbines) do
      target_t[i] = 0
      enable_coil[i] = true
      turbine.setActive(false)
      regulators_t[i].set_setpoint(target_t[i])
    end
    return
  elseif key == K_POWER then
    print('Turbines - power '..mode_tn)
    mode_t = 'power'
  elseif key == K_POWER_P then
    if mode_t == 'power' then
      mode_tn = math.min(mode_tn + 1, #machines.turbines + 1)
      print('Turbines - power '..mode_tn)
    else
      print('Turbines - STOP, cannot change power mode')
    end
  elseif key == K_POWER_M and mode_t == 'power' then
    if mode_t == 'power' then
      mode_tn = math.max(mode_tn - 1, 0)
      print('Turbines - power '..mode_tn)
    else
      print('Turbines - STOP, cannot change power mode')
    end
  end

  if mode_tn == #machines.turbines + 1 then
    target_t[1] = 1845
  else
    target_t[1] = 900
  end
  enable_coil[1] = mode_tn ~= 0
  for i = 2, #machines.turbines do
    if i > mode_tn + 1 then
      target_t[i] = 60
    else
      target_t[i] = 1845
    end
    enable_coil[i] = i <= mode_tn
    regulators_t[i].set_setpoint(target_t[i])
  end
end


local function change_mode_reactor(key)
  if key == K_REACTOR_STOP or key == K_STOP then
    print('Reactor - STOP')
    mode_r = 'stop'
  elseif key == K_BALANCE then
    print('Reactor - balance')
    mode_r = 'balance'
    init_reactor()
  elseif key == K_REACTOR_STANDBY then
    print('Reactor - standby')
    mode_r = 'standby'
  end
end


local function info(key)
  if key == K_GET_STATE then
    print('Current state:')
    if mode_t == 'power' then
      print(string.format('  Turbines - power %d', mode_tn))
    else
      print('  Turbines - stop')
    end
    for i, turbine in machines.turbines do
      local state = 'engaged'
      if not turbine.getInductorEngaged() then
        state = 'dis' .. state
      end
      print(string.format('    Turbine %d - %s', i, state))
    end
    print(string.format('  Reactor - %s', mode_r))
  elseif key == K_HELP then
    print('Commands: <space>, r, t; s, b; p, +, -; g, h')
  end
end


for i, turbine in ipairs(machines.turbines) do
  turbine.setActive(true)
  regulators_t[i].init(turbine.getFluidFlowRateMax())
end
change_mode_turbine(K_POWER)
change_mode_reactor(K_BALANCE)

while true do
  --handle key_down events
  repeat
    local _, _, key = event.pull(EVENT_WAIT, 'key_down')
    if key == 3 then
      print('interrupting...')
      machines.reactor.setActive(false)
      for _, turbine in ipairs(machines.turbines) do
        turbine.setActive(false)
        turbine.setInductorEngaged(false)
        turbine.setFluidFlowRateMax(0)
      end
      event.cancel(timer)
      os.exit()
    end
    change_mode_turbine(key)
    change_mode_reactor(key)
    info(key)
  until key == nil
  
  --regulate reactor
  --update mode_r based on current pressure
  if get_pressure() >= PRESSURE_THRESHOLD and mode_r == 'balance' then
    print('Reactor - standby')
    mode_r = 'standby'
  elseif get_pressure() <= (2*target_r) - PRESSURE_THRESHOLD and
      mode_r == 'standby' then
    print('Reactor - balance')
    mode_r = 'balance'
  end
  --regulate, shutdown if not enough water
  if mode_r == 'balance' then
    regulator_r()
    --[[
    if (w.getTankLevel(sides.south) < (WATER_EMERGENCY_STOP * w.getTankCapacity(sides.south))) then
      print('Reactor - NOT ENOUGH WATER')
      mode_r = 'stop'
    end
    --]]
  end
  --activate/deactivate reactor
  if machines.reactor.getActive() and (mode_r == 'standby' or mode_r == 'stop')
  then
    machines.reactor.setActive(false)
  elseif (not machines.reactor.getActive() and mode_r == 'balance') then
    machines.reactor.setActive(true)
  end
  
  --regulate turbines
  for i, turbine in ipairs(machines.turbines) do
    if not turbine.getActive() then
      turbine.setActive(true)
    end
    regulators_t[i]()
    
    --update coils based on current speed
    local speed = turbine.getRotorSpeed()
    if not enable_coil[i] then
      if turbine.getInductorEngaged() then
        print(string.format('Turbine %d - disengaged', i))
        turbine.setInductorEngaged(false)
      end
    elseif speed >= (target_t[i] - INDUCTION_THRESHOLD) and
        not turbine.getInductorEngaged() then
      print(string.format('Turbine %d - engaged', i))
      turbine.setInductorEngaged(true)
    elseif speed < (target_t[i] - INDUCTION_THRESHOLD) and
        turbine.getInductorEngaged() then
      print(string.format('Turbine %d - disengaged', i))
      turbine.setInductorEngaged(false)
    end
  end
end