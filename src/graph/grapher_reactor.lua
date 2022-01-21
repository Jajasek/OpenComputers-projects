local r, t1, t2, t3, s1, s2, w, p = table.unpack(require("loadComp"))
local component = require("component")
local event = require("event")
local sides = require("sides")

local FPS = 0.5
local running = true
local target = 0.93


function get_pressure()
  return (s1.getTankLevel(sides.west) + s2.getTankLevel(sides.west)) / 
         (s1.getTankCapacity(sides.west) + s2.getTankCapacity(sides.west))
end


event.listen("interrupted", function() running = false; return false end)

local graph = require("graph").new("f0a2e231-ee41-4d37-b997-b8fccddb5e5b", "ba763c9b-4373-4762-a20a-e6c48ccb6a89", 3)
graph.default_palette()
component.invoke("d4980a51-df2c-4d39-8b54-a23b0a14248b", "bind", "e64ff5ef-2276-4f75-a2db-732c077d8152")
component.setPrimary("gpu", "d4980a51-df2c-4d39-8b54-a23b0a14248b")
while running do
  os.sleep(0.5/FPS)
  graph.add_percent(
    get_pressure(),
    r.getControlRodLevel(0) / 100,
    target
  )
end
