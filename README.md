# MacWatcher Spoon

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Hammerspoon Spoon](https://img.shields.io/badge/Hammerspoon-Spoon-FFA500.svg)](https://www.hammerspoon.org/docs/index.html)

A Hammerspoon Spoon that executes commands on system events like wake, sleep, and WiFi changes.

## Features

- Execute commands/callbacks when resuming from sleep/unlock
- Trigger actions when system goes to sleep/locks
- Monitor WiFi network changes
- Configurable execution delays and cooldown periods
- Async command execution with timeouts

## Installation

1. Ensure you have [Hammerspoon](https://www.hammerspoon.org) installed
2. Clone this repository to your Spoons directory:
```bash
cd ~/.hammerspoon/Spoons
git clone https://github.com/yourusername/MacWatcher.spoon.git
```

## Configuration

```lua
-- Load and configure the Spoon
local macWatcher = hs.loadSpoon("MacWatcher")

-- Configure default settings (optional)
macWatcher.cooldown = 5          -- Minimum seconds between hook executions
macWatcher.taskTimeout = 30      -- Timeout for command execution

-- Set up event hooks
macWatcher
  :whenResume({"/bin/echo", "System resumed"}, 2)  -- Run 2 seconds after a session is resumed
  :whenSuspend({"/usr/bin/true"}, 0)               -- Run immediately before sleep
  :onWifiChange({"/usr/local/bin/ssid_handler"}, 1) -- Run 1s after WiFi change (note: SSID passed as an argument to the command)
  
-- Start monitoring
macWatcher:start()
```

## Methods

- `whenResume({ command, ... }, delay)` - Run command array after wake/unlock
- `whenSuspend({ command, ... }, delay)` - Run command array before sleep/lock
- `onWifiChange({ command, ... }, delay)` - Run command array when WiFi network changes (SSID passed as an additional argument)
- `start()` - Begin monitoring system events
- `stop()` - Stop all monitoring and timers
