--[[
Copyright © 2024, Metra of HorizonXI
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of React nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 'AS IS' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL --Metra-- BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

-- Horizon Approved Addon 0457

addon.author  = 'Metra'
addon.name    = 'Metrics'
addon.version = '2026-09-02'

_Globals = { }
_Globals.Initialized = false

SettingsFile = require('settings')
Socket       = require('socket')   -- Needed for millisecond precision on timestamps for attack speed.
Timers       = require('timers')

-- This holds all of the settings for the various Metrics modules.
-- It needs to be initialized after requiring 'settings' because 'settings' contains the definition for the 'T' table modifier.
-- The 'T' table modifier is needed for the settings to save correctly without crashing on initial load.
Metrics = T{ }

require('version')
require('resources._resource')
require('database._database')
require('file')
require('throttling')
require('performance')
require('ashita._ashita')
require('handlers._handler')
require('windows.!manager')
require('columns.!column')
require('modules.config._config')
require('modules.exp._exp')
require('modules.loot._loot')
require('modules.parse._parse')
require('modules.focus._focus')
require('modules.battle log._battle_log')
require('modules.report._report')
require('modules.overview._overview')
require('modules.hub.!hub')
require('modules.debug.!debug')
require('commands')
require('horizon')
require('initialization')

local RENDER_GRACE_SECONDS = 3
local RENDER_RECOVERY_SECONDS = 10
local RENDER_RETRY_DELAYS = { 3, 15, 60 }
local renderDisabled = false
local renderRetryAt = 0
local renderFailureCount = 0
local renderFailureNotified = false
local renderStableSince
local renderErrorPersisted = false
local renderReadyAt = 0
local wasLoggedIn = false
local entityPacketsReady = false
local activePacket
local activePacketHandler

local packetHandlers =
{
    [ H.Packet.ZONE_START      ] = function()
        if not Ashita.Player.IsZoning() then
            Ashita.Player.Zoning(true)
            entityPacketsReady = false
        end
    end,
    [ H.Packet.ZONE_END        ] = function()
        H.ZoningEnd()
        entityPacketsReady = false
        renderReadyAt = Socket.gettime() + RENDER_GRACE_SECONDS
    end,
    [ H.Packet.EXAMPLAR_UPDATE ] = function(packet) XP.OnExemplarUpdate(packet.data) end,
    [ H.Packet.CAPACITY_UPDATE ] = function(packet) XP.OnCapacityUpdate(packet.data) end,
    [ H.Packet.ALLIANCE_UPDATE ] = function() Ashita.Party.NeedRefresh = true end,
    [ H.Packet.PARTY_UPDATE    ] = function() Ashita.Party.NeedRefresh = true end,
    [ H.Packet.XP_UPDATE       ] = function(packet) XP.OnXpGained(packet.data) end,
    [ H.Packet.PLAYER_UPDATE   ] = function() H.PlayerUpdate() end,
    [ H.Packet.ACTION          ] = function(packet) H.StartActionPacket(packet) end,
    [ H.Packet.ACTION_MESSAGE  ] = function(packet) H.ActionMessage(packet) end,
    [ H.Packet.ITEM_DROPPED    ] = function(packet) Loot.Dropped(packet.data) end,
    [ H.Packet.ITEM_OBTAINED   ] = function(packet) Loot.Obtained(packet.data) end,
}

local entityDependentPackets =
{
    [ H.Packet.PLAYER_UPDATE  ] = true,
    [ H.Packet.ACTION         ] = true,
    [ H.Packet.ACTION_MESSAGE ] = true,
    [ H.Packet.ITEM_DROPPED   ] = true,
    [ H.Packet.ITEM_OBTAINED  ] = true,
}

local invokePacketHandler = function()
    activePacketHandler(activePacket)
end

local packetError = function(error)
    local packetId = activePacket and activePacket.id or "unknown"
    return Debug.Error.Traceback(string.format("packet_in 0x%03X", tonumber(packetId) or 0), error)
end

------------------------------------------------------------------------------------------------------
-- Subscribe to screen rendering. Use this to drive things over time.
-- https://github.com/ocornut/imgui
-- https://github.com/ocornut/imgui/blob/master/imgui_demo.cpp
-- https://github.com/ocornut/imgui/blob/master/imgui_tables.cpp
------------------------------------------------------------------------------------------------------
local updateReadiness = function()
    if not _Globals.Initialized or Ashita.Player.IsZoning() then
        return false
    end

    local now = Socket.gettime()
    if not Ashita.Player.IsLoggedIn() then
        wasLoggedIn = false
        entityPacketsReady = false
        return false
    end

    if not wasLoggedIn then
        wasLoggedIn = true
        renderReadyAt = math.max(renderReadyAt, now + RENDER_GRACE_SECONDS)
    end

    if now < renderReadyAt then
        return false
    end

    entityPacketsReady = true
    return true, now
end

local present = function(perfStart)
    -- Throttling for performance.
    Throttle.Throttle()

    -- Need to initialize here because some things aren't ready when addon loads.
    XP.Initialize()

    Ashita.Party.CheckRefreshTime()
    Ashita.Party.Refresh()

    WindowManager.CheckMouse()

    Timers.Cycle(Timers.Types.AUTOPAUSE)
    Timers.Cycle(Timers.Types.DPS)

    if not WindowManager.IsMasked() and not WindowManager.ShouldHideFromMenu() then
        -- Windows that always standalone.
        Hub.Window.Populate(Hub.Content)
        Overview.Window.Populate(Overview.Content)
        Config.Window.Populate(Config.Content)
        Debug.Window.Populate(Debug.Content)

        -- Windows that standalone only in multi-window mode.
        if WindowManager.IsMultiWindow() then
            Parse.Window.Populate(Parse.Content)
            Focus.Window.Populate(Focus.Content)
            Blog.Window.Populate(Blog.Content)
            XP.Window.Populate(XP.Content)
            Loot.Window.Populate(Loot.Content)
            Report.Window.Populate(Report.Content)
        end

        Throttle.Block()
    end

    Perf.Capture(Perf.Enums.UI_RENDER, perfStart)
end

local presentError = function(error)
    local trace, written, existing = Debug.Error.Traceback("d3d_present", error)
    renderErrorPersisted = written or existing
    return trace
end

local presentFrame = function()
    local ready, perfStart = updateReadiness()
    if not ready or (renderDisabled and perfStart < renderRetryAt) then
        return nil
    end

    renderDisabled = false
    present(perfStart)

    if renderFailureCount > 0 and not renderStableSince then
        renderStableSince = perfStart
    end

    if renderStableSince and perfStart - renderStableSince >= RENDER_RECOVERY_SECONDS then
        renderFailureCount = 0
        renderFailureNotified = false
        renderStableSince = nil
        renderErrorPersisted = false
        pcall(Ashita.Chat.Echo, "UI rendering recovered.")
    end
end

ashita.events.register('d3d_present', 'present_cb', function()
    local success = xpcall(presentFrame, presentError)
    if not success then
        renderDisabled = true
        renderStableSince = nil
        renderFailureCount = renderFailureCount + 1

        local retryIndex = math.min(renderFailureCount, #RENDER_RETRY_DELAYS)
        renderRetryAt = Socket.gettime() + RENDER_RETRY_DELAYS[retryIndex]

        if not renderFailureNotified then
            renderFailureNotified = true
            local message = "UI rendering paused after an error; combat tracking continues. Retrying automatically."
            if renderErrorPersisted then
                message = message .. " See config\\Metrics\\metrics-errors.log."
            else
                message = message .. " The error log could not be written."
            end
            pcall(Ashita.Chat.Echo, message)
        end
    end
end)

------------------------------------------------------------------------------------------------------
-- Subscribes to incoming packets.
-- Party info doesn't seem to update right away with 0xC8 (200) and 0xDD (221) so can't update party directly from those.
-- https://github.com/atom0s/XiPackets/tree/main/world/server/0x0028
------------------------------------------------------------------------------------------------------
ashita.events.register('packet_in', 'packet_in_cb', function(packet)
    if not _Globals.Initialized or not packet or not packet.data then
        return nil
    end

    local handler = packetHandlers[packet.id]
    if handler and (entityPacketsReady or not entityDependentPackets[packet.id]) then
        activePacket = packet
        activePacketHandler = handler
        xpcall(invokePacketHandler, packetError)
        activePacket = nil
        activePacketHandler = nil
    end
end)