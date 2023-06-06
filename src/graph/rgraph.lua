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

local graph = require('graph').new(machines.gpus[1], machines.screens[1], 5)
graph.set_palette(0xffffff, 0x663300, 0xffcc33, 0xff3333, 0xcc66cc)
event.listen(
    'interrupted', function()
      print("interrupting...")
      running = false
      graph.clear()
      return false
    end
)

while running do
  os.sleep(1/FPS - 1.1)  -- graphing takes 1.1s
  graph.add_percent(
    get_pressure(),
    machines.reactor.getControlRodLevel(0) / 100,
    machines.reactor.getFuelTemperature() / 2000,
    machines.reactor.getCasingTemperature() / 2000,
    target
  )
end
