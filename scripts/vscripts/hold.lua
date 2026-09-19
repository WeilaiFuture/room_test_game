-- 钉在 CUSTOM_GAME_SETUP，不推进。
local Hold = {}

function Hold.Apply()
    if not GameRules then
        return
    end
    pcall(function()
        if GameRules.EnableCustomGameSetupAutoLaunch then
            GameRules:EnableCustomGameSetupAutoLaunch(false)
        end
        if GameRules.SetCustomGameSetupTimeout then
            GameRules:SetCustomGameSetupTimeout(-1)
        end
        if GameRules.SetCustomGameSetupAutoLaunchDelay then
            GameRules:SetCustomGameSetupAutoLaunchDelay(999999)
        end
        if GameRules.SetCustomGameSetupRemainingTime then
            GameRules:SetCustomGameSetupRemainingTime(999999)
        end
        GameRules:SetHeroSelectionTime(99999)
        GameRules:SetStrategyTime(0)
        GameRules:SetShowcaseTime(0)
        GameRules:SetPreGameTime(0)
        GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 60)
        GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
        if GameRules.LockCustomGameSetupTeamAssignment then
            GameRules:LockCustomGameSetupTeamAssignment(false)
        end
    end)
end

function Hold.Force(reason)
    Hold.Apply()
    if GameRules and GameRules.ResetToCustomGameSetup then
        print("[HALL] ResetToCustomGameSetup " .. tostring(reason or ""))
        pcall(function()
            GameRules:ResetToCustomGameSetup()
        end)
    end
    Hold.Apply()
end

return Hold
