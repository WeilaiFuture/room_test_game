if RoomMode == nil then
    RoomMode = {}
end

function RoomMode:Init()
    print("[ROOM] init map=" .. tostring(GetMapName()))
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:EnableCustomGameSetupAutoLaunch(true)
    GameRules:SetCustomGameSetupAutoLaunchDelay(3)
    if GameRules.SetCustomGameSetupTimeout then
        GameRules:SetCustomGameSetupTimeout(8)
    end
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetPreGameTime(5)
    GameRules:SetPostGameTime(30)
    GameRules:SetSameHeroSelectionEnabled(true)

    local mode = GameRules:GetGameModeEntity()
    if mode then
        mode:SetFogOfWarDisabled(true)
        if mode.SetCustomGameForceHero then
            mode:SetCustomGameForceHero("npc_dota_hero_axe")
        end
    end

    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("lobby_rooms", "ui", {
                phase = "room",
                message = "已进入房间地图 " .. tostring(GetMapName()),
            })
        end)
    end
end

return RoomMode
