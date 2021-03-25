local net      = require 'service.net'
local timer    = require 'timer'
local config   = require 'config'
local client   = require 'provider.client'
local nonil    = require 'without-check-nil'
local util     = require 'utility'
local platform = require 'bee.platform'
local proto    = require 'proto.proto'
local lang     = require 'language'
local define   = require 'proto.define'

local tokenPath = (ROOT / 'log' / 'token'):string()
local token = util.loadFile(tokenPath)
if not token then
    token = ('%016X'):format(math.random(0, math.maxinteger))
    util.saveFile(tokenPath, token)
end

log.info('Telemetry Token:', token)

local function getClientName()
    nonil.enable()
    local clientName    = client.info.clientInfo.name
    local clientVersion = client.info.clientInfo.version
    nonil.disable()
    return table.concat({clientName, clientVersion}, ' ')
end

local function send(link, msg)
    link:write(('s4'):pack(msg))
end

local function pushClientInfo(link)
    send(link, string.pack('zzz'
        , 'pulse'
        , token
        , getClientName()
    ))
end

local function pushPlatformInfo(link)
    send(link, string.pack('zzzzz'
        , 'platform'
        , token
        , ('%s %s'):format(platform.OS, platform.Arch)
        , ('%s %s'):format(platform.CRT, platform.CRTVersion)
        , ('%s %s'):format(platform.Compiler, platform.CompilerVersion)
    ))
end

local function pushErrorLog(link)
    if not log.firstError then
        return
    end
    local err = log.firstError
    log.firstError = nil
    send(link, string.pack('zzzz'
        , 'error'
        , token
        , getClientName()
        , ('%q'):format(err)
    ))
end

timer.wait(5, function ()
    timer.loop(300, function ()
        if not config.config.telemetry.enable then
            return
        end
        local suc, link = pcall(net.connect, 'tcp', 'moe-loli.love', 11577)
        if not suc then
            suc, link = pcall(net.connect, 'tcp', '119.45.194.183', 11577)
        end
        if not suc or not link then
            return
        end
        function link:on_connect()
            pushClientInfo(link)
            pushPlatformInfo(link)
            pushErrorLog(link)
            self:close()
        end
    end)()
    timer.loop(1, function ()
        if not config.config.telemetry.enable then
            return
        end
        net.update()
    end)
end)

local m = {}

function m.updateConfig()
    if config.config.telemetry.enable ~= nil then
        return
    end
    if m.hasShowedMessage then
        return
    end
    m.hasShowedMessage = true

    if client.isVSCode() then
        local enableTitle  = lang.script.WINDOW_TELEMETRY_ENABLE
        local disableTitle = lang.script.WINDOW_TELEMETRY_DISABLE
        local item = proto.awaitRequest('window/showMessageRequest', {
            message = lang.script.WINDOW_TELEMETRY_HINT,
            type    = define.MessageType.Info,
            actions = {
                {
                    title = enableTitle,
                },
                {
                    title = disableTitle,
                },
            }
        })
        if not item then
            return
        end
        if item.title == enableTitle then
            proto.notify('$/command', {
                command   = 'lua.config',
                data      = {
                    key    = 'Lua.telemetry.enable',
                    action = 'set',
                    value  = true,
                    global = true,
                }
            })
        elseif item.title == disableTitle then
            proto.notify('$/command', {
                command   = 'lua.config',
                data      = {
                    key    = 'Lua.telemetry.enable',
                    action = 'set',
                    value  = false,
                    global = true,
                }
            })
        end
    else
        proto.notify('window/showMessage', {
            message = lang.script.WINDOW_TELEMETRY_HINT,
            type    = define.MessageType.Info,
        })
    end
end

return m
