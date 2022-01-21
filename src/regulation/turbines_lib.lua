local r, t1, t2, t3, s1, s2, w, p = table.unpack(require("loadComp"))
local t = {t1, t2, t3}
local regulation = require("regulation")
local event = require("event")
local keyboard = require("keyboard")
local modem = require("component").modem

local target = {}
local enable_coil = {}

local INDUCTION_TRESHOLD = 40
local EVENT_WAIT = 0.005
local MODEM_PERIOD = 3
local MODEM_INFO_PORT = 1
local NUMBER_OF_TURBINES = 3
local timer = event.timer(MODEM_PERIOD, function() modem.broadcast(MODEM_INFO_PORT, "t_targets", table.unpack(target)) end, math.huge)

local K_POWER1 = string.byte("1")
local K_POWER2 = string.byte("2")
local K_POWER3 = string.byte("3")
local K_POWER4 = string.byte("4")
local K_STANDBY = string.byte("0")
local K_STOP = string.byte(" ")

local regulators = {}
for i = 1, NUMBER_OF_TURBINES do
  regulators[i] = regulation.PDM(
    t[i].getRotorSpeed,
    t[i].setFluidFlowRateMax,
    0,
    0.03, 0.1,
    2000, false
  )
end


function interrupt(key)
  if (key == 3) then
    print("interrupting...")
    for i = 1, NUMBER_OF_TURBINES do
      t[i].setActive(false)
      t[i].setInductorEngaged(false)
      t[i].setFluidFlowRateMax(0)
    end
    event.cancel(timer)
    os.exit()
  end
end


function stop()
  print("EMERGENCY STOP")
  for i = 1, NUMBER_OF_TURBINES do
    target[i] = 0
    enable_coil[i] = true
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
    enable_coil = {true, false, false}
  elseif key == K_POWER2 then
    print('switching to mode "power_2"')
    target = {900, 1845, 900}
    enable_coil = {true, true, false}
  elseif key == K_POWER3 then
    print('switching to mode "power_3"')
    target = {900, 1845, 1845}
    enable_coil = {true, true, true}
  elseif key == K_POWER4 then
    print('switching to mode "power_4"')
    target = {1845, 1845, 1845}
    enable_coil = {true, true, true}
  elseif key == K_STANDBY then
    print('switching to mode "standby"')
    target = {60, 60, 60}
    enable_coil = {false, false, false}
  else
    return
  end
  for i = 1, NUMBER_OF_TURBINES do
    regulators[i].set_setpoint(target[i])
  end
end


for i = 1, NUMBER_OF_TURBINES do
  t[i].setActive(true)
  regulators[i].init(t[i].getFluidFlowRateMax())
end
switch_mode(K_STANDBY)

while true do
  event_=table.pack(event.pull(EVENT_WAIT, "key_down"))
  if (event_[1] == "key_down") then
    interrupt(event_[3])
    switch_mode(event_[3])
  end
  
  for i = 1, NUMBER_OF_TURBINES do
    regulators[i]()
    local speed = t[i].getRotorSpeed()
    if not enable_coil[i] then
      t[i].setInductorEngaged(false)
    elseif speed >= (target[i] - INDUCTION_TRESHOLD) and not t[i].getInductorEngaged() then
      t[i].setInductorEngaged(true)
    elseif speed < (target[i] - INDUCTION_TRESHOLD) and t[i].getInductorEngaged() then
      t[i].setInductorEngaged(false)
    end
  end
end