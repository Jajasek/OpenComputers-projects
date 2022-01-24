local fs = require('filesystem')

local PATH = '/etc/machines.cfg'

if fs.exists(PATH) and (not fs.isDirectory(PATH)) then
  fs.remove(PATH)
end
package.loaded.machines = nil
require('machines')