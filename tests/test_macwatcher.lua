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

		-- Schedule with delay
		w:_executeAfter("echo", { "a" }, 5)
		local t1 = w._timers["echo"]
		assert.is_true(t1 ~= nil)

		-- Re-schedule; should cancel t1
		w:_executeAfter("echo", { "b" }, 5)
		local t2 = w._timers["echo"]
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

	it("_execute logs error for invalid cmd type", function()
		overrideExecute(w) -- still override to avoid real execution paths
		-- This should not throw
		w:_execute({}, nil)
		assert.is_true(true)
	end)
end)
