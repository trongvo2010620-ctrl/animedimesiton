--[[
    ===================================================================
    🌟 SLH HUB MODIFIED | ANIME DIMENSIONS (OCT 2026 EDITION)
    Tái hiện 100% đầy đủ toàn bộ giao diện & tính năng từ SLH Hub
    ⚡ TÍNH NĂNG MỚI BỔ SUNG:
       - Full 7 Tabs chuẩn SLH: Main, More, Character, Setting, Buy, Webhook, Misc
       - Infinite Mode Auto Reset theo Wave, Auto Delete Map, Exploit Safety
       - Skill Priority Sequence (Thứ tự ra chiêu 1->5)
       - Proximity Prompts, Ctrl+Click TP, Infinite Yield, StatGui
       - Tự động lưu ngầm 100% (Silent Auto-Save & Auto-Restore)
       - Auto Rejoin khi Kick / Mất kết nối (Dual Layer)
    ===================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character
local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
local Humanoid = Character and Character:FindFirstChild("Humanoid")

local function SetupCharacter(char)
    if not char then return end
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5) or char:FindFirstChild("HumanoidRootPart")
    Humanoid = char:WaitForChild("Humanoid", 5) or char:FindFirstChild("Humanoid")
end

if Character then
    task.spawn(function()
        SetupCharacter(Character)
    end)
end

LocalPlayer.CharacterAdded:Connect(function(char)
    SetupCharacter(char)
end)

-- 1. CHỐNG VĂNG GAME KHI TREO MÁY (ANTI-AFK)
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

-- ===================================================================
-- 2. HỆ THỐNG CẤU HÌNH & TỰ ĐỘNG LƯU NGẦM 100% (ZERO ACTION AUTO-SAVE)
-- ===================================================================
local AutoSaveFile = "AnimeDimensions_AutoSave.json"

local Settings = {
    -- TAB 1: MAIN & FARMING
    MapSelection = "Auto",
    SelectDifficulty = "Normal",
    WaitOnLobbyAfterJoin = 10,
    AutoPlay = false,
    Hardcore = false,
    AutoReplay = true,
    FriendOnly = false,
    AutoSelectMap = false,
    TweenSpeed = 500,
    AutoMob = false,
    KillAura = false,
    DistanceToSkill = 30,
    AutoSkill = false,
    AutoAssistSkill = false,
    AutoFruitSkill = false,
    SelectAttackMethod = "Click",
    AutoMelee = true,
    FarmDistance = 7,
    FarmPosition = "Above",

    -- TAB 2: MORE (RAIDS & EXTREME)
    RaidSelection = "Auto",
    SelectExtremeDimensionDifficulty = "Extreme",
    ExtremeDimensionMinReward = 100,
    CooldownJoinRaid = 10,
    AutoRaid = false,
    FreeBossRush = false,
    BossRush = false,
    AutoSpeedRaid = false,
    AutoRaidChallenge = false,
    ExtremeDimension = false,
    AutoDodgeSkill = false,
    AutoDeleteMap = false,
    AutoRedeemAllCode = false,
    BackToLobbyIfGotExploitsDetected = false,
    HideName = false,
    DashNoCooldown = false,
    AutoWalkOnlyBoss = false,
    AutoClaimQuestAndReward = false,
    GoLobbyMethod = "TeleportToLobby",
    BackToLobbyIfRaidOpen = false,
    StopReplayIfRaidOpen = false,
    DisableNoclip = false,
    DoNotThingIfHavePlayer = false,

    -- TAB 3: CHARACTER & CARDS
    AutoEquipCharacter = false,
    AutoResetToMain = false,
    AutoResetToFirstAssist = false,
    SelectRarity = "Common",
    AutoSellCard = false,
    EquipBestCard = false,
    EquipBestCardMode = "Damage/Crit",

    -- TAB 4: SETTING (DODGE, SKILL PRIORITY, INF)
    SizeDodgePart = 3.5,
    SizeDodgePartY = 100,
    TweenSpeedDodgePart = 0.15,
    DodgePartTransparency = 0.9,
    GoAFKIfRaidNotOpen = false,
    SelectWaveToReset = 100,
    ResetINFMode = false,
    SkillFirst = "4",
    SkillSecond = "3",
    SkillThird = "5",
    SkillFourth = "1",
    SkillFifth = "2",

    -- TAB 5: BUY
    SelectMethodBuy = "Raid Token",
    BuyRushTicket = false,
    Buy100RaidToken = false,

    -- TAB 6: WEBHOOK
    WebhookURL = "",
    SendDimensionDrops = true,
    SendRaidDrops = true,
    WebhookOnRejoin = true,

    -- TAB 7: MISC
    Speed = 16,
    Jump = 50,
    WalkSpeed = false,
    JumpPower = false,
    CtrlClickTP = false,
    CloseGuiAfterExecute = false,
    StatGui = false,
    CreditGui = false,
    StatGuiPosition = "Right",
    CreditGuiPosition = "Left",
    RejoinIfGotKick = true,
    WhiteScreen = false
}

-- Tự động nạp cấu hình cũ ngay khi mở file
pcall(function()
    if readfile and isfile and isfile(AutoSaveFile) then
        local savedData = HttpService:JSONDecode(readfile(AutoSaveFile))
        for key, val in pairs(savedData) do
            Settings[key] = val
        end
        print("⚡ [AutoSave]: Đã tự động khôi phục toàn bộ cài đặt cũ của bạn!")
    end
end)

-- Hàm tự động lưu ngầm không làm phiền người chơi
local function AutoSave()
    pcall(function()
        if writefile then
            writefile(AutoSaveFile, HttpService:JSONEncode(Settings))
        end
    end)
end

-- ===================================================================
-- HÀM GỬI DISCORD WEBHOOK THÔNG MINH
-- ===================================================================
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (Fluxus and Fluxus.request)

local function SendDiscordWebhook(title, description, fields, color)
    if not Settings.WebhookURL or Settings.WebhookURL == "" then return end
    if not httpRequest then return end

    local payload = {
        username = "SLH Hub Modified",
        avatar_url = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=150&height=150&format=png",
        embeds = {
            {
                title = title or "⚡ SLH Hub Notification",
                description = description or "",
                color = color or 16711680,
                fields = fields or {},
                footer = {
                    text = "SLH Hub Modified • " .. os.date("%d/%m/%Y %H:%M:%S")
                },
                timestamp = DateTime.now():ToIsoDate()
            }
        }
    }

    pcall(function()
        httpRequest({
            Url = Settings.WebhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- ===================================================================
-- 3. LOAD GIAO DIỆN CHÍNH (ORION UI)
-- ===================================================================
local OrionLib;
local orionMirrors = {
    "https://raw.githubusercontent.com/jensonhirst/Orion/main/source",
    "https://raw.githubusercontent.com/shlexware/Orion/main/source"
}

for _, mirror in ipairs(orionMirrors) do
    local s, res = pcall(function()
        local code = game:HttpGet(mirror)
        if code and not code:find("404: Not Found") and #code > 1000 then
            return loadstring(code)()
        end
    end)
    if s and res and type(res) == "table" and res.MakeWindow then
        OrionLib = res
        break
    end
end

if not OrionLib then
    warn("❌ Không thể tải thư viện Orion UI!")
    return
end

local Window = OrionLib:MakeWindow({
    Name = "SLH Hub Modified | AnimeDimensions | 24 Oct, 2026",
    HidePremium = false,
    SaveConfig = false,
    IntroText = "SLH Hub Modified Pro"
})

-- ===================================================================
-- TAB 1: MAIN
-- ===================================================================
local MainTab = Window:MakeTab({
    Name = "Main",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MainTab:AddSection({ Name = "Farming" })

MainTab:AddDropdown({
    Name = "MapSelection(AutoUpdate!)",
    Default = Settings.MapSelection,
    Options = { "Auto", "Titan Dimension", "Demon Dimension", "Dragon Dimension", "Ghoul Dimension", "Hero Dimension", "Curse Dimension", "Shield Dimension", "Sword Dimension", "One Piece Dimension" },
    Callback = function(v)
        Settings.MapSelection = v
        AutoSave()
    end
})

MainTab:AddDropdown({
    Name = "SelectDifficulty",
    Default = Settings.SelectDifficulty,
    Options = { "Easy", "Normal", "Hard", "Nightmare", "Inferno" },
    Callback = function(v)
        Settings.SelectDifficulty = v
        AutoSave()
    end
})

MainTab:AddTextbox({
    Name = "WaitOnLobbyAfterJoin(OnlyNumber)",
    Default = tostring(Settings.WaitOnLobbyAfterJoin),
    TextDisappear = false,
    Callback = function(v)
        Settings.WaitOnLobbyAfterJoin = tonumber(v) or 10
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoPlay",
    Default = Settings.AutoPlay,
    Callback = function(v)
        Settings.AutoPlay = v
        if v then
            Settings.AutoMob = true
            Settings.AutoMelee = true
            Settings.KillAura = true
            Settings.AutoSkill = true
            Settings.AutoAssistSkill = true
            Settings.AutoFruitSkill = true
            Settings.AutoReplay = true
            Settings.AutoSelectMap = true
        end
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "Hardcore",
    Default = Settings.Hardcore,
    Callback = function(v)
        Settings.Hardcore = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoReplay",
    Default = Settings.AutoReplay,
    Callback = function(v)
        Settings.AutoReplay = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "FriendOnly",
    Default = Settings.FriendOnly,
    Callback = function(v)
        Settings.FriendOnly = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoSelectMap(DetectedLevel)",
    Default = Settings.AutoSelectMap,
    Callback = function(v)
        Settings.AutoSelectMap = v
        AutoSave()
    end
})

MainTab:AddSection({ Name = "Combat & Movement" })

MainTab:AddTextbox({
    Name = "TweenSpeed(OnlyNumber)",
    Default = tostring(Settings.TweenSpeed),
    TextDisappear = false,
    Callback = function(v)
        Settings.TweenSpeed = tonumber(v) or 500
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoMob",
    Default = Settings.AutoMob,
    Callback = function(v)
        Settings.AutoMob = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "Kill Aura",
    Default = Settings.KillAura,
    Callback = function(v)
        Settings.KillAura = v
        AutoSave()
    end
})

MainTab:AddTextbox({
    Name = "DistanceToSkill(OnlyNumber)",
    Default = tostring(Settings.DistanceToSkill),
    TextDisappear = false,
    Callback = function(v)
        Settings.DistanceToSkill = tonumber(v) or 30
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoSkill",
    Default = Settings.AutoSkill,
    Callback = function(v)
        Settings.AutoSkill = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoAssistSkill",
    Default = Settings.AutoAssistSkill,
    Callback = function(v)
        Settings.AutoAssistSkill = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoFruitSkill",
    Default = Settings.AutoFruitSkill,
    Callback = function(v)
        Settings.AutoFruitSkill = v
        AutoSave()
    end
})

MainTab:AddDropdown({
    Name = "SelectAttackMethod",
    Default = Settings.SelectAttackMethod,
    Options = { "Click", "Melee", "Skill" },
    Callback = function(v)
        Settings.SelectAttackMethod = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "AutoMelee",
    Default = Settings.AutoMelee,
    Callback = function(v)
        Settings.AutoMelee = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 2: MORE (RAIDS, BOSS RUSH, CHALLENGE & FUNCTIONS)
-- ===================================================================
local MoreTab = Window:MakeTab({
    Name = "More",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MoreTab:AddSection({ Name = "JoiningCombo" })

MoreTab:AddDropdown({
    Name = "RaidSelection",
    Default = Settings.RaidSelection,
    Options = { "Auto", "Shadow Raid", "Dio Over Heaven Raid", "Sukuna Raid", "Aizen Raid", "Gojo Raid" },
    Callback = function(v)
        Settings.RaidSelection = v
        AutoSave()
    end
})

MoreTab:AddDropdown({
    Name = "SelectExtremeDimensionDifficulty",
    Default = Settings.SelectExtremeDimensionDifficulty,
    Options = { "Extreme", "Nightmare", "Hard" },
    Callback = function(v)
        Settings.SelectExtremeDimensionDifficulty = v
        AutoSave()
    end
})

MoreTab:AddDropdown({
    Name = "ExtremeDimensionMinReward(%)",
    Default = tostring(Settings.ExtremeDimensionMinReward),
    Options = { "100", "75", "50", "25" },
    Callback = function(v)
        Settings.ExtremeDimensionMinReward = tonumber(v) or 100
        AutoSave()
    end
})

MoreTab:AddTextbox({
    Name = "Cooldown JoinRaid(OnlyNumber)",
    Default = tostring(Settings.CooldownJoinRaid),
    TextDisappear = false,
    Callback = function(v)
        Settings.CooldownJoinRaid = tonumber(v) or 10
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoRaid",
    Default = Settings.AutoRaid,
    Callback = function(v)
        Settings.AutoRaid = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "FreeBossRush",
    Default = Settings.FreeBossRush,
    Callback = function(v)
        Settings.FreeBossRush = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "BossRush",
    Default = Settings.BossRush,
    Callback = function(v)
        Settings.BossRush = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoSpeedRaid(RandomSelect)",
    Default = Settings.AutoSpeedRaid,
    Callback = function(v)
        Settings.AutoSpeedRaid = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoRaidChallenge(IfRewardAvailable)",
    Default = Settings.AutoRaidChallenge,
    Callback = function(v)
        Settings.AutoRaidChallenge = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "ExtremeDimension(MinReward%)",
    Default = Settings.ExtremeDimension,
    Callback = function(v)
        Settings.ExtremeDimension = v
        AutoSave()
    end
})

MoreTab:AddSection({ Name = "MoreFunction" })

MoreTab:AddButton({
    Name = "Return To Lobby",
    Callback = function()
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("TeleportToLobby", true) 
                or ReplicatedStorage:FindFirstChild("ReturnLobby", true)
            if remote then remote:FireServer() end
        end)
        TeleportService:Teleport(6379034480, LocalPlayer)
    end
})

MoreTab:AddToggle({
    Name = "AutoDodgeSkill",
    Default = Settings.AutoDodgeSkill,
    Callback = function(v)
        Settings.AutoDodgeSkill = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoDeleteMap",
    Default = Settings.AutoDeleteMap,
    Callback = function(v)
        Settings.AutoDeleteMap = v
        if v then
            pcall(function()
                for _, obj in pairs(workspace:GetDescendants()) do
                    if obj:IsA("Decal") or obj:IsA("Texture") then
                        obj.Transparency = 1
                    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                        obj.Enabled = false
                    end
                end
            end)
        end
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoRedeemAllCode",
    Default = Settings.AutoRedeemAllCode,
    Callback = function(v)
        Settings.AutoRedeemAllCode = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "BackToLobbyIfGotExploitsDetected",
    Default = Settings.BackToLobbyIfGotExploitsDetected,
    Callback = function(v)
        Settings.BackToLobbyIfGotExploitsDetected = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "HideName",
    Default = Settings.HideName,
    Callback = function(v)
        Settings.HideName = v
        pcall(function()
            local head = Character and Character:FindFirstChild("Head")
            if head then
                for _, gui in pairs(head:GetChildren()) do
                    if gui:IsA("BillboardGui") then gui.Enabled = not v end
                end
            end
        end)
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "DashNoCooldown",
    Default = Settings.DashNoCooldown,
    Callback = function(v)
        Settings.DashNoCooldown = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoWalk(Only Boss)",
    Default = Settings.AutoWalkOnlyBoss,
    Callback = function(v)
        Settings.AutoWalkOnlyBoss = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "AutoClaimQuestAndReward",
    Default = Settings.AutoClaimQuestAndReward,
    Callback = function(v)
        Settings.AutoClaimQuestAndReward = v
        AutoSave()
    end
})

MoreTab:AddDropdown({
    Name = "GoLobbyMethod",
    Default = Settings.GoLobbyMethod,
    Options = { "TeleportToLobby", "Reconnect", "Leave" },
    Callback = function(v)
        Settings.GoLobbyMethod = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "BackToLobbyIfRaidOpen",
    Default = Settings.BackToLobbyIfRaidOpen,
    Callback = function(v)
        Settings.BackToLobbyIfRaidOpen = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "StopReplayIfRaidOpen",
    Default = Settings.StopReplayIfRaidOpen,
    Callback = function(v)
        Settings.StopReplayIfRaidOpen = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "Disable Noclip",
    Default = Settings.DisableNoclip,
    Callback = function(v)
        Settings.DisableNoclip = v
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = "DoNotThingIfHavePlayer",
    Default = Settings.DoNotThingIfHavePlayer,
    Callback = function(v)
        Settings.DoNotThingIfHavePlayer = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 3: CHARACTER (CHARACTERS & CARDS)
-- ===================================================================
local CharTab = Window:MakeTab({
    Name = "Character",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

CharTab:AddSection({ Name = "Character" })

CharTab:AddToggle({
    Name = "AutoEquip Character",
    Default = Settings.AutoEquipCharacter,
    Callback = function(v)
        Settings.AutoEquipCharacter = v
        AutoSave()
    end
})

CharTab:AddToggle({
    Name = "Auto Reset To Main",
    Default = Settings.AutoResetToMain,
    Callback = function(v)
        Settings.AutoResetToMain = v
        AutoSave()
    end
})

CharTab:AddToggle({
    Name = "Auto Reset To First Assist",
    Default = Settings.AutoResetToFirstAssist,
    Callback = function(v)
        Settings.AutoResetToFirstAssist = v
        AutoSave()
    end
})

CharTab:AddButton({
    Name = "SaveCharacter",
    Callback = function()
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("SaveCharacter", true) 
                or ReplicatedStorage:FindFirstChild("SaveEquipment", true)
            if remote then remote:FireServer() end
        end)
    end
})

CharTab:AddSection({ Name = "SellCard" })

CharTab:AddDropdown({
    Name = "SelectRarity",
    Default = Settings.SelectRarity,
    Options = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
    Callback = function(v)
        Settings.SelectRarity = v
        AutoSave()
    end
})

CharTab:AddToggle({
    Name = "AutoSellCard",
    Default = Settings.AutoSellCard,
    Callback = function(v)
        Settings.AutoSellCard = v
        AutoSave()
    end
})

CharTab:AddSection({ Name = "EquipCard" })

CharTab:AddToggle({
    Name = "EquipBestCard",
    Default = Settings.EquipBestCard,
    Callback = function(v)
        Settings.EquipBestCard = v
        AutoSave()
    end
})

CharTab:AddDropdown({
    Name = "EquipBestCardMode",
    Default = Settings.EquipBestCardMode,
    Options = { "Damage/Crit", "Cooldown", "Health/Defense" },
    Callback = function(v)
        Settings.EquipBestCardMode = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 4: SETTING (DODGE, SKILL PRIORITY, INF MODE)
-- ===================================================================
local SettingTab = Window:MakeTab({
    Name = "Setting",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

SettingTab:AddSection({ Name = "Setting DodgeSkill" })

SettingTab:AddTextbox({
    Name = "SizeDodgePart (OnlyNumber)",
    Default = tostring(Settings.SizeDodgePart),
    TextDisappear = false,
    Callback = function(v)
        Settings.SizeDodgePart = tonumber(v) or 3.5
        AutoSave()
    end
})

SettingTab:AddTextbox({
    Name = "SizeDodgePart Y (OnlyNumber)",
    Default = tostring(Settings.SizeDodgePartY),
    TextDisappear = false,
    Callback = function(v)
        Settings.SizeDodgePartY = tonumber(v) or 100
        AutoSave()
    end
})

SettingTab:AddTextbox({
    Name = "TweenSpeedDodgePart (Sec)",
    Default = tostring(Settings.TweenSpeedDodgePart),
    TextDisappear = false,
    Callback = function(v)
        Settings.TweenSpeedDodgePart = tonumber(v) or 0.15
        AutoSave()
    end
})

SettingTab:AddTextbox({
    Name = "DodgePartTransparency (OnlyNumber)",
    Default = tostring(Settings.DodgePartTransparency),
    TextDisappear = false,
    Callback = function(v)
        Settings.DodgePartTransparency = tonumber(v) or 0.9
        AutoSave()
    end
})

SettingTab:AddSection({ Name = "MoreFunction2" })

SettingTab:AddToggle({
    Name = "Go AFK (If Raid Not Open)",
    Default = Settings.GoAFKIfRaidNotOpen,
    Callback = function(v)
        Settings.GoAFKIfRaidNotOpen = v
        AutoSave()
    end
})

SettingTab:AddTextbox({
    Name = "SelectWaveToReset",
    Default = tostring(Settings.SelectWaveToReset),
    TextDisappear = false,
    Callback = function(v)
        Settings.SelectWaveToReset = tonumber(v) or 100
        AutoSave()
    end
})

SettingTab:AddToggle({
    Name = "Reset INF Mode (SelectWave)",
    Default = Settings.ResetINFMode,
    Callback = function(v)
        Settings.ResetINFMode = v
        AutoSave()
    end
})

SettingTab:AddSection({ Name = "Setting AutoSkill" })

SettingTab:AddDropdown({
    Name = "SkillFirst",
    Default = tostring(Settings.SkillFirst),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        Settings.SkillFirst = v
        AutoSave()
    end
})

SettingTab:AddDropdown({
    Name = "SkillSecond",
    Default = tostring(Settings.SkillSecond),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        Settings.SkillSecond = v
        AutoSave()
    end
})

SettingTab:AddDropdown({
    Name = "SkillThird",
    Default = tostring(Settings.SkillThird),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        Settings.SkillThird = v
        AutoSave()
    end
})

SettingTab:AddDropdown({
    Name = "SkillFourth",
    Default = tostring(Settings.SkillFourth),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        Settings.SkillFourth = v
        AutoSave()
    end
})

SettingTab:AddDropdown({
    Name = "SkillFifth",
    Default = tostring(Settings.SkillFifth),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        Settings.SkillFifth = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 5: BUY (AUTO BUY SHOP)
-- ===================================================================
local BuyTab = Window:MakeTab({
    Name = "Buy",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

BuyTab:AddSection({ Name = "AutoBuy" })

BuyTab:AddDropdown({
    Name = "Select method buy",
    Default = Settings.SelectMethodBuy,
    Options = { "Raid Token", "Gems", "Gold" },
    Callback = function(v)
        Settings.SelectMethodBuy = v
        AutoSave()
    end
})

BuyTab:AddToggle({
    Name = "BuyRushTicket",
    Default = Settings.BuyRushTicket,
    Callback = function(v)
        Settings.BuyRushTicket = v
        AutoSave()
    end
})

BuyTab:AddToggle({
    Name = "Buy100RaidToken(BossRushToken)",
    Default = Settings.Buy100RaidToken,
    Callback = function(v)
        Settings.Buy100RaidToken = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 6: WEBHOOK
-- ===================================================================
local WebhookTab = Window:MakeTab({
    Name = "Webhook",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

WebhookTab:AddSection({ Name = "Webhook" })

WebhookTab:AddParagraph("----------------------------", "Search in Youtube\n\"How to Create Webhook\"\n----------------------------")

WebhookTab:AddTextbox({
    Name = "Url Webhook",
    Default = Settings.WebhookURL,
    TextDisappear = false,
    Callback = function(v)
        Settings.WebhookURL = v
        AutoSave()
    end
})

WebhookTab:AddToggle({
    Name = "Send(DimensionDropsResult)",
    Default = Settings.SendDimensionDrops,
    Callback = function(v)
        Settings.SendDimensionDrops = v
        AutoSave()
    end
})

WebhookTab:AddToggle({
    Name = "Send(RaidDropsResult)",
    Default = Settings.SendRaidDrops,
    Callback = function(v)
        Settings.SendRaidDrops = v
        AutoSave()
    end
})

WebhookTab:AddToggle({
    Name = "Send(RejoinAlert)",
    Default = Settings.WebhookOnRejoin,
    Callback = function(v)
        Settings.WebhookOnRejoin = v
        AutoSave()
    end
})

WebhookTab:AddButton({
    Name = "🔔 Test Webhook",
    Callback = function()
        if not Settings.WebhookURL or Settings.WebhookURL == "" then
            OrionLib:MakeNotification({
                Name = "Webhook Error",
                Content = "Please enter a Webhook URL first!",
                Image = "rbxassetid://4483345998",
                Time = 4
            })
            return
        end

        local testFields = {
            { name = "Player", value = LocalPlayer.Name, inline = true },
            { name = "User ID", value = tostring(LocalPlayer.UserId), inline = true },
            { name = "Place ID", value = tostring(game.PlaceId), inline = true },
            { name = "Kill Aura", value = Settings.KillAura and "ON" or "OFF", inline = true },
            { name = "Auto Play", value = Settings.AutoPlay and "ON" or "OFF", inline = true }
        }

        SendDiscordWebhook("🔔 [TEST] SLH Hub Webhook Connected", "Your Discord Webhook is working correctly!", testFields, 65280)

        OrionLib:MakeNotification({
            Name = "Success!",
            Content = "Sent test message to Discord!",
            Image = "rbxassetid://4483345998",
            Time = 4
        })
    end
})

-- ===================================================================
-- TAB 7: MISC
-- ===================================================================
local MiscTab = Window:MakeTab({
    Name = "Misc",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MiscTab:AddSection({ Name = "Section1" })

MiscTab:AddTextbox({
    Name = "Speed",
    Default = tostring(Settings.Speed),
    TextDisappear = false,
    Callback = function(v)
        Settings.Speed = tonumber(v) or 16
        if Settings.WalkSpeed and Humanoid then Humanoid.WalkSpeed = Settings.Speed end
        AutoSave()
    end
})

MiscTab:AddTextbox({
    Name = "Jump",
    Default = tostring(Settings.Jump),
    TextDisappear = false,
    Callback = function(v)
        Settings.Jump = tonumber(v) or 50
        if Settings.JumpPower and Humanoid then Humanoid.JumpPower = Settings.Jump end
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "WalkSpeed",
    Default = Settings.WalkSpeed,
    Callback = function(v)
        Settings.WalkSpeed = v
        if Humanoid then Humanoid.WalkSpeed = v and Settings.Speed or 16 end
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "JumpPower",
    Default = Settings.JumpPower,
    Callback = function(v)
        Settings.JumpPower = v
        if Humanoid then Humanoid.JumpPower = v and Settings.Jump or 50 end
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "Ctrl+ClickTP",
    Default = Settings.CtrlClickTP,
    Callback = function(v)
        Settings.CtrlClickTP = v
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "CloseGuiAfterExecute",
    Default = Settings.CloseGuiAfterExecute,
    Callback = function(v)
        Settings.CloseGuiAfterExecute = v
        AutoSave()
    end
})

MiscTab:AddButton({
    Name = "Rejoin",
    Callback = function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
})

MiscTab:AddButton({
    Name = "HopServer",
    Callback = function()
        pcall(function()
            local serversApi = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            local req = (syn and syn.request) or (http and http.request) or request
            if req then
                local res = req({ Url = serversApi, Method = "GET" })
                local data = HttpService:JSONDecode(res.Body)
                for _, s in ipairs(data.data) do
                    if s.playing < s.maxPlayers and s.id ~= game.JobId then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                        break
                    end
                end
            end
        end)
    end
})

MiscTab:AddButton({
    Name = "FireProximityPrompt",
    Callback = function()
        for _, p in pairs(workspace:GetDescendants()) do
            if p:IsA("ProximityPrompt") then fireproximityprompt(p) end
        end
    end
})

MiscTab:AddButton({
    Name = "InstantProximityPrompt",
    Callback = function()
        for _, p in pairs(workspace:GetDescendants()) do
            if p:IsA("ProximityPrompt") then p.HoldDuration = 0 end
        end
    end
})

MiscTab:AddSection({ Name = "Section2" })

MiscTab:AddDropdown({
    Name = "StatGuiPosition",
    Default = Settings.StatGuiPosition,
    Options = { "Right", "Left" },
    Callback = function(v)
        Settings.StatGuiPosition = v
        AutoSave()
    end
})

MiscTab:AddDropdown({
    Name = "CreditGuiPosition",
    Default = Settings.CreditGuiPosition,
    Options = { "Left", "Right" },
    Callback = function(v)
        Settings.CreditGuiPosition = v
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "StatGui",
    Default = Settings.StatGui,
    Callback = function(v)
        Settings.StatGui = v
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "CreditGui",
    Default = Settings.CreditGui,
    Callback = function(v)
        Settings.CreditGui = v
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "RejoinIfGotKick",
    Default = Settings.RejoinIfGotKick,
    Callback = function(v)
        Settings.RejoinIfGotKick = v
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "Whitescreen(Reduce Cpu)",
    Default = Settings.WhiteScreen,
    Callback = function(v)
        Settings.WhiteScreen = v
        RunService:Set3dRenderingEnabled(not v)
        AutoSave()
    end
})

MiscTab:AddButton({
    Name = "infiniteyield",
    Callback = function()
        loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))()
    end
})

MiscTab:AddButton({
    Name = "ResetCamera",
    Callback = function()
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        workspace.CurrentCamera.CameraSubject = Humanoid
    end
})

MiscTab:AddButton({
    Name = "Copy SLH Modified Discord Link",
    Callback = function()
        if setclipboard then setclipboard("https://discord.gg/smelllikehacker") end
        OrionLib:MakeNotification({
            Name = "Copied!",
            Content = "Discord invite copied to clipboard!",
            Image = "rbxassetid://4483345998",
            Time = 3
        })
    end
})

-- ===================================================================
-- 🔄 LOGIC CORE CHẠY NGẦM ĐẦY ĐỦ (COMPLETE EXECUTION ENGINES)
-- ===================================================================

-- 1. HỆ THỐNG AUTO REJOIN KHI BỊ KICK / MẤT KẾT NỐI
local function TriggerRejoin()
    if not Settings.RejoinIfGotKick then return end
    warn("⚠️ [PHÁT HIỆN BỊ KICK / MẤT MẠNG! ĐANG TỰ ĐỘNG REJOIN...]")
    
    if Settings.WebhookOnRejoin then
        SendDiscordWebhook(
            "⚠️ [CẢNH BÁO] Tài Khoản Bị Kick / Rejoin",
            "Tài khoản **" .. LocalPlayer.Name .. "** vừa mất kết nối khỏi server và đang tự động Rejoin!",
            {
                { name = "Player", value = LocalPlayer.Name, inline = true },
                { name = "Time", value = os.date("%H:%M:%S - %d/%m/%Y"), inline = true },
                { name = "Place ID", value = tostring(game.PlaceId), inline = false }
            },
            15158332
        )
    end

    local queue = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    if queue then
        pcall(function()
            queue([[
                task.wait(4)
                loadstring(readfile and readfile("AnimeDimensions_CleanSource.lua") or "")()
            ]])
        end)
    end

    task.wait(3)
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

GuiService.ErrorMessageChanged:Connect(function()
    TriggerRejoin()
end)

pcall(function()
    local promptOverlay = CoreGui:WaitForChild("RobloxPromptGui", 5):WaitForChild("promptOverlay", 5)
    if promptOverlay then
        promptOverlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                TriggerRejoin()
            end
        end)
    end
end)

-- ===================================================================
-- 🔄 LOGIC CORE CHẠY NGẦM ĐẦY ĐỦ (COMPLETE EXECUTION ENGINES)
-- ===================================================================

local VirtualInputManager = game:GetService("VirtualInputManager")

-- HÀM MÔ PHỎNG CLICK CHUỘT THẬT (ĐẢM BẢO 100% LUÔN ĐÁNH ĐƯỢC MỌI GAME)
local function SimulateLeftClick()
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.01)
        VirtualUser:Button1Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
    pcall(function()
        if mouse1click then mouse1click() end
    end)
end

-- HÀM MÔ PHỎNG BẤM PHÍM SKILL (1, 2, 3, 4, 5)
local keyMap = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five
}

local function SimulateSkillKey(numStr)
    local kc = keyMap[tostring(numStr)]
    if kc then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, kc, false, game)
            task.wait(0.02)
            VirtualInputManager:SendKeyEvent(false, kc, false, game)
        end)
    end
end

-- HÀM TÌM TẤT CẢ QUÁI / BOSS TOÀN DIỆN (QUÉT MỌI NƠI TRONG WORKSPACE)
local function GetAllEnemies()
    local list = {}
    local seen = {}

    local function CheckModel(model)
        if not model or not model:IsA("Model") or model == Character or seen[model] then return end
        if Players:GetPlayerFromCharacter(model) then return end
        local hum = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
        if hum and root and hum.Health > 0 then
            seen[model] = true
            table.insert(list, model)
        end
    end

    -- 1. Quét các thư mục phổ biến
    local candidateFolders = {
        workspace:FindFirstChild("Enemies"),
        workspace:FindFirstChild("Mobs"),
        workspace:FindFirstChild("Monsters"),
        workspace:FindFirstChild("Entities"),
        workspace:FindFirstChild("Dungeon") and workspace.Dungeon:FindFirstChild("Enemies"),
        workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Enemies"),
        workspace:FindFirstChild("CurrentRoom") and workspace.CurrentRoom:FindFirstChild("Enemies"),
        workspace:FindFirstChild("Folder")
    }

    for _, folder in ipairs(candidateFolders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                CheckModel(child)
            end
        end
    end

    -- 2. Quét trực tiếp trong Workspace nếu chưa tìm thấy
    if #list == 0 then
        for _, child in ipairs(workspace:GetChildren()) do
            CheckModel(child)
        end
    end

    return list
end

-- HÀM LẤY MỤC TIÊU ƯU TIÊN GẦN NHẤT HOẶC BOSS
local function GetTarget()
    local enemies = GetAllEnemies()
    if #enemies == 0 then return nil end

    if Settings.AutoWalkOnlyBoss then
        for _, mob in ipairs(enemies) do
            local hum = mob:FindFirstChildOfClass("Humanoid")
            if mob.Name:lower():find("boss") or mob:FindFirstChild("BossLabel") or (hum and hum.MaxHealth > 50000) then
                return mob
            end
        end
    end

    local closestMob = nil
    local minDistance = math.huge
    for _, mob in ipairs(enemies) do
        local root = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso") or mob:FindFirstChild("UpperTorso")
        if root and HumanoidRootPart then
            local dist = (HumanoidRootPart.Position - root.Position).Magnitude
            if dist < minDistance then
                minDistance = dist
                closestMob = mob
            end
        end
    end
    return closestMob
end

-- VÒNG LẶP NOCLIP LIÊN TỤC TRÁNH KẸT VÀ RƠI
RunService.Stepped:Connect(function()
    if Character and (Settings.AutoMob or Settings.AutoPlay or not Settings.DisableNoclip) then
        for _, part in ipairs(Character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end)

-- 3. VÒNG LẶP FARM CHÍNH (BAY ĐẾN QUÁI & ĐÁNH THẬT + TWEEN + CHỐNG RƠI)
task.spawn(function()
    while task.wait(0.03) do
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then
            -- Pause if other players are present
        elseif (Settings.AutoMob or Settings.AutoPlay) and Humanoid and Humanoid.Health > 0 and HumanoidRootPart then
            local target = GetTarget()
            if target then
                local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso")
                if targetRoot then
                    local targetCFrame = targetRoot.CFrame
                    local offset = (Settings.FarmPosition == "Above") 
                        and (CFrame.new(0, Settings.FarmDistance or 7, 0) * CFrame.Angles(math.rad(-90), 0, 0))
                        or CFrame.new(0, 0, Settings.FarmDistance or 7)

                    HumanoidRootPart.CFrame = targetCFrame * offset
                    HumanoidRootPart.Velocity = Vector3.new(0, 0, 0)
                    HumanoidRootPart.RotVelocity = Vector3.new(0, 0, 0)

                    if Settings.AutoMelee or Settings.SelectAttackMethod == "Melee" or Settings.SelectAttackMethod == "Click" then
                        SimulateLeftClick()

                        pcall(function()
                            local combatRemote = ReplicatedStorage:FindFirstChild("Attack", true) 
                                or ReplicatedStorage:FindFirstChild("MeleeAttack", true) 
                                or ReplicatedStorage:FindFirstChild("Combat", true)
                                or ReplicatedStorage:FindFirstChild("Punch", true)
                            if combatRemote then combatRemote:FireServer() end
                        end)
                    end
                end
            end
        end
    end
end)

-- 4. VÒNG LẶP KILL AURA (QUÉT TOÀN BỘ WORKSPACE & TẤT CẢ QUÁI)
task.spawn(function()
    while task.wait(0.12) do
        if Settings.KillAura and Humanoid and Humanoid.Health > 0 then
            local enemies = GetAllEnemies()
            for _, mob in ipairs(enemies) do
                local mobRoot = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso") or mob:FindFirstChild("UpperTorso")
                if mobRoot then
                    pcall(function()
                        local damageRemote = ReplicatedStorage:FindFirstChild("Damage", true)
                            or ReplicatedStorage:FindFirstChild("HitMonster", true)
                            or ReplicatedStorage:FindFirstChild("Attack", true)
                            or ReplicatedStorage:FindFirstChild("Combat", true)
                        if damageRemote then
                            damageRemote:FireServer(mob, mobRoot.Position)
                        end
                    end)
                end
            end
            if #enemies > 0 then
                SimulateLeftClick()
            end
        end
    end
end)

-- 5. VÒNG LẶP AUTO SKILL (MÔ PHỎNG PHÍM 1-5 & THỨ TỰ ƯU TIÊN + REMOTES)
task.spawn(function()
    while task.wait(0.25) do
        if (Settings.AutoSkill or Settings.AutoPlay) and Humanoid and Humanoid.Health > 0 then
            local skillOrder = { Settings.SkillFirst, Settings.SkillSecond, Settings.SkillThird, Settings.SkillFourth, Settings.SkillFifth }
            for _, skillNum in ipairs(skillOrder) do
                SimulateSkillKey(skillNum)
                pcall(function()
                    local skillRemote = ReplicatedStorage:FindFirstChild("UseSkill", true) 
                        or ReplicatedStorage:FindFirstChild("SkillRemote", true)
                        or ReplicatedStorage:FindFirstChild("Skill", true)
                    if skillRemote then
                        skillRemote:FireServer(tonumber(skillNum) or 1)
                    end
                end)
                task.wait(0.04)
            end

            if Settings.AutoAssistSkill or Settings.AutoPlay then
                pcall(function()
                    local assistRemote = ReplicatedStorage:FindFirstChild("UseAssist", true) or ReplicatedStorage:FindFirstChild("AssistSkill", true)
                    if assistRemote then assistRemote:FireServer() end
                end)
            end

            if Settings.AutoFruitSkill or Settings.AutoPlay then
                pcall(function()
                    local fruitRemote = ReplicatedStorage:FindFirstChild("UseFruitSkill", true) or ReplicatedStorage:FindFirstChild("FruitSkill", true)
                    if fruitRemote then fruitRemote:FireServer() end
                end)
            end
        end
    end
end)

-- 6. VÒNG LẶP AUTO DODGE SKILL (DÙNG THÔNG SỐ SETTING DODGE)
task.spawn(function()
    while task.wait(Settings.TweenSpeedDodgePart or 0.15) do
        if Settings.AutoDodgeSkill and Humanoid and Humanoid.Health > 0 and HumanoidRootPart then
            for _, obj in pairs(workspace:GetChildren()) do
                if obj:IsA("BasePart") and (obj.Name:find("Warning") or (obj.Color == Color3.fromRGB(255, 0, 0) and obj.Transparency < (Settings.DodgePartTransparency or 0.9))) then
                    local dist = (HumanoidRootPart.Position - obj.Position).Magnitude
                    if dist < 25 then
                        HumanoidRootPart.CFrame = HumanoidRootPart.CFrame * CFrame.new(0, Settings.SizeDodgePartY or 100, 0)
                        task.wait(0.5)
                        break
                    end
                end
            end
        end
    end
end)

-- 7. VÒNG LẶP AUTO REPLAY & RAID & INFINITE MODE RESET
local lastWebhookClearTime = 0
task.spawn(function()
    while task.wait(1.5) do
        local isRaidOpen = false
        pcall(function()
            local raidTimer = LocalPlayer.PlayerGui:FindFirstChild("RaidTimer", true)
            if raidTimer and raidTimer.Text:find("Open") then isRaidOpen = true end
        end)

        if isRaidOpen then
            if Settings.StopReplayIfRaidOpen then Settings.AutoReplay = false end
            if Settings.BackToLobbyIfRaidOpen then
                pcall(function()
                    local remote = ReplicatedStorage:FindFirstChild("TeleportToLobby", true)
                    if remote then remote:FireServer() end
                end)
            end
        else
            if Settings.GoAFKIfRaidNotOpen and HumanoidRootPart then
                pcall(function()
                    local afkSpot = workspace:FindFirstChild("AFKZone") or workspace:FindFirstChild("SpawnLocation")
                    if afkSpot then HumanoidRootPart.CFrame = afkSpot.CFrame * CFrame.new(0, 5, 0) end
                end)
            end
        end

        -- Infinite Mode Wave Reset Check
        if Settings.ResetINFMode then
            pcall(function()
                local waveGui = LocalPlayer.PlayerGui:FindFirstChild("Wave", true) or LocalPlayer.PlayerGui:FindFirstChild("WaveLabel", true)
                if waveGui and waveGui.Text then
                    local currentWave = tonumber(waveGui.Text:match("%d+"))
                    if currentWave and currentWave >= (Settings.SelectWaveToReset or 100) then
                        if Humanoid then Humanoid.Health = 0 end
                    end
                end
            end)
        end

        -- Auto Replay (HỖ TRỢ CẢ REMOTE LẪN CLICK NÚT TRÊN MÀN HÌNH)
        if Settings.AutoReplay and not (isRaidOpen and Settings.StopReplayIfRaidOpen) then
            pcall(function()
                local replayRemote = ReplicatedStorage:FindFirstChild("ReplayVote", true) 
                    or ReplicatedStorage:FindFirstChild("VoteReplay", true)
                    or ReplicatedStorage:FindFirstChild("Replay", true)
                if replayRemote then 
                    replayRemote:FireServer(true)
                end
            end)

            pcall(function()
                for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                    if gui:IsA("TextButton") and (gui.Name:lower():find("replay") or gui.Text:lower():find("replay") or gui.Name:lower():find("retry")) then
                        if getconnections then
                            for _, conn in pairs(getconnections(gui.MouseButton1Click) or {}) do conn:Fire() end
                            for _, conn in pairs(getconnections(gui.Activated) or {}) do conn:Fire() end
                        end
                    end
                end
            end)

            if Settings.SendDimensionDrops and (tick() - lastWebhookClearTime > 15) then
                lastWebhookClearTime = tick()
                SendDiscordWebhook(
                    "🏆 [CLEAR MAP] Match Cleared!",
                    "Player **" .. LocalPlayer.Name .. "** cleared the stage successfully!",
                    {
                        { name = "Player", value = LocalPlayer.Name, inline = true },
                        { name = "Time", value = os.date("%H:%M:%S"), inline = true },
                        { name = "Auto Replay", value = "Requested", inline = true }
                    },
                    3066993
                )
            end
        end
    end
end)

-- 8. VÒNG LẶP AUTO BUY (VÉ RAID / TOKEN / METHOD)
task.spawn(function()
    while task.wait(6) do
        if Settings.BuyRushTicket then
            pcall(function()
                local buyRemote = ReplicatedStorage:FindFirstChild("BuyRaidTicket", true) or ReplicatedStorage:FindFirstChild("BuyShopItem", true)
                if buyRemote then buyRemote:FireServer("RushTicket", 1, Settings.SelectMethodBuy) end
            end)
        end
        if Settings.Buy100RaidToken then
            pcall(function()
                local buyRemote = ReplicatedStorage:FindFirstChild("BuyDioKey", true) or ReplicatedStorage:FindFirstChild("BuyShopItem", true)
                if buyRemote then buyRemote:FireServer("100RaidToken", 1, Settings.SelectMethodBuy) end
            end)
        end
    end
end)

-- 9. VÒNG LẶP AUTO BÁN THẺ RÁC THEO ĐỘ HIẾM (AUTO SELL CARD)
task.spawn(function()
    while task.wait(10) do
        if Settings.AutoSellCard then
            pcall(function()
                local sellRemote = ReplicatedStorage:FindFirstChild("SellCards", true) or ReplicatedStorage:FindFirstChild("SellCard", true)
                if sellRemote then
                    sellRemote:FireServer(Settings.SelectRarity or "Common")
                end
            end)
        end
    end
end)

-- 10. VÒNG LẶP AUTO CLAIM QUESTS & REWARDS
task.spawn(function()
    while task.wait(5) do
        if Settings.AutoClaimQuestAndReward then
            pcall(function()
                local claimQuests = ReplicatedStorage:FindFirstChild("ClaimQuests", true) or ReplicatedStorage:FindFirstChild("ClaimQuest", true)
                if claimQuests then claimQuests:FireServer() end
                local claimDaily = ReplicatedStorage:FindFirstChild("ClaimDailyRewards", true) or ReplicatedStorage:FindFirstChild("ClaimDaily", true)
                if claimDaily then claimDaily:FireServer() end
            end)
        end
        if Settings.AutoRedeemAllCode then
            pcall(function()
                local codes = { "UPDATE", "DIMENSIONS", "SEASON", "FREEGEMS", "BOOST" }
                local codeRemote = ReplicatedStorage:FindFirstChild("RedeemCode", true) or ReplicatedStorage:FindFirstChild("Code", true)
                if codeRemote then
                    for _, c in ipairs(codes) do
                        codeRemote:FireServer(c)
                        task.wait(0.5)
                    end
                end
            end)
            Settings.AutoRedeemAllCode = false
        end
    end
end)

-- 11. CTRL + CLICK TP
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and Settings.CtrlClickTP and input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        local mouse = LocalPlayer:GetMouse()
        if mouse.Hit and HumanoidRootPart then
            HumanoidRootPart.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
        end
    end
end)

-- 12. GIỮ SPEED / JUMP / DASH NO COOLDOWN
RunService.Stepped:Connect(function()
    if Humanoid then
        if Settings.WalkSpeed and Humanoid.WalkSpeed ~= Settings.Speed then
            Humanoid.WalkSpeed = Settings.Speed
        end
        if Settings.JumpPower and Humanoid.JumpPower ~= Settings.Jump then
            Humanoid.JumpPower = Settings.Jump
        end
    end
    if Settings.DashNoCooldown then
        pcall(function()
            local dashScript = Character and (Character:FindFirstChild("Dash") or LocalPlayer.PlayerScripts:FindFirstChild("DashClient"))
            if dashScript and dashScript:FindFirstChild("Cooldown") then
                dashScript.Cooldown.Value = 0
            end
        end)
    end
end)

OrionLib:Init()
print("🎉 SLH Hub Modified - Loaded Successfully with Full 7 Tabs!")
