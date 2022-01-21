local r, t1, t2, t3, s1, s2, w, p = table.unpack(require("loadComp"))
local t = {t1, t2, t3}
local comp = require("computer")
local event = require("event")
local keyboard = require("keyboard")
local sides = require("sides")
local modem = require("component").modem
local floor = require("math").floor

local target = {}
local unlock_coil = {}

local SLOPE_COEFFICIENT = 0.05
local REGULATION_COEFFICIENT = 13
local INDUCTION_TRESHOLD = 0.93
local AVERAGE_LOOP = 0.3
local EVENT_WAIT = 0.005
local MODEM_PERIOD = 3
local MODEM_INFO_PORT = 1
local NUMBER_OF_TURBINES = 3

local K_POWER1 = string.byte("1")
local K_POWER2 = string.byte("2")
local K_POWER3 = string.byte("3")
local K_POWER4 = string.byte("4")
local K_STANDBY = string.byte("s")
local K_STOP = string.byte(" ")

local running = true
local time_old, time_cur
local flow_rate = {}
local speed_old = {}
local speed_cur = {}
for i = 1, NUMBER_OF_TURBINES do
  speed_old[i] = 0
  speed_cur[i] = 0
  flow_rate[i] = t[i].getFluidFlowRateMax()
  target[i] = 60
  unlock_coil[i] = false
  t[i].setInductorEngaged(false)
end


function interrupt(key)
  if (key == 3) then
    print("interrupting...")
    for i = 1, NUMBER_OF_TURBINES do
      t[i].setActive(false)
      t[i].setInductorEngaged(false)
      t[i].setFluidFlowRateMax(0)
    end
    os.exit()
  end
end


function stop()
  print("EMERGENCY STOP")
  for i = 1, NUMBER_OF_TURBINES do
    target[i] = 0
    flow_rate[i] = 0
    unlock_coil[i] = true
    t[i].setActive(false)
  end
end


function switch_mode(key)
  if (key == K_STOP) then
    stop()
    return
  end
  
  t1.setActive(true)
  t2.setActive(true)
  t3.setActive(true)
  if key == K_POWER1 then
    print('switching to mode "power_1"')
    target = {900, 900, 60}
    unlock_coil = {true, false, false}
    t2.setInductorEngaged(false)
    t3.setInductorEngaged(false)
  elseif key == K_POWER2 then
    print('switching to mode "power_2"')
    target = {900, 1800, 900}
    unlock_coil = {true, true, false}
    t3.setInductorEngaged(false)
  elseif key == K_POWER3 then
    print('switching to mode "power_3"')
    target = {900, 1800, 1800}
    unlock_coil = {true, true, true}
  elseif key == K_POWER4 then
    print('switching to mode "power_4"')
    target = {1800, 1800, 1800}
    unlock_coil = {true, true, true}
  elseif key == K_STANDBY then
    print('switching to mode "standby"')
    target = {60, 60, 60}
    unlock_coil = {false, false, false}
    t1.setInductorEngaged(false)
    t2.setInductorEngaged(false)
    t3.setInductorEngaged(false)
  end
end


function update()
  time_old = time_cur
  time_cur = comp.uptime()
  for i = 1, NUMBER_OF_TURBINES do
    speed_old[i] = speed_cur[i]
    speed_cur[i] = t[i].getRotorSpeed()
  end
  if time_old == nil then
    return
  end
  if floor(time_old / MODEM_PERIOD) < floor(time_cur / MODEM_PERIOD) then
    modem.broadcast(MODEM_INFO_PORT, "t_targets", table.unpack(target))
  end
end


function update_flow_rate(i)
  local difference = target[i] - speed_cur[i]
  local der_target = SLOPE_COEFFICIENT * difference
  local der = (speed_cur[i] - speed_old[i]) / (time_cur - time_old)
  flow_rate[i] = flow_rate[i] + (REGULATION_COEFFICIENT * (der_target - der))
  
  if (flow_rate[i] > t[i].getFluidFlowRateMaxMax()) then
    flow_rate[i] = t[i].getFluidFlowRateMaxMax()
  elseif (flow_rate[i] < 0) then
    flow_rate[i] = 0
  end
end


function update_coil(i)
  if (speed_cur[i] >= (INDUCTION_TRESHOLD * target[i]) and not t[i].getInductorEngaged()) then
    t[i].setInductorEngaged(true)
  elseif (speed_cur[i] < (INDUCTION_TRESHOLD * target[i]) and t[i].getInductorEngaged()) then
    t[i].setInductorEngaged(false)
  end
end


for i = 1, NUMBER_OF_TURBINES do
  t[i].setActive(true)
end
update()

while running do
  event_=table.pack(event.pull(EVENT_WAIT))
  if (event_[1] == "key_down") then
    interrupt(event_[3])
    switch_mode(event_[3])
  end
  update()
  if (time_cur <= time_old) then
    time_old = time_cur - AVERAGE_LOOP
  end
  
  for i = 1, NUMBER_OF_TURBINES do
    update_flow_rate(i)
    t[i].setFluidFlowRateMax(flow_rate[i])
    if (unlock_coil[i]) then
      update_coil(i)
    end
  end
end