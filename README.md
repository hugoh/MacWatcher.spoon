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

Ensure you have [Hammerspoon](https://www.hammerspoon.org) installed, then choose a method:

### Release zip (recommended)

1. Download `MacWatcher.spoon.zip` from the [latest release](https://github.com/hugoh/MacWatcher.spoon/releases/latest)
2. Unzip — this produces a `MacWatcher.spoon` folder
3. Move it to `~/.hammerspoon/Spoons/`
4. Reload Hammerspoon (menu bar icon → Reload Config, or run `hs.reload()` in the console)

### SpoonInstall (if you already use it)

```lua
spoon.SpoonInstall:installSpoonFromZip(
  "https://github.com/hugoh/MacWatcher.spoon/releases/latest/download/MacWatcher.spoon.zip"
)
```

### Clone from git (for development or latest changes)

```bash
cd ~/.hammerspoon/Spoons
git clone https://github.com/hugoh/MacWatcher.spoon.git
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
