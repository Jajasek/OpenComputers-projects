local minitel = require("minitel")
local gpu = require("component").gpu
local event = require("event")

local x, y = gpu.getResolution()
local WAIT = 1.5
local response, other = false, 0

local f=io.open("/etc/hostname","rb")
hostname = f:read()
f:close()

if hostname == "4" then
    forvard_to = "0"
else
    forvard_to = tostring(tonumber(hostname) + 1)
end

math.randomseed(require("computer").uptime())
for _ = 1, 20 do
  math.random(0, 100)
end
math.randomseed(require("computer").uptime() + math.random(0, 1000))

if hostname == "0" then
    gpu.setBackground(15, true)
    gpu.fill(1, 1, x, y, " ")
    os.sleep(WAIT)
    while not minitel.rsend(tostring(math.random(0, 4)), 0, "My hostname is "..hostname) do end
end

while true do
    gpu.setBackground(0, true)
    gpu.fill(1, 1, x, y, " ")
    repeat
      local event, from, port, data = event.pull()
      if event == "key_down" and port == 3 then
        os.exit()
      end
    until (event == "net_msg")
    gpu.setBackground(15, true)
    gpu.fill(1, 1, x, y, " ")
    os.sleep(WAIT)
    repeat
      repeat
        other = tostring(math.random(0, 4))
      until (other ~= hostname)
      response = minitel.rsend(other, 0, "My hostname is "..hostname)
    until response
end