--if the script was just run and the computer was rebooted, do not run it again
local term = require("term")
term.write("Network install autorun started\n")
term.write("Block checking... ")
local computer = require("computer")
local filesystem = require("filesystem")
local shell = require("shell")
if filesystem.exists("/mnt/72f/autorun_block") then
  autorun_block = io.open("/mnt/72f/autorun_block", "r")
  local computer_address = autorun_block:read()
  autorun_block:close()
  shell.execute("rm /mnt/72f/autorun_block")
  if computer_address == computer.address() then
    --the floppy could have been removed from previous computer right before rebooting, so there has to be an address check
    term.write("block detected. Exiting.\n")
    return
  end
end
term.write("no block detected.\n")

--set wake messages
term.write("Setting wake messages... ")
local component = require("component")
for a, t in component.list("modem") do
  component.invoke(a, "setWakeMessage", ":this is a wake message:", true)
end
for a, t in component.list("tunnel") do
  component.invoke(a, "setWakeMessage", ":this is a wake message:", true)
end
term.write("done.\n")

--copy all files
term.write("Copying...\n")
shell.execute("cp -r -f -u -v /mnt/72f/files/* /")

--enable rc scripts
term.write("Enabling scripts...\n")
for script in io.lines("/mnt/72f/rc-list.txt") do
  term.write(script.." ")
  shell.execute("rc "..script.." enable")
end

--set a hostname, by default it iterates through non-negative whole numbers
--if ask == "true", let the user type custom hostname, otherwise generate one.
local lines_iterator = io.lines("/mnt/72f/hostname")
local def_hostname, format_, ask = tonumber(lines_iterator()), lines_iterator(), lines_iterator()
if def_hostname ~= nil then  --If ask == "true", user should get the opportunity to change the hostname (default would be <current>). But I am lazy.
  local def_hostname_formatted = string.format(format_, def_hostname)
  local hostname = def_hostname_formatted
  if ask == "true" then
    term.write("Input hostname [default: "..def_hostname_formatted.."]: ", true)
    hostname = term.read()
    hostname = hostname:sub(1, hostname:len() - 1)
    if hostname == "" then
      hostname = def_hostname_formatted
    end
  end
  if hostname == def_hostname_formatted then
    def_hostname_file = io.open("/mnt/72f/hostname", "w")
    def_hostname_file:write(def_hostname + 1 .."\n"..format_.."\n"..ask)
    def_hostname_file:close()
  end
  term.write("New hostname: "..hostname.."\n")
  local hostname_file = io.open("/etc/hostname", "w")
  hostname_file:write(hostname)
  hostname_file:close()
end

--[[ uncomment this when deleting reboot
term.clear()
computer.beep(1000, 0.5)
computer.pushSignal("key_down", component.keyboard.address, 13, 28, "Jachym2002")
--]]

--reboot and create a temporary block file to prevent this script from running again
term.write("Creating block file...")
block = io.open("/mnt/72f/autorun_block", "w")
block:write(computer.address())
block:close()
require("computer").shutdown(true)
