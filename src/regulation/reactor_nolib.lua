local r, t1, t2, t3, s1, s2, w, p = table.unpack(require("loadComp"))
local comp = require("computer")
local event = require("event")
local keyboard = require("keyboard")
local sides = require("sides")


local target = 0.93

local MAX_CRL = 90
local SLOPE_COEFFICIENT = 0.05
local REGULATION_COEFFICIENT = -2000
local WATER_TRESHOLD = 0.3
local WATER_EMERGENCY_STOP = 0.1
local PRESSURE_TRESHOLD = 0.97
local AVERAGE_LOOP = 0.1
local EVENT_WAIT = 0.005

local running = true
local mode = "keep_pressure"  --can be "keep_pressure", "standby" or "stop"
local time_old, time_cur
local pressure_old, pressure_cur
local crl = 0
for i = 0, r.getNumberOfControlRods() - 1 do
  crl = crl + r.getControlRodLevel(i)
end
crl = crl / r.getNumberOfControlRods()


function stop()
  change_mode("stop")
  r.setActive(false)
end


function interrupt()
  print("interrupting...")
  running = false
  p.setOutput(sides.east, 0)
end


function change_mode(new)
  print('entering mode "'..new..'"')
  mode = new
end


function update()
  time_old = time_cur
  time_cur = comp.uptime()
  pressure_old = pressure_cur
  pressure_cur = (s1.getTankLevel(sides.west) + s2.getTankLevel(sides.west)) / 
                 (s1.getTankCapacity(sides.west) + s2.getTankCapacity(sides.west))
end


function update_crl()
  if (mode == "standby" or mode == "stop") then
    crl = MAX_CRL
    return
  end

  local difference = target - pressure_cur
  local der_target = SLOPE_COEFFICIENT * difference
  local der = (pressure_cur - pressure_old) / (time_cur - time_old)
  crl = crl + (REGULATION_COEFFICIENT * (der_target - der))
  --print(difference*10000, der_target*10000, der*10000, crl)
  if (crl > MAX_CRL) then
    crl = MAX_CRL
  elseif (crl < 0) then
    crl = 0
  end
end


function update_pumps()
  if (w.getTankLevel(sides.up) < (WATER_TRESHOLD * w.getTankCapacity(sides.up))) then
    if (p.getOutput(sides.east) ~= 0) then
      p.setOutput(sides.east, 0)
    end
  else
    if (p.getOutput(sides.east) ~= 15) then
      p.setOutput(sides.east, 15)
    end
  end
end

r.setActive(true)
update()
while running do
  event_=table.pack(event.pull(EVENT_WAIT))
  if (event_[1] == "key_down") then
    if (event_[3] == 3) then
      interrupt()
    elseif event_[3] == string.byte(" ") then
      stop()
    elseif event_[3] == string.byte("k") then
      change_mode("keep_pressure")
      r.setActive(true)
    end
  end
  update()
  if (time_cur <= time_old) then
    time_old = time_cur - AVERAGE_LOOP
  end
  
  if (pressure_cur >= PRESSURE_TRESHOLD and mode == "keep_pressure") then
    change_mode("standby")
    r.setActive(false)
  elseif (pressure_cur <= (2*target) - PRESSURE_TRESHOLD and mode == "standby") then
    change_mode("keep_pressure")
    r.setActive(true)
  end
  if (w.getTankLevel(sides.up) < (WATER_EMERGENCY_STOP * w.getTankCapacity(sides.up))) then
    stop()
  end
  update_crl()
  r.setAllControlRodLevels(crl)
  update_pumps()
end
