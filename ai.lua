--[[
                       _   _        _                    _
       _ __ ___   __ _| |_| |_ __ _| |_ __ _        __ _(_)
      | '_ ` _ \ / _` | __| __/ _` | __/ _` |_____ / _` | |
      | | | | | | (_| | |_| || (_| | || (_| |_____| (_| | |
      |_| |_| |_|\__,_|\__|\__\__,_|\__\__,_|      \__,_|_|

      v1.0.0

      Copyright (c) 2017 Matthew Hesketh <wrxck0@gmail.com>
      See LICENSE for details

      mattata-ai is a basic AI implementation, hooked to Cleverbot, written in Lua.

]]

local ai = {}
local configuration = require('configuration')
local api = require('telegram-bot-lua.core').configure(configuration.bot_token)
local tools = require('telegram-bot-lua.tools')
local redis = dofile('libs/redis.lua')
local http = require('socket.http')
local url = require('socket.url')
local ltn12 = require('ltn12')
local digest = require('openssl.digest')

function ai:init()
    self.info = api.info -- Set the bot's information to the object fetched from the Telegram bot API.
    print('Connected to the Telegram bot API!')
    print('\n\tUsername: @' .. self.info.username .. '\n\tName: ' .. self.info.name .. '\n\tID: ' .. self.info.id .. '\n')
    self.version = 'v1.0.0'
    self.last_update = self.last_update or 0 -- If there is no last update known, make it 0 so the bot doesn't encounter any
    -- problems when it tries to add the necessary increment.
    return true
end

function ai:run(configuration, token)
-- mattata-ai's main long-polling function which repeatedly checks the Telegram bot API for updates.
-- The objects received in the updates are then further processed through object-specific functions.
    token = token or configuration.bot_token
    assert(token, 'You need to enter your Telegram bot API token in configuration.lua, or pass it as the second argument when using the ai:run() function!')
    local is_running = ai.init(self) -- Initialise the bot.
    while is_running do -- Perform the main loop whilst the bot is running.
        -- Check the Telegram bot API for updates.
        local success = api.get_updates(1, self.last_update + 1, 20, nil, false)
        if success and success.result then
            for k, v in ipairs(success.result) do
                self.last_update = v.update_id
                if v.message then
                    if v.message.reply_to_message then
                        v.message.reply = v.message.reply_to_message -- Make the `update.message.reply_to_message`
                        -- object `update.message.reply` to make any future handling easier.
                        v.message.reply_to_message = nil -- Delete the old value by setting its value to nil.
                    end
                    ai.on_message(self, v.message)
                    if configuration.debug then
                        print(
                            string.format(
                                '%s[36m[Update #%s] Message from %s to %s%s[0m',
                                string.char(27),
                                v.update_id,
                                v.message.from.id,
                                v.message.chat.id,
                                string.char(27)
                            )
                        )
                    end
                end
            end
        else
            print(
                string.format(
                    '%s[31m[Error] There was an error retrieving updates from the Telegram bot API!%s[0m',
                    string.char(27),
                    string.char(27)
                )
            )
        end
    end
    print(self.info.first_name .. ' is shutting down...')
end

function ai.on_message(self, message)
    if not message or not message.chat or not message.text then
        return false
    elseif message.date < os.time() - 10 then
        return false
    elseif self.info.name:match(' ') then
        self.info.name = self.info.name:match('^(.-) ')
    end
    redis:incr('ai:received_messages')
    self.info.name = self.info.name:lower()
    message.text = message.text:lower()
    if message.text:gsub(' ', '') == self.info.name then
        return false
    elseif message.chat.type ~= 'private' and not message.text:match(self.info.name) and not message.text:lower():match("bot") then
        if not message.reply or not message.reply.from or message.reply.from.id ~= self.info.id then
            return false
        end
    end
    message.text = message.text:gsub(self.info.name, '')
    api.send_chat_action(message.chat.id)
    local output
    if message.reply and message.reply.text and message.reply.text:len() > 0 and message.reply.from and message.reply.from.id == self.info.id then
        output = ai.process(message.text, message.reply.text)
    else
        output = ai.process(message.text)
    end
    if not output then
        if message.reply and message.reply.text and message.reply.text:len() > 0 and message.reply.from and message.reply.from.id == self.info.id then
            output = ai.process(message.text, message.reply.text, true)
        else
            output = ai.process(message.text)
        end
    end
    return ai.send_reply(message, output and '<pre>' .. tools.escape_html(output) .. '</pre>' or '<pre>' .. tools.escape_html(ai.offline()) .. '</pre>', 'html')
end

function ai.get_me(token)
    token = token or configuration.bot_token
    return ai.request(string.format('https://api.telegram.org/bot%s/getMe', token))
end

-- A variant of `ai.send_message()`, optimised for sending a message as a reply.
function ai.send_reply(message, text, parse_mode, disable_web_page_preview, reply_markup, token)
    local success = api.send_message(
        message,
        text,
        parse_mode,
        disable_web_page_preview,
        false,
        message.message_id,
        reply_markup
        or '{"remove_keyboard":true}',
        token
    )
    if not success
    then
        success = api.send_message(
            message,
            text,
            parse_mode,
            disable_web_page_preview,
            false,
            message.message_id,
            reply_markup,
            token
        )
    end
    redis:incr('ai:sent_replies')
    return success
end

function ai:exception(err, message, log_chat)
    local output = string.format(
        '[%s]\n%s: %s\n%s\n',
        os.date('%X'),
        self.info.username,
        tools.escape_html(err)
        or '',
        tools.escape_html(message)
    )
    if log_chat then
        return ai.send_message(log_chat, '<pre>' .. output .. '</pre>', 'html')
    end
    return true
end

function ai.num_to_hex(int)
    local hex = '0123456789abcdef'
    local s = ''
    while int > 0 do
        local mod = math.fmod(int, 16)
        s = hex:sub(mod + 1, mod +1 ) .. s
        int = math.floor(int / 16)
    end
    if s == '' then
        s = '0'
    end
    return s
end

function ai.str_to_hex(str)
    local s = ''
    while #str > 0 do
        local h = ai.num_to_hex(str:byte(1, 1))
        if #h < 2 then
            h = '0' .. h
        end
        s = s .. h
        str = str:sub(2)
    end
    return s
end

function ai.unescape(str)
    if not str then
        return false
    end
    str = str:gsub('%%(%x%x)', function(x)
        return tostring(tonumber(x, 16)):char()
    end)
    return str
end

function ai.cookie()
    local cookie = {}
    local _, res, headers = http.request{
        ['url'] = 'http://www.cleverbot.com/',
        ['method'] = 'GET'
    }
    if res ~= 200 then
        return false
    end
    local set = headers['set-cookie']
    local k, v = set:match('([^%s;=]+)=?([^%s;]*)')
    cookie[k] = v
    return cookie
end

function ai.talk(message, reply)
    if not message then
        return false
    end
    return ai.cleverbot(message, reply)
end

function ai.cleverbot(message, reply)
    local cookie = ai.cookie()
    if not cookie then
        return false
    end
    for k, v in pairs(cookie) do
        cookie[#cookie + 1] = k .. '=' .. v
    end
    local query = 'stimulus=' .. url.escape(message)
    if reply then
        query = query .. '&vText2=' .. url.escape(reply)
    end
    query = query .. '&cb_settings_scripting=no&islearning=1&icognoid=wsf&icognocheck='
    local sub = query:sub(8, 33)
    local digested = digest.new('md5'):final(sub)
    query = query .. ai.str_to_hex(digested)
    local _, res, headers = http.request(
        {
            ['url'] = 'http://www.cleverbot.com/webservicemin?uc=UseOfficialCleverbotAPI&',
            ['method'] = 'POST',
            ['headers'] = {
                ['Host'] = 'www.cleverbot.com',
                ['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0',
                ['Accept'] = '*/*',
                ['Accept-Language'] = 'en-US,en;q=0.5',
                ['Accept-Encoding'] = 'gzip, deflate',
                ['Referrer'] = 'http://www.cleverbot.com/',
                ['Content-Length'] = query:len(),
                ['Content-Type'] = 'text/plain;charset=UTF-8',
                ['Cookie'] = table.concat(cookie, ';'),
                ['DNT'] = '1',
                ['Connection'] = 'keep-alive'
            },
            ['source'] = ltn12.source.string(query)
        }
    )
    if res ~= 200 or not headers.cboutput then
        return false
    end
    local output = ai.unescape(headers.cboutput)
    if not output then
        return false
    end
    return output
end

function ai.process(message, reply)
    if not message then
        return ai.unsure()
    end
    local original_message = message
    message = message:lower()
    if message:match('^hi%s*') or message:match('^hello%s*') or message:match('^howdy%s*') or message:match('^hi.?$') or message:match('^hello.?$') or message:match('^howdy.?$') then
        return ai.greeting()
    elseif message:match('^bye%s*') or message:match('^good[%-%s]?bye%s*') or message:match('^bye$') or message:match('^good[%-%s]?bye$') then
        return ai.farewell()
    elseif message:match('%s*y?o?ur%s*name%s*') or message:match('^what%s*is%s*y?o?ur%s*name') then
        return 'My name is ai, what\'s yours?'
    elseif message:match('^do y?o?u[%s.]*') then
        return ai.choice(message)
    elseif message:match('^how%s*a?re?%s*y?o?u.?') or message:match('.?how%s*a?re?%s*y?o?u%s*') or message:match('.?how%s*a?re?%s*y?o?u.?$') or message:match('^a?re?%s*y?o?u%s*oka?y?.?$') or message:match('%s*a?re?%s*y?o?u%s*oka?y?.?$') then
        return ai.feeling()
    else
        return ai.talk(original_message, reply or false)
    end
end

function ai.greeting()
    local greetings = {
        'Hello!',
        'Hi.',
        'How are you?',
        'What\'s up?',
        'Are you okay?',
        'How\'s it going?',
        'What\'s your name?',
        'What are you up to?',
        'Hello.',
        'Hey!',
        'Hey.',
        'Howdy!',
        'Howdy.',
        'Hello there!',
        'Hello there.'
    }
    return greetings[math.random(#greetings)]
end

function ai.farewell()
    local farewells = {
        'Goodbye!',
        'Bye.',
        'I\'ll speak to you later, yeah?',
        'See ya!',
        'Oh, bye then.',
        'Bye bye.',
        'BUH-BYE!',
        'Aw. See ya.'
    }
    return farewells[math.random(#farewells)]
end

function ai.unsure()
    local unsure = {
        'What?',
        'I really don\'t understand.',
        'What are you trying to say?',
        'Huh?',
        'Um..?',
        'Excuse me?',
        'What does that mean?'
    }
    return unsure[math.random(#unsure)]
end

function ai.feeling()
    local feelings = {
        'I am good thank you!',
        'I am well.',
        'Good, how about you?',
        'Very well thank you; you?',
        'Never better!',
        'I feel great!'
    }
    return feelings[math.random(#feelings)]
end

function ai.choice(message)
    local generic_choices = {
        'I do!',
        'I do not.',
        'Nah, of course not!',
        'Why would I?',
        'Um...',
        'I sure do!',
        'Yes, do you?',
        'Nope!',
        'Yeah!'
    }
    local personal_choices = {
        'I love you!',
        'I\'m sorry, but I don\'t really like you!',
        'I really like you.',
        'I\'m crazy about you!'
    }
    if message:match('%s*me.?$')
    then
        return personal_choices[math.random(#personal_choices)]
    end
    return generic_choices[math.random(#generic_choices)]
end

function ai.offline()
    local responses = {
        'I don\'t feel like talking right now!',
        'I don\'t want to talk at the moment.',
        'Can we talk later?',
        'I\'m not in the mood right now...',
        'Leave me alone!',
        'Please can I have some time to myself?',
        'I really don\'t want to talk to anyone right now!',
        'Please leave me in peace.',
        'I don\'t wanna talk right now, I hope you understand.'
    }
    return responses[math.random(#responses)]
end

return ai
