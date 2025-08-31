-- vim: set ft=lua:

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MacWatcher"

local RESUME = "resume"
local SUSPEND = "suspend"
local WIFI = "wifi"

obj.suspendWatcher = nil
obj.wifiWatcher = nil
obj.hooks = {}
obj.hooks[RESUME] = {}
obj.hooks[SUSPEND] = {}
obj.hooks[WIFI] = {}
obj._timers = {}
obj.cooldown = 5
obj.lastHook = nil
obj.lastHookTime = 0
obj.taskTimeout = 30

local logger = hs.logger.new(obj.name, "info")

local function debugOut(label, data)
	if logger.level < 4 then
		return
	end
	if not data or data == "" then
		return
	end
	for line in data:gmatch("[^\r\n]+") do
		logger.d(label .. ": " .. line)
	end
end

function obj:_executeAsyncCmd(cmd, args)
	local fullCmd = cmd .. "; args: " .. hs.inspect(args)
	logger.i("Executing command: " .. fullCmd)
	local timeoutTimer
	local task = hs.task.new(cmd, function(exitCode, _, _)
		-- FIXME: Getting errors:
		-- ** Warning:   LuaSkin: hs.task terminationHandler block encountered an exception:
		--		 *** -[NSConcreteFileHandle readDataOfLength:]: Resource temporarily unavailable
		--  Related https://github.com/Hammerspoon/hammerspoon/issues/3210
		exitCode = exitCode or -1
		logger.df("Exit code: %d", exitCode or -1)
		if exitCode ~= 0 then
			logger.ef("Execution failed: %s; exit code: %d", exitCode)
		end
		if timeoutTimer then
			logger.d("Stopping timeout timer")
			timeoutTimer:stop()
			timeoutTimer = nil
		end
	end, function(_, stdOut, stdErr)
		debugOut("Output", stdOut)
		debugOut("Error Output", stdErr)
		return true
	end, args)
	task:closeInput()
	timeoutTimer = hs.timer.doAfter(self.taskTimeout, function()
		if task and task:isRunning() then
			logger.wf("Terminating task %s (PID: %d) after %f seconds", hs.inspect(task), task:pid() or -1,
				self.taskTimeout)
			task:terminate()
		end
	end)
	task:start()
end

function obj:_execute(cmd, args)
	if not cmd then
		logger.e("No command or function provided")
		return
	end

	if type(cmd) == "string" then
		self:_executeAsyncCmd(cmd, args)
	else
		logger.ef("Invalid cmd type: %s", type(cmd))
	end
end

function obj:_executeAfter(cmd, args, delay)
	local timerKey = tostring(cmd)
	if self._timers[timerKey] then
		logger.d("Canceling existing timer for key: %s", timerKey)
		self._timers[timerKey]:stop()
		self._timers[timerKey] = nil
	end

	if delay <= 0 then
		self:_execute(cmd, args)
		return
	end

	logger.df("Scheduling command with delay: %f seconds for key: %s", delay, timerKey)
	self._timers[timerKey] = hs.timer.doAfter(delay, function()
		self:_execute(cmd, args)
		self._timers[timerKey] = nil
	end)
end

function obj:_cancelAllTimers()
	for key, timer in pairs(self._timers) do
		logger.d("Canceling timer for key: %s", key)
		timer:stop()
	end
	self._timers = {}
end

local function hasElements(t)
	return t and #t > 0
end

function obj:_executeCmd(item, extraArgs)
	local args
	if hasElements(item.args) then
		if hasElements(extraArgs) then
			args = { table.unpack(item.args), table.unpack(extraArgs) }
		else
			args = item.args
		end
	else
		args = extraArgs
	end
	self:_executeAfter(item.cmd, args, item.delay)
end

function obj:_cmdAdd(hookType, cmd, delay)
	logger.df("Adding to %s: %s; delay: %d", hookType, hs.inspect(cmd), delay)
	local realCmd = cmd[1]
	table.remove(cmd, 1)
	table.insert(self.hooks[hookType], { cmd = realCmd, args = cmd, delay = delay })
	return self
end

function obj:whenResume(cmd, delay)
	return self:_cmdAdd(RESUME, cmd, delay)
end

function obj:whenSuspend(cmd, delay)
	return self:_cmdAdd(SUSPEND, cmd, delay)
end

function obj:onWifiChange(cmd, delay)
	return self:_cmdAdd(WIFI, cmd, delay)
end

function obj:_execHooks(hookType, args)
	local currentTime = hs.timer.secondsSinceEpoch()
	if hookType == self.lastHook then
		local last = currentTime - self.lastHookTime
		if last < self.cooldown then
			logger.df("Hooks for %s skipped due to cooldown: last run %f seconds ago < %f", hookType, last,
				self.cooldown)
			return
		end
	else
		logger.df("Resetting hooks cooldown for %s", hookType)
		self.lastHook = hookType
	end
	self.lastHookTime = currentTime
	logger.df("Executing hooks from %s", hookType)
	hs.fnutils.each(self.hooks[hookType], function(item)
		self:_executeCmd(item, args)
	end)
end

function obj:_caffeinateWatcherCallback(event)
	if
	    event == hs.caffeinate.watcher.screensaverDidStop
	    or event == hs.caffeinate.watcher.screensaverWillStop
	    or event == hs.caffeinate.watcher.screensDidUnlock
	    or event == hs.caffeinate.watcher.screensDidWake
	    or event == hs.caffeinate.watcher.sessionDidBecomeActive
	then
		logger.i("Executing resume hooks")
		self:_execHooks(RESUME)
	elseif
	    event == hs.caffeinate.watcher.screensaverDidStart
	    or event == hs.caffeinate.watcher.screensDidLock
	    or event == hs.caffeinate.watcher.screensDidSleep
	    or event == hs.caffeinate.watcher.systemWillPowerOff
	    or event == hs.caffeinate.watcher.systemWillSleep
	    or event == hs.caffeinate.watcher.sessionDidResignActive
	then
		logger.i("Executing suspend hooks")
		self:_execHooks(SUSPEND)
	elseif
	    event ~= hs.caffeinate.watcher.systemDidWake
	then
		logger.df("Unsupported caffeinate event '%s'", event)
	end
end

function obj:_ssidChangedCallback()
	local currentSSID = hs.wifi.currentNetwork() or ""
	logger.f("Executing WiFi hooks for SSID '%s'", currentSSID)
	self:_execHooks(WIFI, { currentSSID })
end

function obj:start()
	logger.f("Starting %s (resume: %d, suspend: %d, wifi: %d hooks)",
		self.name, #self.hooks[RESUME], #self.hooks[SUSPEND], #self.hooks[WIFI])
	self.suspendWatcher = hs.caffeinate.watcher.new(hs.fnutils.partial(self._caffeinateWatcherCallback, self))
	self.suspendWatcher:start()
	self.wifiWatcher = hs.wifi.watcher.new(hs.fnutils.partial(self._ssidChangedCallback, self))
	self.wifiWatcher:start()
	self:_execHooks(RESUME)
	self:_ssidChangedCallback()
end

function obj:stop()
	logger.i("Stopping " .. obj.name)
	self:_cancelAllTimers()
	if self.suspendWatcher then
		self.suspendWatcher:stop()
		self.suspendWatcher = nil
	end
	if self.wifiWatcher then
		self.wifiWatcher:stop()
		self.wifiWatcher = nil
	end
	self:_execHooks(self.suspend)
end

return obj
