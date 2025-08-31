-- Simple test runner for the MacWatcher Spoon tests

local tests = {}
_G.test = function(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local function green(s) return "\27[32m" .. s .. "\27[0m" end
local function red(s) return "\27[31m" .. s .. "\27[0m" end
local function yellow(s) return "\27[33m" .. s .. "\27[0m" end

local total, passed, failed = 0, 0, 0

-- Load test files (register tests)
dofile("tests/test_macwatcher.lua")

-- Execute
for _, t in ipairs(tests) do
  total = total + 1
  local ok, err = xpcall(t.fn, debug.traceback)
  if ok then
    passed = passed + 1
    io.write(green("PASS "), t.name, "\n")
  else
    failed = failed + 1
    io.write(red("FAIL "), t.name, "\n", yellow(err), "\n")
  end
end

print(string.format("\nSummary: %d total, %d passed, %d failed", total, passed, failed))
os.exit(failed == 0 and 0 or 1)
