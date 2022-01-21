local t1 = require("loadComp").t1
local t2 = require("loadComp").t2
local t3 = require("loadcomp").t3
local t = {t1, t2, t3}
local g = require("graph")
local graphs = {}
local comp = require("computer")
local component = require("component")
local event = require("event")
local floor = require("math").floor
local modem = component.modem

local FPS = 1
local EVENT_WAIT = 0.005
local MODEM_INFO_PORT = 1
local NUMBER_OF_TURBINES = 3
local sum_flow = {}
local count = 0
local sum_speed = {}
local time_cur, time_old = 0, 0
local target = {}

for i = 1, NUMBER_OF_TURBINES do
  sum_flow[i] = 0
  sum_speed[i] = 0
  target[i] = nil
end

do
  local addr = {}
  local i = 1
  for a, _ in component.list("gpu") do
    addr[i] = a
    i = i + 1
  end
  local graph1 = g.new(addr[1], "1c91b227-95bd-4a11-b95d-e341ec8f3ce4", 3)
  local graph2 = g.new(addr[2], "442d08ed-4c12-4095-a702-ff2a2e2d1cd2", 3)
  local graph3 = g.new(addr[3], "6e33073d-c822-45e5-b2bd-dacc5489d50f", 3)
  graphs = {graph1, graph2, graph3}
  modem.open(MODEM_INFO_PORT)
end

for i = 1, NUMBER_OF_TURBINES do
  --graphs[i].setNumberOfValues(3)
  --graphs[i].gpu.setPaletteColor(1, 0xFFFF00)
  --graphs[i].gpu.setPaletteColor(2, 0xFF8A00)
  --graphs[i].gpu.setPaletteColor(3, 0x00FF00)
  --graphs[i].gpu.setPaletteColor(15, 0x000000)
  graphs[i].default_palette()
  graphs[i].clear()
end

function interrupt(key)
  if (key == 3) then
    print("interrupting...")
    for i = 1, NUMBER_OF_TURBINES do
      graphs[i].clear()
    end
    os.exit()
  end
end


while true do
  repeat
    event_=table.pack(event.pull(EVENT_WAIT))
    if (event_[1] == "key_down") then
      interrupt(event_[3])
    elseif event_[1] == "modem_message" and event_[6] == "t_targets" then
      target = {event_[7], event_[8], event_[9]}
    end
  until event_[1] == nil
  for i = 1, NUMBER_OF_TURBINES do
    sum_flow[i] = sum_flow[i] + t[i].getFluidFlowRateMax()
    sum_speed[i] = sum_speed[i] + t[i].getRotorSpeed()
  end
  count = count + 1
  time_old = time_cur
  time_cur = comp.uptime()
  if floor(time_old * FPS) < floor(time_cur * FPS) then
    for i = 1, NUMBER_OF_TURBINES do
      graphs[i].add_percent((sum_flow[i] / count) / t[i].getFluidFlowRateMaxMax(),
                            (sum_speed[i] / count) / 2000,
                            (target[i] and target[i] / 2000) or nil)
      sum_flow[i] = 0
      sum_speed[i] = 0
    end
    count = 0
  end
end