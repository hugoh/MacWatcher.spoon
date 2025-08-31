# Makefile to run Lua unit tests for the MacWatcher Spoon using busted.
# Installs busted locally into .rocks if not already available.

.PHONY: test deps clean-deps

# Allow overriding the Lua interpreter: `make test LUA=luajit`
LUA ?= lua

# Local LuaRocks tree
ROCKS_DIR ?= .rocks
BUSTED := $(ROCKS_DIR)/bin/busted

# Ensure Lua can find project-local modules (e.g., tests.mock_hs)
LUA_PATH := $(CURDIR)/?.lua;$(CURDIR)/?/init.lua;;
LUA_CPATH := ;;

test: deps
	@echo "Running Lua unit tests with busted"
	LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(BUSTED) -p 'test_.*%.lua' tests

deps: $(BUSTED)

$(BUSTED):
	@echo "Ensuring busted is installed locally in $(ROCKS_DIR)"
	@if ! command -v luarocks >/dev/null 2>&1; then echo "luarocks not found. Install it with: brew install luarocks"; exit 1; fi
	luarocks --tree=$(ROCKS_DIR) install busted

# Optional: remove local rock tree
clean-deps:
	@rm -rf $(ROCKS_DIR)
