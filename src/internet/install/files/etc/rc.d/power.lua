local component = require("component")
local minitel = require("minitel")


local function route()
  local f = io.open("/etc/minitel.cfg","rb")
  if f then
    local output = require("serialization").unserialize(f:read("*a")).route
    f:close()
    if output == nil then return true end
    return output
  else
    return true
  end
end


local function broadcast_wake_message(exclude)
  --[[
  for a, t in component.list("modem") do
    if a ~= exclude then
      local msg, _ = component.invoke(a, "getWakeMessage")
      component.invoke(a, "broadcast", 1, msg)
    end
  end
  for a, t in component.list("tunnel") do
    if a ~= exclude then
      local msg, _ = component.invoke(a, "getWakeMessage")
      component.invoke(a, "send", msg)
    end
  end
  --]]
  minitel.usend("~", 0, nil, ":this is a wake message:")
end


function start()
  --forward the broadcast wake message
  broadcast_wake_message()
  
  --start shutdown message listener
  event = require("event")
  event.listen("net_broadcast",
    function(event_name, from, port, data)
      if port == 0 and data == ":this is a shutdown message:" then
        event.timer(2, require("computer").shutdown, 1)
      end
    end
  )
  
  --start wakeup message forwardinf listener
  --[[
  if route() then
    event.listen("modem_message",
      function(event_name, localAddress, remoteAddress, port, distance, message, ...)
        local wake_msg, _ = component.invoke(localAddress, "getWakeMessage")
        if message == wake_msg then
          broadcast_wake_message(localAddress)
        end
      end
    )
  end
  --]]
end


function shutdown()
  minitel.usend("~", 0, ":this is a shutdown message:")
  event.timer(2, require("computer").shutdown, 1)
end
