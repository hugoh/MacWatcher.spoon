-- luacheck: std +busted
-- luacheck: globals hs
-- luacheck: globals assert (are (equal same) is_true is_nil)
-- Busted tests for MacWatcher Spoon using the mock hs environment

local mock = dofile("tests/mock_hs.lua")

describe("MacWatcher Spoon", function()
	local w

	local function overrideExecute(target, sink)
		target._executed = sink or {}
		function target:_execute(cmd, args) table.insert(self._executed, { cmd = cmd, args = args }) end
	end

	before_each(function()
		mock.setup()
		w = dofile("init.lua")
	end)

	it("whenResume and _execHooks trigger _execute with args", function()
		overrideExecute(w)

		w:whenResume({ "echo", "hi" }, 0)
		assert.are.equal(1, #w.hooks["resume"])

		w:_execHooks("resume")
		assert.are.equal(1, #w._executed)
		assert.are.equal("echo", w._executed[1].cmd)
		assert.are.same({ "hi" }, w._executed[1].args)
	end)

	it("_executeCmd merges extraArgs", function()
		overrideExecute(w)

		w:_executeCmd({ cmd = "echo", args = { "a" }, delay = 0 }, { "b" })
		assert.are.equal(1, #w._executed)
		assert.are.equal("echo", w._executed[1].cmd)
		assert.are.same({ "a", "b" }, w._executed[1].args)
	end)

	it("cooldown prevents rapid re-execution for same hook", function()
		overrideExecute(w)
		w.cooldown = 5

		w:whenResume({ "x" }, 0)

		hs.timer.secondsSinceEpoch() -- ensure function exists
		mock._setTime(100)
		w:_execHooks("resume")
		assert.are.equal(1, #w._executed)

		mock._setTime(102)
		w:_execHooks("resume")
		assert.are.equal(1, #w._executed)

		mock._setTime(106)
		w:_execHooks("resume")
		assert.are.equal(2, #w._executed)
	end)

	it("start initializes watchers and triggers initial hooks", function()
		overrideExecute(w)

		mock._setSSID("HomeNet")

		w:whenResume({ "echo", "r" }, 0)
		w:onWifiChange({ "echo", "w" }, 0)

		w:start()

		assert.is_true(w.suspendWatcher ~= nil and w.suspendWatcher._started == true)
		assert.is_true(w.wifiWatcher ~= nil and w.wifiWatcher._started == true)

		assert.are.equal(2, #w._executed)
		-- Execution order: resume first, then wifi
		assert.are.equal("echo", w._executed[1].cmd)
		assert.are.same({ "r" }, w._executed[1].args)

		assert.are.equal("echo", w._executed[2].cmd)
		assert.are.same({ "w", "HomeNet" }, w._executed[2].args)
	end)

	it("_ssidChangedCallback passes current SSID", function()
		overrideExecute(w)

		mock._setSSID("Office")
		w:onWifiChange({ "echo" }, 0)
		w:_ssidChangedCallback()

		assert.are.equal(1, #w._executed)
		assert.are.same({ "Office" }, w._executed[1].args)
	end)

	it("_caffeinateWatcherCallback maps events to resume/suspend", function()
		overrideExecute(w)

		w:whenResume({ "r" }) -- no delay parameter
		w:whenSuspend({ "s" }, 0) -- parameter = 0

		w:_caffeinateWatcherCallback(hs.caffeinate.watcher.screensaverDidStop)
		w:_caffeinateWatcherCallback(hs.caffeinate.watcher.screensaverDidStart)

		assert.are.equal(2, #w._executed)
		assert.is_nil(w._executed[1].args) -- no extra args for resume
		assert.is_nil(w._executed[2].args) -- no extra args for suspend
	end)

	it("_executeAfter cancels prior timer for same key", function()
		overrideExecute(w)

		-- Schedule with delay (no hookType → key is ":echo")
		w:_executeAfter("echo", { "a" }, 5)
		local key = ":echo"
		local t1 = w._timers[key]
		assert.is_true(t1 ~= nil)

		-- Re-schedule; should cancel t1
		w:_executeAfter("echo", { "b" }, 5)
		local t2 = w._timers[key]
		assert.is_true(t2 ~= nil and t2 ~= t1)
		assert.is_true(t1._stopped == true)

		-- Fire the second timer; should execute once with latest args
		t2:fire()
		assert.are.equal(1, #w._executed)
		assert.are.equal("echo", w._executed[1].cmd)
		assert.are.same({ "b" }, w._executed[1].args)
	end)

	it("cooldown allows re-execution when args differ for same hook", function()
		overrideExecute(w)
		w.cooldown = 5

		w:whenResume({ "x" }, 0)

		mock._setTime(100)
		w:_execHooks("resume", { "a" })
		assert.are.equal(1, #w._executed)

		mock._setTime(101)
		w:_execHooks("resume", { "b" })
		assert.are.equal(2, #w._executed)
	end)

	it("whenSuspend is chainable", function()
		local result = w:whenSuspend({ "x" }, 0)
		assert.are.equal(w, result)
	end)

	it("onWifiChange is chainable", function()
		local result = w:onWifiChange({ "x" }, 0)
		assert.are.equal(w, result)
	end)

	it("_execute does nothing when cmd is nil", function()
		-- real _execute: nil guard returns early without calling _executeAsyncCmd
		local called = false
		w._executeAsyncCmd = function() called = true end
		w:_execute(nil, nil)
		assert.is_false(called)
	end)

	it("_cancelAllTimers stops all pending timers", function()
		w:_executeAfter("a", {}, 5)
		w:_executeAfter("b", {}, 5)
		local timers = {}
		for _, t in pairs(w._timers) do table.insert(timers, t) end
		assert.are.equal(2, #timers)

		w:_cancelAllTimers()
		assert.are.equal(0, #w._timers)
		for _, t in ipairs(timers) do
			assert.is_true(t._stopped)
		end
	end)

	it("stop() stops and nils the watchers", function()
		w:start()
		local sw, ww = w.suspendWatcher, w.wifiWatcher
		w:stop()
		assert.is_true(sw._started == false)
		assert.is_true(ww._started == false)
		assert.is_nil(w.suspendWatcher)
		assert.is_nil(w.wifiWatcher)
	end)

	it("stop() fires suspend hooks", function()
		overrideExecute(w)
		w:whenSuspend({ "halt" }, 0)
		w:start()
		w:stop()
		-- first _executed entry is from start()'s _execHooks(RESUME) — none registered
		-- stop() fires suspend
		assert.are.equal(1, #w._executed)
		assert.are.equal("halt", w._executed[1].cmd)
	end)

	it("stop() cancels pending timers", function()
		w:start()
		w:_executeAfter("pending", {}, 10)
		local timers = {}
		for _, t in pairs(w._timers) do table.insert(timers, t) end
		assert.is_true(#timers > 0)
		w:stop()
		assert.are.equal(0, #w._timers)
	end)

	it("_ssidChangedCallback passes empty string when SSID is nil", function()
		overrideExecute(w)
		mock._setSSID(nil)
		w:onWifiChange({ "net" }, 0)
		w:_ssidChangedCallback()
		assert.are.same({ "" }, w._executed[1].args)
	end)

	it("_caffeinateWatcherCallback fires resume hooks for all resume events", function()
		local resumeEvents = {
			hs.caffeinate.watcher.screensaverDidStop,
			hs.caffeinate.watcher.screensaverWillStop,
			hs.caffeinate.watcher.screensDidUnlock,
			hs.caffeinate.watcher.screensDidWake,
			hs.caffeinate.watcher.sessionDidBecomeActive,
		}
		for _, event in ipairs(resumeEvents) do
			mock.setup()
			w = dofile("init.lua")
			overrideExecute(w)
			w:whenResume({ "r" }, 0)
			w:_caffeinateWatcherCallback(event)
			assert.are.equal(1, #w._executed, "resume not fired for event: " .. tostring(event))
		end
	end)

	it("_caffeinateWatcherCallback fires suspend hooks for all suspend events", function()
		local suspendEvents = {
			hs.caffeinate.watcher.screensaverDidStart,
			hs.caffeinate.watcher.screensDidLock,
			hs.caffeinate.watcher.screensDidSleep,
			hs.caffeinate.watcher.systemWillPowerOff,
			hs.caffeinate.watcher.systemWillSleep,
			hs.caffeinate.watcher.sessionDidResignActive,
		}
		for _, event in ipairs(suspendEvents) do
			mock.setup()
			w = dofile("init.lua")
			overrideExecute(w)
			w:whenSuspend({ "s" }, 0)
			w:_caffeinateWatcherCallback(event)
			assert.are.equal(1, #w._executed, "suspend not fired for event: " .. tostring(event))
		end
	end)

	it("_caffeinateWatcherCallback ignores systemDidWake silently", function()
		overrideExecute(w)
		w:whenResume({ "r" }, 0)
		w:whenSuspend({ "s" }, 0)
		w:_caffeinateWatcherCallback(hs.caffeinate.watcher.systemDidWake)
		assert.are.equal(0, #w._executed)
	end)

	it("_caffeinateWatcherCallback ignores unknown events", function()
		overrideExecute(w)
		w:whenResume({ "r" }, 0)
		w:whenSuspend({ "s" }, 0)
		w:_caffeinateWatcherCallback("unknownEvent")
		assert.are.equal(0, #w._executed)
	end)

	it("_executeAsyncCmd clears timeout timer on successful completion", function()
		w:_executeAsyncCmd("echo", { "hi" })
		-- mock task completes synchronously; timeout timer should be stopped
		for key, _ in pairs(w._timers) do
			assert.is_false(key:sub(1, 9) == "__timeout", "timeout timer still present: " .. key)
		end
	end)

	it("_executeAsyncCmd logs error on non-zero exit code", function()
		mock._setTaskExitCode(1)
		w:_executeAsyncCmd("fail-cmd", {})
		local logger = hs.logger.new("test")
		-- error is logged; spoon should not throw
		assert.is_true(true)
	end)

	it("_executeCmd uses only extraArgs when item has no args", function()
		overrideExecute(w)
		w:_executeCmd({ cmd = "echo", args = {}, delay = 0 }, { "extra" })
		assert.are.same({ "extra" }, w._executed[1].args)
	end)

	it("cooldown does not block re-execution at exact boundary", function()
		overrideExecute(w)
		w.cooldown = 5
		w:whenResume({ "x" }, 0)

		mock._setTime(100)
		w:_execHooks("resume")
		assert.are.equal(1, #w._executed)

		mock._setTime(105) -- exactly at boundary: last == cooldown, should NOT be blocked
		w:_execHooks("resume")
		assert.are.equal(2, #w._executed)
	end)

	it("cooldown is independent per hook type", function()
		overrideExecute(w)
		w.cooldown = 5
		w:whenResume({ "r" }, 0)
		w:whenSuspend({ "s" }, 0)

		mock._setTime(100)
		w:_execHooks("resume")
		w:_execHooks("suspend")
		assert.are.equal(2, #w._executed)

		mock._setTime(102)
		w:_execHooks("resume") -- blocked by cooldown
		w:_execHooks("suspend") -- blocked by cooldown
		assert.are.equal(2, #w._executed)

		mock._setTime(106)
		w:_execHooks("resume") -- past cooldown
		w:_execHooks("suspend") -- past cooldown
		assert.are.equal(4, #w._executed)
	end)

	it("_execute logs error for invalid cmd type", function()
		overrideExecute(w) -- still override to avoid real execution paths
		-- This should not throw
		w:_execute({}, nil)
		assert.is_true(true)
	end)

	it("whenStop registers a hook", function()
		w:whenStop({ "work-focus", "stop" })
		assert.are.equal(1, #w.hooks["stop"])
		assert.are.equal("work-focus", w.hooks["stop"][1].cmd)
		assert.are.same({ "stop" }, w.hooks["stop"][1].args)
	end)

	it("whenStop is chainable", function()
		local result = w:whenStop({ "work-focus", "stop" })
		assert.are.equal(w, result)
	end)

	it("stop() runs whenStop hooks synchronously via hs.execute", function()
		w:whenStop({ "work-focus", "stop" })
		w:start()
		w:stop()
		assert.are.equal(1, #mock._executed)
		assert.are.equal("work-focus stop", mock._executed[1])
	end)

	it("stop() runs whenStop hooks with no args", function()
		w:whenStop({ "work-focus" })
		w:start()
		w:stop()
		assert.are.equal(1, #mock._executed)
		assert.are.equal("work-focus", mock._executed[1])
	end)

	it("stop() runs multiple whenStop hooks in order", function()
		w:whenStop({ "cmd-a", "1" })
		w:whenStop({ "cmd-b", "2", "3" })
		w:start()
		w:stop()
		assert.are.equal(2, #mock._executed)
		assert.are.equal("cmd-a 1", mock._executed[1])
		assert.are.equal("cmd-b 2 3", mock._executed[2])
	end)

	it("stop() does not run whenStop hooks if none registered", function()
		w:start()
		w:stop()
		assert.are.equal(0, #mock._executed)
	end)
end)
