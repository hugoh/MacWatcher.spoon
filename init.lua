-- vim: set ft=lua:

--- === MacWatcher ===
---
--- A Hammerspoon Spoon that runs commands on system events: wake, sleep, and WiFi changes.
---
--- Download: https://github.com/hugoh/MacWatcher.spoon/releases/latest

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MacWatcher"
obj.version = "dev"

local RESUME = "resume"
local SUSPEND = "suspend"
local WIFI = "wifi"
local STOP = "stop"

obj.suspendWatcher = nil
obj.wifiWatcher = nil
obj.hooks = {}
obj.hooks[RESUME] = {}
obj.hooks[SUSPEND] = {}
obj.hooks[WIFI] = {}
obj.hooks[STOP] = {}
obj._timers = {}
obj._watchdogTimers = {}
obj._timerSeq = 0
--- MacWatcher.cooldown
--- Variable
--- Minimum seconds between repeated hook executions for the same event (default: 5).
obj.cooldown = 5
obj._cooldownState = {}
--- MacWatcher.taskTimeout
--- Variable
--- Maximum seconds a command may run before it is forcibly terminated (default: 30).
obj.taskTimeout = 30

local logger = hs.logger.new(obj.name, "info")

local function shellQuote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function debugOut(label, data)
	if logger.level < 4 then return end
	if not data or data == "" then return end
	for line in data:gmatch("[^\r\n]+") do
		logger.d(label .. ": " .. line)
	end
end

