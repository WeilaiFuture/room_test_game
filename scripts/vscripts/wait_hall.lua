-- wait 大厅：拉游戏图列表，点一张就 assign 再 connect。
local Config = require("hall_config")
local Identity = require("identity")
local Json = require("json")

local WaitHall = {
    maps = {},
    busy = {},
}

local function log(msg)
    print("[HALL] " .. tostring(msg))
end

local function control_url()
    return tostring(Config.controlUrl or ""):gsub("/+$", "")
end

local function token()
    return tostring(Config.token or "")
end

local function publish_maps()
    if not CustomNetTables or not CustomNetTables.SetTableValue then
        return
    end
    local maps = WaitHall.maps or {}
    pcall(function()
        CustomNetTables:SetTableValue("hall_maps", "meta", {
            count = #maps,
            gameAddonId = tostring(Config.gameAddonId or ""),
        })
    end)
    for i = 1, 32 do
        local row = maps[i]
        pcall(function()
            if row then
                CustomNetTables:SetTableValue("hall_maps", "map_" .. i, {
                    addon = tostring(row.addon or ""),
                    map = tostring(row.map or row.name or ""),
                    max_players = tonumber(row.max_players) or 10,
                })
            else
                CustomNetTables:SetTableValue("hall_maps", "map_" .. i, { map = "" })
            end
        end)
    end
end

local function fetch_maps()
    local url = control_url()
    if url == "" or not CreateHTTPRequestScriptVM then
        return
    end
    pcall(function()
        local req = CreateHTTPRequestScriptVM("GET", url .. "/v1/hall/maps")
        req:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. token())
        req:SetHTTPRequestAbsoluteTimeoutMS(8000)
        req:Send(function(result)
            local data = Json.Decode(tostring(result and result.Body or ""))
            if type(data) ~= "table" then
                return
            end
            local maps = data.maps or data.items or {}
            local out = {}
            for _, row in pairs(maps) do
                if type(row) == "table" and (row.map or row.name) then
                    out[#out + 1] = {
                        addon = tostring(row.addon or row.arcade_id or Config.gameAddonId or ""),
                        map = tostring(row.map or row.name or ""),
                        max_players = tonumber(row.max_players) or 10,
                    }
                end
            end
            if #out == 0 and Config.gameAddonId then
                out[1] = { addon = Config.gameAddonId, map = "omg", max_players = 10 }
            end
            WaitHall.maps = out
            publish_maps()
            log("wait maps " .. tostring(#out))
        end)
    end)
end

local function emit(pid, event)
    local player = PlayerResource and PlayerResource.GetPlayer and PlayerResource:GetPlayer(pid)
    if not player or not CustomGameEventManager then
        return
    end
    pcall(function()
        CustomGameEventManager:Send_ServerToPlayer(player, "hall_connect", event)
    end)
    if CustomNetTables then
        pcall(function()
            CustomNetTables:SetTableValue("hall_redirect", "jump_" .. tostring(pid), event)
        end)
    end
end

local function assign_and_send(pid, addon, map_name)
    if WaitHall.busy[pid] then
        return
    end
    local url = control_url()
    if url == "" then
        return
    end
    WaitHall.busy[pid] = true
    local steam = Identity.PlayerSteam64(pid) or ""
    log("wait assign pid=" .. tostring(pid) .. " " .. addon .. "/" .. map_name)
    pcall(function()
        local req = CreateHTTPRequestScriptVM("POST", url .. "/v1/assign")
        req:SetHTTPRequestHeaderValue("Content-Type", "application/json")
        req:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. token())
        req:SetHTTPRequestAbsoluteTimeoutMS(8000)
        req:SetHTTPRequestRawPostBody("application/json", Json.Encode({
            arcade_id = addon,
            addon = addon,
            map = map_name,
            players = 1,
        }))
        req:Send(function(result)
            WaitHall.busy[pid] = nil
            local data = Json.Decode(tostring(result and result.Body or ""))
            if type(data) ~= "table" or tostring(data.status or "") == "wait" or not (data.port or data.address) then
                log("wait no room pid=" .. tostring(pid))
                emit(pid, { player_id = pid, status = "wait", enabled = 0, text = "现在没有空闲游戏房" })
                return
            end
            local host = tostring(data.ip or data.host or "")
            local port = tonumber(data.port) or 0
            local address = tostring(data.address or "")
            if address == "" and host ~= "" and port > 0 then
                address = host .. ":" .. tostring(port)
            end
            emit(pid, {
                player_id = pid,
                steam_id = steam,
                host = host,
                port = port,
                address = address,
                password = tostring(data.password or ""),
                enabled = 1,
                status = "allocated",
                mode = "wait",
                reason = "TO_GAME",
            })
        end)
    end)
end

function WaitHall.Init()
    WaitHall.maps = {}
    WaitHall.busy = {}
    fetch_maps()
    if CustomGameEventManager and CustomGameEventManager.RegisterListener then
        CustomGameEventManager:RegisterListener("Lua_Hall", function(source, event)
            event = event or {}
            local player = EntIndexToHScript(source)
            local pid = player and player.GetPlayerID and player:GetPlayerID()
            if type(event.data) == "table" then
                event = event.data
            end
            local tp = tostring(event.tp or event.action or "")
            if tp == "refresh" then
                fetch_maps()
                return
            end
            if tp == "pick" and pid then
                local addon = tostring(event.addon or Config.gameAddonId or "")
                local map_name = tostring(event.map or "")
                if addon ~= "" and map_name ~= "" then
                    assign_and_send(pid, addon, map_name)
                end
            end
        end)
    end
    local mode = GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
    if mode and mode.SetContextThink then
        mode:SetContextThink("hall_wait_maps", function()
            if not WaitHall.maps or #WaitHall.maps == 0 then
                fetch_maps()
            end
            return 8
        end, 3)
    end
    log("wait hall " .. control_url())
end

return WaitHall
