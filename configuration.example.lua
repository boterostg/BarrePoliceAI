--[[
                       _   _        _                    _
       _ __ ___   __ _| |_| |_ __ _| |_ __ _        __ _(_)
      | '_ ` _ \ / _` | __| __/ _` | __/ _` |_____ / _` | |
      | | | | | | (_| | |_| || (_| | || (_| |_____| (_| | |
      |_| |_| |_|\__,_|\__|\__\__,_|\__\__,_|      \__,_|_|

      Configuration file for mattata-ai v1.0.0

      Copyright 2017 Matthew Hesketh <wrxck0@gmail.com>
      This code is licensed under the MIT. See LICENSE for details.

      Each value in an array should be comma separated, with the exception of the last value!
      Make sure you always update your configuration file after pulling changes from GitHub!

]]

return { -- Rename this file to configuration.lua for the bot to work!
    ['bot_token'] = '', -- In order for the bot to actually work, you
    -- MUST insert the Telegram bot API token you received from @BotFather.
    ['debug'] = false, -- Turn this on to print EVEN MORE information to the terminal.
    ['redis'] = { -- Configurable options for connecting the bot to redis. Do NOT modify
    -- these settings if you don't know what you're doing!
        ['host'] = '127.0.0.1',
        ['port'] = 6379,
        ['password'] = nil,
        ['db'] = 2
    },
}

-- End of configuration, you're good to go.
-- Use ./launch.sh to start the bot.
-- If you can't execute the script, try running: chmod +x launch.sh
