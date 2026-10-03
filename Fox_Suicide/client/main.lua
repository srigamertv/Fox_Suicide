local function SendNotification(text)
    local mode = string.lower(Config.Notification or 'auto')

    if mode == 'auto' then
        if GetResourceState('vorp_core') == 'started' then mode = 'vorp'
        elseif GetResourceState('rsg-core') == 'started' then mode = 'rsg'
        else mode = 'chat' end
    end

    if mode == 'vorp' then
        local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
        if ok and core and core.NotifyRightTip then
            core.NotifyRightTip(text, 7500)
            return
        end
        TriggerEvent('vorp:TipRight', text, 7500)
        return
    end

    if mode == 'rsg' then
        local ok, core = pcall(function() return exports['rsg-core']:GetCoreObject() end)
        if ok and core and core.Functions and core.Functions.Notify then
            core.Functions.Notify(text, 'primary', 7500)
            return
        end
    end

    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = {Config.Locales.suicide, tostring(text)}
    })
end

local isAwaitingConfirmation = false
local suicideCamera = nil
local promptGroup = GetRandomIntInRange(0, 16777215)
local promptsInitialized = false

local ANIMATION_DICTIONARY = "script_story@mry1@ig@ig6_jamie_attempts_suicide"
local AIM_ANIMATION = "ig6_gun_to_head_ig_jamie"
local SHOOT_ANIMATION = "ig6_jamie_shoots_himself_ig_jamie"
local UPPER_BODY_FILTER = "UpperbodyFixup_filter"

local SHOOT_CONTROL = 130948705
local LEAVE_CONTROL = 1139971484
local HEAD_BONE = 27981

local PROMPT_SET_TRANSPORT_MODE = -4182673151102386388
local PROMPT_HAS_STANDARD_MODE_COMPLETED = -3951124360707079506
local SET_CINEMATIC_MODE_ACTIVE = 7626386965794333459
local APPLY_DAMAGE_TO_PED = 7597950592220076244

function CreateSuicidePrompt(controlAction, label, urgentPulsing)
    local prompt = PromptRegisterBegin()
    local promptLabel = CreateVarString(10, "LITERAL_STRING", label)

    PromptSetControlAction(prompt, controlAction)
    PromptSetText(prompt, promptLabel)

    if urgentPulsing then
        PromptSetUrgentPulsingEnabled(prompt, true)
    end

    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, promptGroup)
    Citizen.InvokeNative(PROMPT_SET_TRANSPORT_MODE, prompt, true)
    PromptRegisterEnd(prompt)

    return prompt
end

function InitializeSuicidePrompts()
    if promptsInitialized then
        return
    end

    promptsInitialized = true
    SuicidePress = CreateSuicidePrompt(SHOOT_CONTROL, Config.Locales.shoot, true)
    SuicideLeave = CreateSuicidePrompt(LEAVE_CONTROL, Config.Locales.leave, false)
end

prompts = InitializeSuicidePrompts

function SetSuicidePromptsState(enabled)
    if SuicideLeave then
        PromptSetVisible(SuicideLeave, enabled)
        PromptSetEnabled(SuicideLeave, enabled)
    end

    if SuicidePress then
        PromptSetVisible(SuicidePress, enabled)
        PromptSetEnabled(SuicidePress, enabled)
    end
end

function SetSuicideBlackBars(enabled)
    Citizen.InvokeNative(SET_CINEMATIC_MODE_ACTIVE, enabled, enabled)
end

function HideSuicideInterface()
    SetSuicideBlackBars(false)
    SetSuicidePromptsState(false)
end

