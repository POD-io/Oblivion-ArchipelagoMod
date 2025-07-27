-- Oblivion Remastered Console Module
-- Handles console command execution
local C = {}

function C.ExecuteConsole(command)
    local UEHelpers = require("UEHelpers")
    local playerController = UEHelpers.GetPlayerController()
    local KismetSystemLibrary = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
    
    if command ~= '' then
        if playerController:IsValid() then
            KismetSystemLibrary:ExecuteConsoleCommand(playerController.player, command, playerController, true)
        else
            print("[OblivionConsole] Player controller invalid")
        end
    else
        print("[OblivionConsole] Command is empty")
    end
end

return C 