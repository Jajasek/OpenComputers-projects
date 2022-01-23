--[[
  A general regulator library, originally designed to regulate the Big Reactors nuclear reactors and steam turbines.
--]]


local uptime = require("computer").uptime
local regulation = {DT = 0.01}  --when uptime() overflows, the old time is given by (t - DT).


function regulation.PID(process_var, control_var, setpoint, proportional_gain, integral_gain, derivative_gain, resolution, reversed)
  --[[
    Standard (bounded) PID regulator. For details see https://en.wikipedia.org/wiki/PID_controller.
    
    process_var is a parameter-less function, control_var is function with one integer parameter in range(0, resolution + 1),
    all other parameters are numbers.
    resolution is optional integer parameter, defaulting to 100.
    reversed is optional boolean parameter. If true, the action will be reversed (e.g. higher control rod levels in a reactor (MV) decrease PV). Defaults to false.
    
    The input range is given by process_var() and setpoint, but control_var only varies on the interval [0; 1] and this interval is
    then projected to the range given by resolution. This should be taken into account when tuning K's.
  --]]
  
  function P(self, t, e)
    return self.Kp * e
  end
  function I(self, t, e)
    self._integral = self._integral + self.Ki * (t - self._old_t) * e
    return self._integral
  end
  function D(self, t, e)
    return self.Kd * (e - self._old_e) / (t - self._old_t)
  end
  local function regulate(self)
    local t = uptime()
    local e = self.SP - self.PV()
    if t < self._old_t then
      self._old_t = t - regulation.DT
    end
    
    local MV = P(self, t, e) + I(self, t, e) + D(self, t, e)
    MV = math.max(0, math.min(1, MV))
    if self.reversed then
      MV = 1 - MV
    end
    self.MV(math.floor(MV * self.resolution + 0.5))
    
    self._old_t = t
    self._old_e = e
  end
  
  --The regulation itself is done by calling new() during every loop iteration.
  local new = setmetatable({}, {
    __call = regulate
  })
  
  new.PV = process_var
  new.MV = control_var
  new.SP = setpoint
  new.Kp = proportional_gain
  new.Ki = integral_gain
  new.Kd = derivative_gain
  
  new.resolution = resolution or 100
  new.reversed = reversed and true or false
  new._integral = 0
  new._old_t = 0
  new._old_e = 0
  
  function new.init(control_var_value)
    --call right before the loop starts to initialize _old_e and _old_t. Optional argument can be the initial state of
    --the control variable (e.g. initial control rods insertion level) and is used to compute the initial _integral term.
    new._integral = (control_var_value or 0) * new.Ki
    new._old_t = uptime()
    new._old_e = new.SP - new.PV()
  end
  
  function new.set_setpoint(setpoint)
    new.SP = setpoint
  end
  function new.set_proportional_gain(proportional_gain)
    new.Kp = proportional_gain
  end
  function new.set_integral_gain(integral_gain)
    new.Ki = integral_gain
  end
  function new.set_derivative_gain(derivative_gain)
    new.Kd = derivative_gain
  end
  function new.set_resolution(resolution)
    new.resolution = resolution
  end
  
  return new
end


function regulation.PDM(process_var, control_var, setpoint, proportional_gain, derivative_gain, resolution, reversed)
  --[[
    Custom Proportional-Derivative-Memory regulator. I have replaced the I term of the PID regulator by a variable holding the previous value of MV.
    
    process_var is a parameter-less function, control_var is function with one integer parameter in range(0, resolution + 1),
    all other paameters are numbers.
    resolution is optional integer parameter, defaulting to 100.
    reversed is optional boolean parameter. If true, the action will be reversed (e.g. higher control rod levels in a reactor (MV) decrease PV). Defaults to false.
    
    The input range is given by process_var() and setpoint, but control_var only varies on the interval [0; 1] and this interval is
    then projected to the range given by resolution. This should be taken into account when tuning K's.
  --]]
  
  function P(self, t, e)
    return self.Kp * e
  end
  function D(self, t, e)
    return self.Kd * (e - self._old_e) / (t - self._old_t)
  end
  local function regulate(self)
    local t = uptime()
    local e = self.SP - self.PV()
    if t < self._old_t then
      self._old_t = t - regulation.DT
    end
    
    local MV = P(self, t, e) + D(self, t, e) + self._memory
    MV = math.max(0, math.min(1, MV))
    self._memory = MV
    self.MV(math.floor((self.reversed and (1 - MV) or MV) * self.resolution + 0.5))
    
    self._old_t = t
    self._old_e = e
  end
  
  --The regulation itself is done by calling new() during every loop iteration.
  local new = setmetatable({}, {
    __call = regulate
  })
  
  new.PV = process_var
  new.MV = control_var
  new.SP = setpoint
  new.Kp = proportional_gain
  new.Kd = derivative_gain
  
  new.resolution = resolution or 100
  new.reversed = reversed and true or false
  new._memory = 0
  new._old_t = 0
  new._old_e = 0
  
  function new.init(control_var_value)
    --call right before the loop starts to initialize _old_e and _old_t. Optional argument can be the initial state of
    --the control variable (e.g. initial control rods insertion level) to use as the initial Memory term.
    new._memory = control_var_value or 0
    new._old_t = uptime()
    new._old_e = new.SP - new.PV()
  end
  
  function new.set_setpoint(setpoint)
    new.SP = setpoint
  end
  function new.set_proportional_gain(proportional_gain)
    new.Kp = proportional_gain
  end
  function new.set_derivative_gain(derivative_gain)
    new.Kd = derivative_gain
  end
  function new.set_resolution(resolution)
    new.resolution = resolution
  end
  
  return new
end


return regulation