function obj:_executeAsyncCmd(cmd, args)
	local fullCmd = cmd .. "; args: " .. hs.inspect(args)
	logger.i("Executing command: " .. fullCmd)
	self._timerSeq = self._timerSeq + 1
	local timeoutKey = "__timeout_" .. self._timerSeq
	local timeoutTimer
	local task = hs.task.new(cmd, function(exitCode, stdOut, stdErr)
		-- FIXME: Getting errors:
		-- ** Warning:   LuaSkin: hs.task terminationHandler block encountered an exception:
		--		 *** -[NSConcreteFileHandle readDataOfLength:]: Resource temporarily unavailable
		--  Related https://github.com/Hammerspoon/hammerspoon/issues/3210
		exitCode = exitCode or -1
		logger.df("Exit code: %d", exitCode)
		if exitCode ~= 0 then
			logger.ef("Execution failed: %s; exit code: %d\nstdOut: %s\nstdErr:%s", fullCmd, exitCode, stdOut, stdErr)
		end
		self._watchdogTimers[timeoutKey] = nil
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
	local closeOk = pcall(function() task:closeInput() end)
	if not closeOk then logger.w("Failed to close task input") end
	timeoutTimer = hs.timer.doAfter(self.taskTimeout, function()
		self._watchdogTimers[timeoutKey] = nil
		if task and task:isRunning() then
			logger.wf(
				"Terminating task %s (PID: %d) after %f seconds",
				hs.inspect(task),
				task:pid() or -1,
				self.taskTimeout
			)
			task:terminate()
		end
	end)
	-- Register the watchdog timer before starting the task: hs.task's
	-- completion callback can fire synchronously from task:start() (e.g.
	-- in tests), so self._watchdogTimers must already contain the entry,
	-- and cleanup must not depend on the timeoutTimer upvalue having been
	-- assigned, to be reliably stopped/removed.
	self._watchdogTimers[timeoutKey] = timeoutTimer
	local startOk = pcall(function() task:start() end)
	if not startOk then logger.w("Failed to start task") end
end

function obj:_execute(cmd, args)
	if not cmd then
		logger.e("No command provided")
		return
	end
	self:_executeAsyncCmd(cmd, args)
end

function obj:_executeAfter(cmd, args, delay, hookType, immediate)
	local timerKey = (hookType or "") .. ":" .. tostring(cmd) .. ":" .. hs.inspect(args)
	if self._timers[timerKey] then
		logger.df("Canceling existing timer for key: %s", timerKey)
		self._timers[timerKey]:stop()
		self._timers[timerKey] = nil
	end

	if immediate or delay <= 0 then
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
		logger.df("Canceling timer for key: %s", key)
		timer:stop()
	end
	self._timers = {}
	for key, timer in pairs(self._watchdogTimers) do
		logger.df("Canceling watchdog timer for key: %s", key)
		timer:stop()
	end
	self._watchdogTimers = {}
end

local function hasElements(t) return t and #t > 0 end

function obj:_executeCmd(item, extraArgs, hookType, immediate)
	local args
	if hasElements(item.args) then
		if hasElements(extraArgs) then
			args = { table.unpack(item.args), table.unpack(extraArgs) }
		else
			args = item.args
		end
	else
		args = extraArgs or {}
	end
	self:_executeAfter(item.cmd, args, item.delay, hookType, immediate)
end

function obj:_cmdAdd(hookType, cmd, delay)
	if delay == nil then delay = 0 end
	logger.df("Adding to %s: %s; delay: %d", hookType, hs.inspect(cmd), delay)
	local realCmd = cmd[1]
	local cmdArgs = { table.unpack(cmd, 2) }
	table.insert(self.hooks[hookType], { cmd = realCmd, args = cmdArgs, delay = delay })
	return self
end

--- MacWatcher:whenResume(cmd[, delay]) -> MacWatcher
--- Method
--- Register a command to run after the system resumes from sleep or unlocks.
---
--- Parameters:
---  * cmd - A table where the first element is the executable path and remaining elements are arguments
---  * delay - (optional) Seconds to wait before executing; default 0
---
--- Returns:
---  * The MacWatcher object, for method chaining
function obj:whenResume(cmd, delay) return self:_cmdAdd(RESUME, cmd, delay) end

--- MacWatcher:whenSuspend(cmd[, delay]) -> MacWatcher
--- Method
--- Register a command to run before the system sleeps or locks.
---
--- Parameters:
---  * cmd - A table where the first element is the executable path and remaining elements are arguments
---  * delay - (optional) Seconds to wait before executing; default 0
---
--- Returns:
---  * The MacWatcher object, for method chaining
function obj:whenSuspend(cmd, delay) return self:_cmdAdd(SUSPEND, cmd, delay) end

--- MacWatcher:onWifiChange(cmd[, delay]) -> MacWatcher
--- Method
--- Register a command to run when the WiFi network changes.
--- The current SSID is appended as an extra argument to the command.
---
--- Parameters:
---  * cmd - A table where the first element is the executable path and remaining elements are arguments
---  * delay - (optional) Seconds to wait before executing; default 0
---
--- Returns:
---  * The MacWatcher object, for method chaining
function obj:onWifiChange(cmd, delay) return self:_cmdAdd(WIFI, cmd, delay) end

--- MacWatcher:whenStop(cmd) -> MacWatcher
--- Method
--- Register a command to run synchronously when stop() is called.
--- Useful for teardown scripts that must complete before the process exits.
---
--- Parameters:
---  * cmd - A table where the first element is the executable path and remaining elements are arguments
---
--- Returns:
---  * The MacWatcher object, for method chaining
function obj:whenStop(cmd) return self:_cmdAdd(STOP, cmd) end

local function tablesEqual(t1, t2)
	if t1 == t2 then return true end
	if type(t1) ~= "table" or type(t2) ~= "table" then return false end
	if #t1 ~= #t2 then return false end
	local keys1 = {}
	for k, v in pairs(t1) do
		if type(v) == "table" then return false end
		if t2[k] ~= v then return false end
		keys1[k] = true
	end
	for k in pairs(t2) do
		if not keys1[k] then return false end
	end
	return true
end

function obj:_execHooks(hookType, args, force, immediate)
	local currentTime = hs.timer.secondsSinceEpoch()
	local state = self._cooldownState[hookType]
	if not force and state and tablesEqual(args, state.args) then
		local last = currentTime - state.time
		if last < self.cooldown then
			logger.df(
				"Hooks for %s with args %s skipped due to cooldown: last run %f seconds ago < %f",
				hookType,
				hs.inspect(args),
				last,
				self.cooldown
			)
			return
		end
	else
		logger.df("Resetting hooks cooldown for %s with args %s", hookType, hs.inspect(args))
	end
	self._cooldownState[hookType] = { args = args, time = currentTime }
	logger.df("Executing hooks from %s", hookType)
	hs.fnutils.each(self.hooks[hookType], function(item) self:_executeCmd(item, args, hookType, immediate) end)
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
	elseif event ~= hs.caffeinate.watcher.systemDidWake then
		logger.df("Unsupported caffeinate event '%s'", event)
	end
end

function obj:_ssidChangedCallback()
	local currentSSID = hs.wifi.currentNetwork() or ""
	logger.f("Executing WiFi hooks for SSID '%s'", currentSSID)
	self:_execHooks(WIFI, { currentSSID })
end

--- MacWatcher:start()
--- Method
--- Start monitoring system events.
--- Also immediately fires resume hooks and evaluates the current WiFi state.
function obj:start()
	logger.f("Starting %s v%s", self.name, self.version)
	logger.f(
		"Registered hooks: resume=%d, suspend=%d, wifi=%d, stop=%d",
		#self.hooks[RESUME],
		#self.hooks[SUSPEND],
		#self.hooks[WIFI],
		#self.hooks[STOP]
	)
	if self.suspendWatcher then self.suspendWatcher:stop() end
	local suspendOk, suspendWatcherOrErr =
		pcall(hs.caffeinate.watcher.new, hs.fnutils.partial(self._caffeinateWatcherCallback, self))
	if suspendOk then
		self.suspendWatcher = suspendWatcherOrErr
		self.suspendWatcher:start()
	else
		logger.w("Failed to create caffeinate watcher: " .. tostring(suspendWatcherOrErr))
		self.suspendWatcher = nil
	end
	if self.wifiWatcher then self.wifiWatcher:stop() end
	local wifiOk, wifiWatcherOrErr = pcall(hs.wifi.watcher.new, hs.fnutils.partial(self._ssidChangedCallback, self))
	if wifiOk then
		self.wifiWatcher = wifiWatcherOrErr
		self.wifiWatcher:start()
	else
		logger.w("Failed to create wifi watcher: " .. tostring(wifiWatcherOrErr))
		self.wifiWatcher = nil
	end
	self:_execHooks(RESUME)
	self:_ssidChangedCallback()
end

--- MacWatcher:stop()
--- Method
--- Stop all monitoring, cancel pending timers, fire suspend hooks synchronously,
--- then run any whenStop commands.
function obj:stop()
	logger.f("Stopping %s v%s", self.name, self.version)
	self:_cancelAllTimers()
	if self.suspendWatcher then
		self.suspendWatcher:stop()
		self.suspendWatcher = nil
	end
	if self.wifiWatcher then
		self.wifiWatcher:stop()
		self.wifiWatcher = nil
	end
	-- immediate=true: run delayed whenSuspend hooks synchronously rather than
	-- scheduling them via a timer, since the _cancelAllTimers() call below
	-- would otherwise cancel them before they ever fire.
	self:_execHooks(SUSPEND, nil, true, true)
	self:_cancelAllTimers()
	for _, item in ipairs(self.hooks[STOP]) do
		local parts = { shellQuote(item.cmd) }
		for _, arg in ipairs(item.args) do
			table.insert(parts, shellQuote(arg))
		end
		local fullCmd = table.concat(parts, " ")
		logger.i("Executing stop command: " .. fullCmd)
		local execOk, execErr = pcall(hs.execute, fullCmd, true)
		if not execOk then logger.w("Failed to execute stop command '" .. fullCmd .. "': " .. tostring(execErr)) end
	end
end

return obj
