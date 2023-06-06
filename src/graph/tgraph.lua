local machines = require('machines')
local graph = require('graph')
local computer = require('computer')
local component = require('component')
local event = require('event')

local modem = component.modem
local EVENT_WAIT = 0.005
local PATH = '/etc/tgraph.cfg'

local function loadConfig(path)
  local file, msg = io.open(path,'rb')
  if not file then
    io.stderr:write('Error while trying to read file at '..path..': '..msg)
    return
  end
  local config_string = file:read('*a')
  file:close()
  local serial = require('serialization')
  return serial.unserialize(config_string)
end

print('To change the config, see configuration file '..PATH..'. For reference, '
          ..'see Jajasek/OpenComputers-projects/src/graph/tgraph.cfg.')
local config = loadConfig(PATH)

local turbines = {}
for _, index in ipairs(config.turbines) do
  if index > #machines.turbines then
    io.stderr:write('Not enough turbines')
    os.exit()
  end
  table.insert(turbines, machines.turbines[index])
end
if #turbines > #machines.gpus then
  io.stderr:write('Not enough gpu-screen pairs')
  os.exit()
end
if #turbines ~= #config.targets then
  io.stderr:write('Inconsistent number of target indices')
  os.exit()
end

local sum_flow = {}
local count = 0
local sum_speed = {}
local time_cur, time_old = 0, 0
local target = {}
local graphs = {}
for i = 1, #turbines do
  sum_flow[i] = 0
  sum_speed[i] = 0
  target[i] = nil
  graphs[i] = graph.new(machines.gpus[i], machines.screens[i], 3)
  graphs[i].default_palette()
  graphs[i].clear()
end
modem.open(config.port)

local function interrupt()
  print("interrupting...")
  for i = 1, #turbines do
    graphs[i].clear()
  end
  os.exit()
end


while true do
  repeat
    local event_=table.pack(event.pull(EVENT_WAIT))
    if (event_[1] == 'key_down') then
      if event_[3] == 3 then
        interrupt()
      end
    elseif event_[1] == 'modem_message' and event_[6] == 't_targets' then
      for i, index in ipairs(config.targets) do
        -- if index == nil or message does not have enough targets, then ignore
        target[i] = index and index + 6 > #event_ and event_[index + 6] or nil
      end
    end
  until event_[1] == nil
  for i = 1, #turbines do
    sum_flow[i] = sum_flow[i] + turbines[i].getFluidFlowRateMax()
    sum_speed[i] = sum_speed[i] + turbines[i].getRotorSpeed()
  end
  count = count + 1
  time_old = time_cur
  time_cur = computer.uptime()
  if math.floor(time_old * config.fps) < math.floor(time_cur * config.fps) then
    for i = 1, #turbines do
      graphs[i].add_percent(
          (sum_flow[i] / count) / turbines[i].getFluidFlowRateMaxMax(),
          (sum_speed[i] / count) / 2000, (target[i] and target[i] / 2000) or nil
      )
      sum_flow[i] = 0
      sum_speed[i] = 0
    end
    count = 0
  end
end