local component = require("component")
local math = require("math")
local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local min = math.min
local max = math.max

local SPACE = 7
local graph = {}


function string_repeat(str, count)
  if count == 0 then return "" end
  local out = str
  for i = 1, count - 1 do
    out = out .. str
  end
  return out
end


function pixel_to_char(y)  -- returns the y-coordinate of character cell, that contains the specified pixel (both counted from top)
  return floor((y + 1) / 2)
end


function counterpart(y)  -- returns the y-coordinate of the pixel, that is in the same character cell as y
  if y % 2 == 0 then
    return y - 1
  else
    return y + 1
  end
end


function is_between(a, b, c)  -- returns true if b is between a and c (inclusive)
  return (c - b) * (b - a) >= 0
end


function sgn(a)  -- returns sign of a, i.e. 1 for non-negative values and -1 for negative
  return a >= 0 and 1 or -1
end


function int(a)  -- rounds a towards zero
  return sgn(a) * floor(abs(a))
end


function graph.new(gpu, screen, number_of_values)  -- Supports both address and proxy
  local new_graph = {}  -- the returned API, items starting with _underscore are meant to be private
  new_graph._draw = {}  -- table of methods which draw graph parts and lines
  if type(gpu) == "string" then
    new_graph.gpu = component.proxy(gpu)
  else
    new_graph.gpu = gpu
  end
  if type(screen) == "string" then
    new_graph.screen = component.proxy(screen)
  else
    new_graph.screen = screen
  end
  new_graph.gpu.bind(new_graph.screen.address)
  new_graph._plotted = {{}, {}}  -- there will be saved the color of all pixels in last two columns, 
   --                               _plotted[0] is on the left. Pixels are counted from top.
  new_graph._cursor = 1  -- the x-coordinate of left
  new_graph._direct_side = 1  -- the side (0 is on the left) on which the middle point of direct part
   --                            will be drawn if other resolving methods fail
  new_graph._direct_invert = false  -- true in case _direct_side depends on direction of graphed direct part,
   --                                  i.e. after simple non-constant part
  new_graph._number_of_values = number_of_values or 1
  new_graph._major = {}
  new_graph._minor = {}
  new_graph._old = {}
  new_graph._buffer_full = true  -- the alternating bool value, when true, new part is drawn
  
  
  function new_graph.set_gpu(gpu)  -- Supports both address and proxy, clears screen
    new_graph._reset_values()
    if type(gpu) == "string" then
      new_graph.gpu = component.proxy(gpu)
    else
      new_graph.gpu = gpu
    end
    new_graph.gpu.bind(new_graph.screen.address)
  end


  function new_graph.set_screen(screen)  -- Supports both address and proxy, clears both old and new screen
    new_graph._reset_values()
    if type(screen) == "string" then
      new_graph.screen = component.proxy(screen)
    else
      new_graph.screen = screen
    end
    new_graph.gpu.bind(new.screen.address)
    new_graph.clear()
  end
  
  
  function new_graph.get_number_of_values()
    return new_graph._number_of_values
  end
  

  function new_graph.set_number_of_values(number)  -- Number of graphs per screen is at most 15 due to the size of palette
    assert(number <= 15, "Maximum number of graphed values per screen is 15")
    new_graph._number_of_values = number
    new_graph._reset_values()
    new_graph.clear()
  end


  function new_graph.clear()  -- also rewinds cursor
    local x, y = new_graph.gpu.getResolution()
    new_graph.gpu.setBackground(15, true)
    new_graph.gpu.fill(1, 1, x, y, " ")
    new_graph._cursor = 1
    for i = 1, 2 do
      for j = 1, 2 * y do
        new_graph._plotted[i][j] = 15
      end
    end
  end
  
  
  function new_graph.default_palette()  -- set the palette to the standart minecraft colors as saved in /usr/lib/colorCodes.lua
    for index, color in ipairs(require("colorCodes")) do
      new_graph.gpu.setPaletteColor(index - 1, color)
    end
  end
  
  
  function new_graph._reset_values()  -- also clears screen
    new_graph._major = {}
    new_graph._minor = {}
    new_graph._old = {}
    for i = 1, new_graph._number_of_values do
      new_graph._major[i] = nil
      new_graph._minor[i] = nil
      new_graph._old[i] = nil
    end
    new_graph._buffer_full = true
    new_graph.clear()
  end
  
  
  function new_graph._get_x(side)  -- returns the x-coordinate of side (0 for left, 1 for right) based on new_graph._cursor.
    local x, _ = new_graph.gpu.getResolution()
    return (new_graph._cursor - 1 + side) % x + 1
  end
  
  
  function new_graph._check(input)
    local _, y = new_graph.gpu.getResolution()
    if input == nil or input < 1 or input > 2 * y then
      return
    else
      return input
    end
  end
  
  
  function new_graph.add(...)
    if new_graph._buffer_full then  -- draw new part
      new_graph._buffer_full = false
      for index = 1, new_graph._number_of_values do
        new_graph._major[index] = new_graph._check(select(index, ...))
        new_graph._select(index)
        new_graph._old[index] = new_graph._major[index]
      end
      new_graph._plotted[0] = new_graph._plotted[1]
      new_graph._plotted[1] = {}
      local x_resolution, y_resolution = new_graph.gpu.getResolution()
      for y = 1, 2 * y_resolution do
        new_graph._plotted[1][y] = 15
      end
      new_graph.gpu.setBackground(15, true)
      new_graph.gpu.fill(((new_graph._cursor + SPACE) % x_resolution) + 1, 1, 1, y_resolution, " ")
      new_graph._cursor = (new_graph._cursor % x_resolution) + 1
    else  -- only save minor
      new_graph._buffer_full = true
      for index = 1, new_graph._number_of_values do
        new_graph._minor[index] = new_graph._check(select(index, ...))
      end
    end
  end
  
  
  function new_graph.add_percent(...)
    local values = {}
    local _, y = new_graph.gpu.getResolution()
    local coefficient = 2 * y - 1
    for i = 1, new_graph._number_of_values do
      value = select(i, ...)
      if value == nil then
        values[i] = nil
      else
        values[i] = floor(coefficient * (1 - value) + 0.5) + 1
      end
    end
    new_graph.add(table.unpack(values))
  end
  
  
  function new_graph._select(index)  -- the logic that decides what part to draw
    if new_graph._minor[index] == nil and new_graph._major[index] == nil then
       -- there are no new values since last drawed part
      new_graph._direct_side = 1
      new_graph._direct_invert = false
      return
    end
    
    if new_graph._minor[index] == nil then
       -- graph is splitted between old and major, draw dot at major
      new_graph._draw.simple(index)
      new_graph._direct_side = 1
      new_graph._direct_invert = false
    
    elseif new_graph._old[index] ~= nil and new_graph._major[index] ~= nil then
       -- four standard parts
      if abs(new_graph._major[index] - new_graph._old[index]) <= 1 and 
          (new_graph._minor[index] == new_graph._major[index] or new_graph._minor[index] == new_graph._old[index]) then
        new_graph._draw.simple(index)
        if new_graph._major[index] == new_graph._old[index] then
          new_graph._direct_side = 1
          new_graph._direct_invert = false
        elseif new_graph._major[index] > new_graph._old[index] then
          new_graph._direct_side = 0
          new_graph._direct_invert = true
        else
          new_graph._direct_side = 1
          new_graph._direct_invert = true
        end
        
      elseif is_between(new_graph._old[index], new_graph._minor[index], new_graph._major[index]) then
        new_graph._draw.direct(index)
      
      elseif is_between(new_graph._old[index], new_graph._major[index], new_graph._minor[index]) then
        new_graph._draw.overshoot(index)
      
      elseif is_between(new_graph._minor[index], new_graph._old[index], new_graph._major[index]) then
        new_graph._draw.opposite(index)
      
      else
        assert(false, string.format("Detected new graph part: %d, %d, %d", new_graph._old[index], new_graph._minor[index], new_graph._major[index]))
      end
      
    elseif new_graph._old[index] == nil and new_graph._major[index] == nil then
       -- draw dot at minor (left)
      new_graph._draw.line(new_graph._minor[index], new_graph._minor[index], index - 1, 0)
    
    elseif new_graph._old[index] ~= nil then
       -- only connection from old to minor
      new_graph._draw.line(new_graph._old[index], new_graph._minor[index], index - 1, 0)
    
    else
       -- only connection from minor to major
      new_graph._draw.line(new_graph._minor[index], new_graph._major[index], index - 1, 1)
    
    end
  end
  
  
  function new_graph._draw.simple(index)
    new_graph._draw.line(new_graph._major[index], new_graph._major[index], index - 1, 1)
  end


  function new_graph._draw.direct(index)
    new_graph._direct_invert = false
    if abs(new_graph._major[index] - new_graph._minor[index]) > abs(new_graph._minor[index] - new_graph._old[index]) then
       --  minor closer to old, therefore on the left
      new_graph._draw.line(new_graph._old[index], new_graph._minor[index], index - 1, 0)
      new_graph._draw.line(new_graph._minor[index] + sgn(new_graph._major[index] - new_graph._old[index]), new_graph._major[index], index - 1, 1)
      new_graph._direct_side = 0
    elseif abs(new_graph._major[index] - new_graph._minor[index]) < abs(new_graph._minor[index] - new_graph._old[index]) then
       --  minor closer to major, therefore on the right
      new_graph._draw.line(new_graph._old[index], new_graph._minor[index] - sgn(new_graph._major[index] - new_graph._old[index]), index - 1, 0)
      new_graph._draw.line(new_graph._minor[index], new_graph._major[index], index - 1, 1)
      new_graph._direct_side = 1
    else
       --  minor in the middle, resolving based on previous part
      if new_graph._direct_invert and new_graph._major[index] > new_graph._old[index] then
        new_graph._direct_side = 1 - new_graph._direct_side
      end
      new_graph._draw.line(new_graph._old[index],
          new_graph._minor[index] - new_graph._direct_side * sgn(new_graph._major[index] - new_graph._old[index]), index - 1, 0)
      new_graph._draw.line(new_graph._minor[index] + (1 - new_graph._direct_side) * sgn(new_graph._major[index] - new_graph._old[index]),
          new_graph._major[index], index - 1, 1)
    end
  end


  function new_graph._draw.overshoot(index)
    if new_graph._minor[index] > new_graph._old[index] then  -- down, then up
      local middle = new_graph._old[index] + ceil((new_graph._minor[index] - new_graph._old[index]) / 2) - 1
      new_graph._draw.line(new_graph._old[index], middle, index - 1, 0)
      new_graph._draw.line(min(middle + 1, new_graph._major[index]), new_graph._minor[index], index - 1, 1)
    else  -- up, then down
      local middle = new_graph._old[index] + floor((new_graph._minor[index] - new_graph._old[index]) / 2) + 1
      new_graph._draw.line(new_graph._old[index], middle, index - 1, 0)
      new_graph._draw.line(max(middle - 1, new_graph._major[index]), new_graph._minor[index], index - 1, 1)
    end
    new_graph._direct_side = 1
    new_graph._direct_invert = false
  end


  function new_graph._draw.opposite(index)
    if new_graph._minor[index] > new_graph._old[index] then  -- down, then up
      local middle = new_graph._major[index] + ceil((new_graph._minor[index] - new_graph._major[index]) / 2) - 1
      new_graph._draw.line(min(middle + 1, new_graph._old[index]), new_graph._minor[index], index - 1, 0)
      new_graph._draw.line(new_graph._major[index], middle, index - 1, 1)
    else  -- up, then down
      local middle = new_graph._major[index] + floor((new_graph._minor[index] - new_graph._major[index]) / 2) + 1
      new_graph._draw.line(max(middle - 1, new_graph._old[index]), new_graph._minor[index], index - 1, 0)
      new_graph._draw.line(new_graph._major[index], middle, index - 1, 1)
    end
    new_graph._direct_side = 0
    new_graph._direct_invert = false
  end


  function new_graph._draw.line(y1, y2, color_index, side)
     -- Draws vertical line overwriting only colors with higher index (lower priority). side: 0 for left, 1 for right
     -- the order of y1 and y2 is not restricted
    local y_bottom = max(y1, y2)
    local y_top = min(y1, y2)
    local draw_start = nil
    for y = y_top, y_bottom do
      if new_graph._plotted[side][y] > color_index then  -- overwrite
        new_graph._plotted[side][y] = color_index
        if draw_start == nil then  -- begin overwriting
          draw_start = y
        end
      elseif draw_start ~= nil then  -- end owerwriting
        new_graph._draw.segment(y - 1, draw_start, color_index, side)
        draw_start = nil
      end
    end
    if draw_start ~= nil then
      new_graph._draw.segment(y_bottom, draw_start, color_index, side)
    end
  end


  function new_graph._draw.segment(y_bottom, y_top, color_index, side)  -- Draws vertical line, y_bottom and y_top are inclusive.
    new_graph.gpu.setForeground(color_index, true)
    local str_print = ""  -- the string, that will be vertically printed
    local str_end = ""  -- a bit that will be concatenated to str_print
    local fill_start  -- y-coordinate of the first character filled with █
    local background = nil
    if y_top % 2 == 0 then
      str_print = "▄"
      background = new_graph._plotted[side][counterpart(y_top)]
      fill_start = pixel_to_char(y_top) + 1
    else
      fill_start = pixel_to_char(y_top)
    end
    if y_bottom % 2 == 1 then
      str_print = str_print .. string_repeat("█", pixel_to_char(y_bottom) - fill_start)
      new_graph.gpu.setBackground(new_graph._plotted[side][counterpart(y_bottom)], true)
      if background ~= nil and background ~= new_graph._plotted[side][counterpart(y_bottom)] then
        new_graph.gpu.set(new_graph._get_x(side), pixel_to_char(y_bottom), "▀", true)
        new_graph.gpu.setBackground(background, true)
      else
        str_print = str_print .. "▀"
      end
    else
      if background ~= nil then
        new_graph.gpu.setBackground(background, true)
      end
      str_print = str_print .. string_repeat("█", pixel_to_char(y_bottom) + 1 - fill_start)
    end
    new_graph.gpu.set(new_graph._get_x(side), pixel_to_char(y_top), str_print, true)
  end
  
  
  new_graph._reset_values()
  return new_graph
end


return graph