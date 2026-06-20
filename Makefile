.PHONY: test

test:
	@echo "Running Lua unit tests with busted"
	busted -p 'test_.*%.lua' tests
