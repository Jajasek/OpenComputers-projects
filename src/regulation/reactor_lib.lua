local r, t1, t2, t3, s1, s2, w, p = table.unpack(require("loadComp"))
local component = require("component")
local uptime = require("computer").uptime
local event = require("event")
local keyboard = require("keyboard")
local sides = require("sides")
local regulation = require("regulation")

component.invoke("d4980a51-df2c-4d39-8b54-a23b0a14248b", "bind", "e64ff5ef-2276-4f75-a2db-732c077d8152")
component.setPrimary("gpu", "d4980a51-df2c-4d39-8b54-a23b0a14248b")

local FPS = 0.5  --self-explanatory

local target = 0.93  --the fraction of available steam storage space that we want to be filled
local MAX_CRL = 90  --when control rods are almost fully inserted, the reaction starts to wierdly fluctuate
local WATER_EMERGENCY_STOP = 0.5
local PRESSURE_TRESHOLD = 0.97  --enter standby mode. During very low steam consumption the pressure
                                --oscillates around target with a deviation of (PRESSURE_TRESHOLD - target).
local EVENT_WAIT = 0.005  --the timeout for event.pull()

local running = true
local mode = nil  --can be "balance", "standby" or "stop"


function get_pressure()
  return (s1.getTankLevel(sides.west) + s2.getTankLevel(sides.west)) / 
         (s1.getTankCapacity(sides.west) + s2.getTankCapacity(sides.west))
end


local PDM = regulation.PDM(
  get_pressure,
  r.setAllControlRodLevels,
  target, 0.8, 30,
  MAX_CRL, true
)


function init()
  local init_crl = 0
  for i = 0, r.getNumberOfControlRods() - 1 do
    init_crl = init_crl + r.getControlRodLevel(i)
  end
  PDM.init(init_crl / r.getNumberOfControlRods())
end


function interrupt()
  print("interrupting...")
  change_mode("stop")
  running = false
end


function change_mode(new)
  print('entering mode "'..new..'"')
  mode = new
end


local grapher_thread = require("thread").create(function()
  local graph = require("graph").new("f0a2e231-ee41-4d37-b997-b8fccddb5e5b", "ba763c9b-4373-4762-a20a-e6c48ccb6a89", 3)
  graph.default_palette()
  while true do
    os.sleep(0.5/FPS)
    graph.add_percent(
      get_pressure(),
      r.getControlRodLevel(0) / 100,
      target
    )
  end
end)

init()
change_mode("balance")
while running do
  repeat
    event_=table.pack(event.pull(EVENT_WAIT))
    if (event_[1] == "key_down") then
      if (event_[3] == 3) then
        interrupt()
      elseif event_[3] == string.byte(" ") then
        change_mode("stop")
      elseif event_[3] == string.byte("b") then
        change_mode("balance")
        init()
      elseif event_[3] == string.byte("s") then
        change_mode("standby")
      end
    end
  until event_[1] == nil
  
  if (get_pressure() >= PRESSURE_TRESHOLD and mode == "balance") then
    change_mode("standby")
  elseif (get_pressure() <= (2*target) - PRESSURE_TRESHOLD and mode == "standby") then
    change_mode("balance")
  end
  
  if (r.getActive() and mode == "standby" or mode == "stop") then
    r.setActive(false)
  elseif (not r.getActive() and mode == "balance") then
    r.setActive(true)
  end
  
  if mode == "balance" then
    PDM()
    if (w.getTankLevel(sides.south) < (WATER_EMERGENCY_STOP * w.getTankCapacity(sides.south))) then
      change_mode("stop")
    end
  end
end
grapher_thread:kill()
