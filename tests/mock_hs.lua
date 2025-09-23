-- Minimal Hammerspoon mock for unit testing MacWatcher Spoon
-- Provides: hs.logger, hs.inspect, hs.fnutils, hs.timer, hs.task,
--           hs.caffeinate.watcher, hs.wifi.watcher, hs.wifi

local M = {}

local function makeLogger(name, levelName)
	local levels = { error = 2, warning = 3, info = 3, debug = 4, verbose = 5 }
	local logger = {
		_name = name or "MockLogger",
		level = levels[(levelName or "info"):lower()] or 3,
		_logs = {},
	}
	local function push(kind, msg) table.insert(logger._logs, { kind = kind, msg = tostring(msg) }) end
	function logger.i(msg, ...) push("i", string.format(tostring(msg), ...)) end
	function logger.d(msg, ...) push("d", string.format(tostring(msg), ...)) end
	function logger.f(msg, ...) push("f", string.format(tostring(msg), ...)) end
	function logger.w(msg, ...) push("w", string.format(tostring(msg), ...)) end
	function logger.e(msg, ...) push("e", string.format(tostring(msg), ...)) end
	function logger.df(fmt, ...) logger.d(string.format(fmt, ...)) end
	function logger.wf(fmt, ...) logger.w(string.format(fmt, ...)) end
	function logger.ef(fmt, ...) logger.e(string.format(fmt, ...)) end
	return logger
end

local function simpleInspect(v, seen)
	seen = seen or {}
	local t = type(v)
	if t ~= "table" then return tostring(v) end
	if seen[v] then return "<recursion>" end
	seen[v] = true
	local parts = {}
	for k, val in pairs(v) do
		table.insert(parts, "[" .. tostring(k) .. "]=" .. simpleInspect(val, seen))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function M.setup()
	local hs = {}

	-- Logger
	hs.logger = { new = makeLogger }

	-- Inspect
	hs.inspect = simpleInspect

	-- fnutils
	hs.fnutils = {}
	function hs.fnutils.each(t, fn)
		for i = 1, #t do
			fn(t[i])
		end
	end
	function hs.fnutils.partial(fn, self)
		return function(...) return fn(self, ...) end
	end

	-- Time/timers
	local now = 0
	local timers = {}
	hs.timer = {}
	function hs.timer.secondsSinceEpoch() return now end
	function M._setTime(t) now = t end
	function M._advance(dt) now = now + (dt or 0) end

	local function makeTimer(cb, delay)
		local obj = { _cb = cb, _delay = delay, _stopped = false, _fired = false }
		function obj:stop() self._stopped = true end
		function obj:fire()
			if self._stopped or self._fired then return end
			self._fired = true
			if self._cb then self._cb() end
		end
		return obj
	end
	function hs.timer.doAfter(delay, cb)
		local t = makeTimer(cb, delay)
		table.insert(timers, t)
		return t
	end
	M._timers = timers

	-- Task
	hs.task = {}
	function hs.task.new(_cmd, completionFn, streamFn, _args)
		local running = false
		local pid = 12345
		local task = {}
		function task.start(_)
			running = true
			-- Simulate some output callbacks then completion
			if streamFn then streamFn(nil, "", "") end
			if completionFn then completionFn(0, "", "") end
			running = false
			return true
		end
		function task.closeInput(_) end
		function task.terminate(_) running = false end
		function task.isRunning(_) return running end
		function task.pid(_) return pid end
		return task
	end

	-- Caffeinate watcher
	hs.caffeinate = { watcher = {} }
	hs.caffeinate.watcher.screensaverDidStop = "screensaverDidStop"
	hs.caffeinate.watcher.screensaverWillStop = "screensaverWillStop"
	hs.caffeinate.watcher.screensDidUnlock = "screensDidUnlock"
	hs.caffeinate.watcher.screensDidWake = "screensDidWake"
	hs.caffeinate.watcher.sessionDidBecomeActive = "sessionDidBecomeActive"
	hs.caffeinate.watcher.screensaverDidStart = "screensaverDidStart"
	hs.caffeinate.watcher.screensDidLock = "screensDidLock"
	hs.caffeinate.watcher.screensDidSleep = "screensDidSleep"
	hs.caffeinate.watcher.systemWillPowerOff = "systemWillPowerOff"
	hs.caffeinate.watcher.systemWillSleep = "systemWillSleep"
	hs.caffeinate.watcher.sessionDidResignActive = "sessionDidResignActive"
	hs.caffeinate.watcher.systemDidWake = "systemDidWake"

	function hs.caffeinate.watcher.new(cb)
		local o = { _cb = cb, _started = false }
		function o:start() self._started = true end
		function o:stop() self._started = false end
		return o
	end

	-- WiFi
	hs.wifi = {}
	local ssid = nil
	function hs.wifi.currentNetwork() return ssid end
	function M._setSSID(s) ssid = s end

	hs.wifi.watcher = {}
	function hs.wifi.watcher.new(cb)
		local o = { _cb = cb, _started = false }
		function o:start() self._started = true end
		function o:stop() self._started = false end
		return o
	end

	-- Expose mock to tests
	M.hs = hs
	_G.hs = hs
	return hs
end

return M