function CreateSuicideCamera(playerPed)
    local cameraPosition = GetOffsetFromEntityInWorldCoords(playerPed, 4.75, 0.0, -0.5)
    local headPosition = GetPedBoneCoords(playerPed, HEAD_BONE, 0.0, 0.0, 0.0)

    suicideCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    SetCamCoord(suicideCamera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(suicideCamera, headPosition.x, headPosition.y, headPosition.z)
    SetCamFov(suicideCamera, 25.0)
    SetCamActive(suicideCamera, true)
    RenderScriptCams(true, true, 4000, true, true)

    if Config.BlackBars then
        SetSuicideBlackBars(true)
    end
end

function DestroySuicideCamera(transitionDuration)
    if not suicideCamera then
        return
    end

    RenderScriptCams(false, true, transitionDuration)
    Wait(transitionDuration)

    SetCamActive(suicideCamera, false)
    DestroyCam(suicideCamera, false)
    ClearFocus()

    suicideCamera = nil
end

function LoadSuicideAnimationDictionary()
    RequestAnimDict(ANIMATION_DICTIONARY)

    while not HasAnimDictLoaded(ANIMATION_DICTIONARY) do
        Wait(100)
    end
end

function PlaySuicideAimAnimation(playerPed)
    TaskPlayAnim(
        playerPed,
        ANIMATION_DICTIONARY,
        AIM_ANIMATION,
        1.5,
        1.0,
        -1,
        67109394,
        0.0,
        false,
        1245184,
        false,
        UPPER_BODY_FILTER,
        false
    )
end

function PlaySuicideShotAnimation(playerPed)
    TaskPlayAnim(
        playerPed,
        ANIMATION_DICTIONARY,
        SHOOT_ANIMATION,
        1.0,
        8.0,
        -1,
        2,
        0.0,
        true,
        0,
        false,
        0,
        false
    )
end

function CancelSuicideSequence(playerPed)
    ClearPedTasks(playerPed)
    FreezeEntityPosition(playerPed, false)
    HideSuicideInterface()
    DestroySuicideCamera(4000)
end

function CompleteSuicideSequence(playerPed, initialHeading)
    ClearPedTasks(playerPed)
    SetEntityHeading(playerPed, initialHeading)
    PlaySuicideShotAnimation(playerPed)
    RemoveAnimDict(ANIMATION_DICTIONARY)

    HideSuicideInterface()
    FreezeEntityPosition(playerPed, false)

    Wait(750)
    Citizen.InvokeNative(APPLY_DAMAGE_TO_PED, PlayerPedId(), 500000, false, true, true)

    Wait(1000)
    DestroySuicideCamera(6000)
end

function MonitorSuicideSequence(playerPed, initialHeading)
    local hasShot = false
    local promptGroupLabel = CreateVarString(10, "LITERAL_STRING", Config.Locales.suicide)

    while suicideCamera do
        Wait(0)
        PromptSetActiveGroupThisFrame(promptGroup, promptGroupLabel)

        if Citizen.InvokeNative(PROMPT_HAS_STANDARD_MODE_COMPLETED, SuicideLeave) then
            CancelSuicideSequence(playerPed)
            break
        end

        if IsPedShooting(playerPed) and not hasShot then
            hasShot = true
            CompleteSuicideSequence(playerPed, initialHeading)
            break
        end
    end
end

function GetValidSuicideWeapon(playerPed, currentWeapon)
    for index = 1, #Config.ValidWeapons do
        local validWeapon = Config.ValidWeapons[index]

        if currentWeapon == validWeapon and GetAmmoInPedWeapon(playerPed, currentWeapon) > 0 then
            return validWeapon
        end
    end

    return nil
end

function StartSuicideSequence()
    local playerPed = PlayerPedId()
    local _, currentWeapon = GetCurrentPedWeapon(playerPed, true)
    local validWeapon = GetValidSuicideWeapon(playerPed, currentWeapon)

    if not validWeapon then
        SendNotification(Config.Locales.requirement)
        return
    end

    if currentWeapon ~= validWeapon or not IsPedWeaponReadyToShoot(playerPed) then
        return
    end

    prompts()

    local initialHeading = GetEntityHeading(playerPed)

    CreateSuicideCamera(playerPed)
    LoadSuicideAnimationDictionary()
    PlaySuicideAimAnimation(playerPed)

    FreezeEntityPosition(playerPed, true)
    SetSuicidePromptsState(true)

    Citizen.CreateThread(function()
        MonitorSuicideSequence(playerPed, initialHeading)
    end)
end


local function handleSuicideCommand()
    if not isAwaitingConfirmation then
        SendNotification(Config.Locales.sure)
        isAwaitingConfirmation = true

        SetTimeout(Config.ConfirmationTime or 10000, function()
            isAwaitingConfirmation = false
        end)
        return
    end

    StartSuicideSequence()
    isAwaitingConfirmation = false
end

RegisterCommand(Config.Command, handleSuicideCommand, false)

for _, alias in ipairs(Config.CommandAliases or {}) do
    if alias ~= Config.Command then
        RegisterCommand(alias, handleSuicideCommand, false)
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    HideSuicideInterface()
    if suicideCamera then
        RenderScriptCams(false, false, 0, true, true)
        SetCamActive(suicideCamera, false)
        DestroyCam(suicideCamera, false)
        suicideCamera = nil
    end
end)
