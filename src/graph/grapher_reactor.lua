local machines = require('machines')
local event = require('event')

local FPS = 0.5
local running = true
local target = 0.93


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


event.listen('interrupted', function() running = false; return false end)

local graph = require('graph').new(machines.gpus[1], machines.screens[1], 3)
graph.default_palette()
while running do
  os.sleep(0.5/FPS)
  graph.add_percent(
    get_pressure(),
    machines.reactor.getControlRodLevel(0) / 100,
    target
  )
end
