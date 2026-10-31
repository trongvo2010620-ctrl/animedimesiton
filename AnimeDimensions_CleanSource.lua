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
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local LOBBY_PLACE_ID = 6379034480
local userIntentionalLeave = false -- Cờ đánh dấu người dùng chủ động Leave, chặn Rejoin tự động (CRIT-1, CRIT-3)
local currentActiveSlot = 1 -- Quản lý slot nhân vật hiện tại (1: Main, 2: First Assist) tránh spam remote đổi nhân vật

-- Quản lý vòng đời kết nối signals khi reload / stop script (LOW-2)
if _G.SLH_Connections then
    for _, conn in ipairs(_G.SLH_Connections) do
        pcall(function() conn:Disconnect() end)
    end
end
_G.SLH_Connections = {}

local function TrackConnection(conn)
    if not conn then return nil end
    table.insert(_G.SLH_Connections, conn)
    return conn
end

local function UntrackConnection(conn)
    if not conn then return nil end
    pcall(function() conn:Disconnect() end)
    if _G.SLH_Connections then
        for i = #_G.SLH_Connections, 1, -1 do
            if _G.SLH_Connections[i] == conn then
                table.remove(_G.SLH_Connections, i)
                break
            end
        end
    end
    return nil
end

local function ClearAllConnections()
    if _G.SLH_Connections then
        for _, conn in ipairs(_G.SLH_Connections) do
            pcall(function() conn:Disconnect() end)
        end
        _G.SLH_Connections = {}
    end
end

-- ===================================================================
-- 2. HỆ THỐNG CẤU HÌNH & TỰ ĐỘNG LƯU NGẦM 100% (ZERO ACTION AUTO-SAVE)
-- ĐƯỢC ĐẶT TRƯỚC TOÀN BỘ CÁC HÀM GETTER VÀ SỰ KIỆN CHARACTER
-- ===================================================================
local AutoSaveFile = "AnimeDimensions_AutoSave.json"

local Settings = {
    -- TAB 1: MAIN & FARMING
    MapSelection = "Auto",
    SelectDifficulty = "Easy",
    WaitOnLobbyAfterJoin = 10,
    WaitLobbyOnlyFirstTime = false,
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
    CustomRedeemCodes = "UPDATE, DIMENSIONS, SEASON, FREEGEMS, BOOST",
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
    SizeDodgePart = 25,
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

-- Tự động nạp cấu hình cũ ngay khi mở file (Kèm kiểm tra Validation Schema)
pcall(function()
    if readfile and isfile and isfile(AutoSaveFile) then
        local savedData = HttpService:JSONDecode(readfile(AutoSaveFile))
        if type(savedData) == "table" then
            for key, val in pairs(savedData) do
                if Settings[key] ~= nil then
                    if type(Settings[key]) == type(val) then
                        Settings[key] = val
                    elseif type(Settings[key]) == "string" and type(val) == "number" then
                        Settings[key] = tostring(val)
                    elseif type(Settings[key]) == "number" and type(val) == "string" then
                        local n = tonumber(val)
                        if n then Settings[key] = n end
                    end
                end
            end
            -- Kiểm tra và chuẩn hóa cấu hình phím skill (MED-9)
            local validSkills = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true }
            if not validSkills[tostring(Settings.SkillFirst)] then Settings.SkillFirst = "1" end
            if not validSkills[tostring(Settings.SkillSecond)] then Settings.SkillSecond = "2" end
            if not validSkills[tostring(Settings.SkillThird)] then Settings.SkillThird = "3" end
            if not validSkills[tostring(Settings.SkillFourth)] then Settings.SkillFourth = "4" end
            if not validSkills[tostring(Settings.SkillFifth)] then Settings.SkillFifth = "5" end

            print("⚡ [AutoSave]: Đã tự động khôi phục và kiểm tra schema toàn bộ cài đặt của bạn!")
        end
    end
end)

-- Áp dụng WhiteScreen ngay khi load cấu hình (MED-4)
if Settings.WhiteScreen then
    local wsOk, wsErr = pcall(function()
        RunService:Set3dRenderingEnabled(false)
    end)
    if not wsOk then
        warn("⚠️ [WhiteScreen] Executor không hỗ trợ Set3dRenderingEnabled: " .. tostring(wsErr))
    end
end

-- Hàm tự động lưu ngầm có Debounce 0.5s chống nghẽn ghi đĩa (Hỗ trợ lưu tức thì khi đóng & hủy race) (LOW-3)
local saveDebounce = false
local currentSaveToken = 0
local function AutoSave(immediate)
    currentSaveToken = currentSaveToken + 1
    local token = currentSaveToken
    if immediate then
        saveDebounce = false
        pcall(function()
            if writefile then
                writefile(AutoSaveFile, HttpService:JSONEncode(Settings))
            end
        end)
        return
    end
    if saveDebounce then return end
    saveDebounce = true
    task.delay(0.5, function()
        saveDebounce = false -- Luôn giải phóng cờ debounce khi hết 0.5s, không bao giờ kẹt khi token mismatch
        if currentSaveToken ~= token then return end
        pcall(function()
            if writefile then
                writefile(AutoSaveFile, HttpService:JSONEncode(Settings))
            end
        end)
    end)
end

-- BIẾN & HÀM QUẢN LÝ NHÂN VẬT (BÂY GIỜ ĐÃ THẤY SETTINGS ĐẦY ĐỦ)
local Character = LocalPlayer.Character
local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
local Humanoid = Character and Character:FindFirstChild("Humanoid")
local cachedHumanoid = Humanoid
local charParts = {}

local function UpdateCharParts(char)
    local parts = {}
    if char and char.Parent then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                table.insert(parts, p)
            end
        end
    end
    charParts = parts
end

-- HÀM LẤY NHÂN VẬT & ROOT DYNAMIC ĐẶT ĐẦU FILE (TOÀN BỘ CÁC TAB ĐỀU NHẬN DIỆN ĐƯỢC)
local function GetMyChar()
    local char = LocalPlayer.Character
    if char then Character = char end
    return char
end

local function GetMyRoot()
    local char = GetMyChar()
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart") 
        or char.PrimaryPart 
        or char:FindFirstChild("Torso") 
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChildWhichIsA("BasePart")
    if root then HumanoidRootPart = root end
    return root
end

local function GetMyHumanoid()
    local char = GetMyChar()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then Humanoid = hum end
    return hum
end

local function ApplyHideName(v)
    pcall(function()
        local char = GetMyChar()
        if char then
            for _, gui in pairs(char:GetDescendants()) do
                if gui:IsA("BillboardGui") then
                    local isNameTag = false
                    local gName = gui.Name:lower()
                    if gName:find("name") or gName:find("tag") or gName:find("title") or gName:find("user") then
                        isNameTag = true
                    else
                        for _, lbl in ipairs(gui:GetChildren()) do
                            if lbl:IsA("TextLabel") and (lbl.Text == LocalPlayer.Name or lbl.Text == LocalPlayer.DisplayName) then
                                isNameTag = true
                                break
                            end
                        end
                    end
                    if isNameTag then
                        gui.Enabled = not v
                    end
                end
            end
        end
        -- Hỗ trợ thêm Name Tag nằm trong PlayerGui có Adornee trỏ vào nhân vật (LOW-5)
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, gui in ipairs(pg:GetChildren()) do
                if gui:IsA("BillboardGui") and (gui.Adornee == char or (char and gui.Adornee and gui.Adornee:IsDescendantOf(char))) then
                    gui.Enabled = not v
                end
            end
        end
    end)
end

local charChildConnection = nil
local function SetupCharacter(char)
    if not char then return end
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5) or char:FindFirstChild("HumanoidRootPart")
    Humanoid = char:WaitForChild("Humanoid", 5) or char:FindFirstChild("Humanoid")
    cachedHumanoid = Humanoid
    
    -- Delay 1s để toàn bộ phụ kiện/vũ khí load đầy đủ trước khi cache noclip (Kiểm tra nhân vật còn sống tránh bug reset)
    task.delay(1, function()
        if LocalPlayer.Character == char and char.Parent then
            UpdateCharParts(char)
        end
    end)

    -- Quản lý 1 connection duy nhất cho ChildAdded mỗi nhân vật, giải phóng triệt để và xóa khỏi mảng theo dõi khi respawn (ngăn ngừa rò rỉ RAM)
    if charChildConnection then
        charChildConnection = UntrackConnection(charChildConnection)
    end
    charChildConnection = TrackConnection(char.ChildAdded:Connect(function(child)
        if not Settings.DisableNoclip then
            if child:IsA("BasePart") then
                table.insert(charParts, child)
            elseif child:IsA("Model") or child:IsA("Tool") or child:IsA("Accessory") then
                for _, p in ipairs(child:GetDescendants()) do
                    if p:IsA("BasePart") then
                        table.insert(charParts, p)
                    end
                end
            end
        end
    end))

    if Settings.HideName then
        task.spawn(function()
            task.wait(0.5)
            ApplyHideName(true)
        end)
    end
end

if Character then
    task.spawn(function()
        SetupCharacter(Character)
    end)
end

TrackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    currentActiveSlot = 1 -- Khi respawn, game luôn tự động chuyển về nhân vật chính (slot 1)
    SetupCharacter(char)
end))

-- 1. CHỐNG VĂNG GAME KHI TREO MÁY (ANTI-AFK CHUẨN)
task.spawn(function()
    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(LocalPlayer.Idled) or {}) do
                pcall(function() conn:Disable() end)
            end
        end
    end)
    TrackConnection(LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(0.2)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end)
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait(0.1)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
    end))
end)

-- ===================================================================
-- HÀM GỬI DISCORD WEBHOOK THÔNG MINH (CÓ RATE LIMIT BACKOFF & VALIDATION)
-- ===================================================================
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (Fluxus and Fluxus.request)
local webhookBlockedUntil = 0

local function SendDiscordWebhook(title, description, fields, color)
    if not Settings.WebhookURL or Settings.WebhookURL == "" then return end
    if not (Settings.WebhookURL:find("discord%.com/api/webhooks/") or Settings.WebhookURL:find("discordapp%.com/api/webhooks/")) then return end
    if not httpRequest then return end
    if os.clock() < webhookBlockedUntil then return end

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
        local res = httpRequest({
            Url = Settings.WebhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
        if res and res.StatusCode == 429 then
            webhookBlockedUntil = os.clock() + 60
        end
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

local ToggleAutoMob, ToggleAutoMelee, ToggleKillAura, ToggleAutoSkill, ToggleAutoAssistSkill, ToggleAutoFruitSkill, ToggleAutoReplay, ToggleAutoSelectMap

MainTab:AddDropdown({
    Name = "MapSelection(AutoUpdate!)",
    Default = Settings.MapSelection,
    Options = { "Auto", "Titan Dimension", "Demon Dimension", "Curse Dimension", "Villain Dimension", "Sword Dimension", "Ghoul Dimension", "Fate Dimension", "Slime Dimension", "Devil Dimension", "Pirate Dimension", "Alien Dimension", "Giant Dimension", "Shadow Dimension", "Esper Dimension", "Soul Dimension" },
    Callback = function(v)
        Settings.MapSelection = v
        AutoSave()
    end
})

MainTab:AddDropdown({
    Name = "SelectDifficulty",
    Default = Settings.SelectDifficulty,
    Options = { "Easy", "Hard", "Nightmare" },
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
    Name = "WaitLobbyOnlyFirstTime",
    Default = Settings.WaitLobbyOnlyFirstTime,
    Callback = function(v)
        Settings.WaitLobbyOnlyFirstTime = v
        AutoSave()
    end
})

local previousSettingsBeforeAutoPlay = nil
local userManuallyOverrodeReplay = false
local autoSettingInProgress = false

local function ProgrammaticSetToggle(toggle, value)
    autoSettingInProgress = true
    pcall(function()
        if toggle and toggle.Set then
            toggle:Set(value)
        end
    end)
    task.delay(0.1, function()
        autoSettingInProgress = false
    end)
end

MainTab:AddToggle({
    Name = "AutoPlay",
    Default = Settings.AutoPlay,
    Callback = function(v)
        Settings.AutoPlay = v
        if v then
            previousSettingsBeforeAutoPlay = {
                AutoMob = Settings.AutoMob,
                AutoMelee = Settings.AutoMelee,
                KillAura = Settings.KillAura,
                AutoSkill = Settings.AutoSkill,
                AutoAssistSkill = Settings.AutoAssistSkill,
                AutoFruitSkill = Settings.AutoFruitSkill,
                AutoReplay = Settings.AutoReplay,
                AutoSelectMap = Settings.AutoSelectMap
            }
            Settings.AutoMob = true
            Settings.AutoMelee = true
            Settings.KillAura = false
            Settings.AutoSkill = true
            Settings.AutoAssistSkill = true
            Settings.AutoFruitSkill = true
            Settings.AutoReplay = true

            ProgrammaticSetToggle(ToggleAutoMob, true)
            ProgrammaticSetToggle(ToggleAutoMelee, true)
            ProgrammaticSetToggle(ToggleKillAura, false)
            ProgrammaticSetToggle(ToggleAutoSkill, true)
            ProgrammaticSetToggle(ToggleAutoAssistSkill, true)
            ProgrammaticSetToggle(ToggleAutoFruitSkill, true)
            ProgrammaticSetToggle(ToggleAutoReplay, true)

            -- Chỉ ép AutoSelectMap nếu người dùng để MapSelection là Auto (MED-8)
            if Settings.MapSelection == "Auto" then
                Settings.AutoSelectMap = true
                ProgrammaticSetToggle(ToggleAutoSelectMap, true)
            end
        else
            -- Khôi phục chính xác cài đặt trước khi bật AutoPlay (CRIT-4)
            if previousSettingsBeforeAutoPlay then
                Settings.AutoMob = previousSettingsBeforeAutoPlay.AutoMob
                Settings.AutoMelee = previousSettingsBeforeAutoPlay.AutoMelee
                Settings.KillAura = previousSettingsBeforeAutoPlay.KillAura
                Settings.AutoSkill = previousSettingsBeforeAutoPlay.AutoSkill
                Settings.AutoAssistSkill = previousSettingsBeforeAutoPlay.AutoAssistSkill
                Settings.AutoFruitSkill = previousSettingsBeforeAutoPlay.AutoFruitSkill
                Settings.AutoReplay = previousSettingsBeforeAutoPlay.AutoReplay
                Settings.AutoSelectMap = previousSettingsBeforeAutoPlay.AutoSelectMap

                ProgrammaticSetToggle(ToggleAutoMob, Settings.AutoMob)
                ProgrammaticSetToggle(ToggleAutoMelee, Settings.AutoMelee)
                ProgrammaticSetToggle(ToggleKillAura, Settings.KillAura)
                ProgrammaticSetToggle(ToggleAutoSkill, Settings.AutoSkill)
                ProgrammaticSetToggle(ToggleAutoAssistSkill, Settings.AutoAssistSkill)
                ProgrammaticSetToggle(ToggleAutoFruitSkill, Settings.AutoFruitSkill)
                ProgrammaticSetToggle(ToggleAutoReplay, Settings.AutoReplay)
                ProgrammaticSetToggle(ToggleAutoSelectMap, Settings.AutoSelectMap)
                previousSettingsBeforeAutoPlay = nil
            end
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

ToggleAutoReplay = MainTab:AddToggle({
    Name = "AutoReplay",
    Default = Settings.AutoReplay,
    Callback = function(v)
        Settings.AutoReplay = v
        if not autoSettingInProgress then
            userManuallyOverrodeReplay = true -- CRIT-1: Chỉ đánh dấu khi user tự tay bấm
        end
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

ToggleAutoSelectMap = MainTab:AddToggle({
    Name = "AutoSelectMap(DetectedLevel)",
    Default = Settings.AutoSelectMap,
    Callback = function(v)
        Settings.AutoSelectMap = v
        AutoSave()
    end
})

MainTab:AddSection({ Name = "Combat & Movement" })

MainTab:AddTextbox({
    Name = "TweenSpeed (>=500: Instant, <500: Smooth)",
    Default = tostring(Settings.TweenSpeed),
    TextDisappear = false,
    Callback = function(v)
        Settings.TweenSpeed = tonumber(v) or 500
        AutoSave()
    end
})

ToggleAutoMob = MainTab:AddToggle({
    Name = "AutoMob",
    Default = Settings.AutoMob,
    Callback = function(v)
        Settings.AutoMob = v
        AutoSave()
    end
})

ToggleKillAura = MainTab:AddToggle({
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

ToggleAutoSkill = MainTab:AddToggle({
    Name = "AutoSkill",
    Default = Settings.AutoSkill,
    Callback = function(v)
        Settings.AutoSkill = v
        AutoSave()
    end
})

ToggleAutoAssistSkill = MainTab:AddToggle({
    Name = "AutoAssistSkill",
    Default = Settings.AutoAssistSkill,
    Callback = function(v)
        Settings.AutoAssistSkill = v
        AutoSave()
    end
})

ToggleAutoFruitSkill = MainTab:AddToggle({
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
        if v == "Skill" then
            Settings.AutoMelee = false
            ProgrammaticSetToggle(ToggleAutoMelee, false) -- Dùng ProgrammaticSetToggle nhất quán (LOW-1)
            -- Bật AutoSkill để đảm bảo skill luôn được tung ra khi chọn chế độ Skill (CRIT-2)
            Settings.AutoSkill = true
            ProgrammaticSetToggle(ToggleAutoSkill, true)
        else
            Settings.AutoMelee = true
            ProgrammaticSetToggle(ToggleAutoMelee, true)
        end
        AutoSave()
    end
})

ToggleAutoMelee = MainTab:AddToggle({
    Name = "AutoMelee",
    Default = Settings.AutoMelee,
    Callback = function(v)
        Settings.AutoMelee = v
        AutoSave()
    end
})

-- Khởi tạo đồng bộ khi AutoPlay được bật từ file lưu trước đó (HIGH-5, CRIT-2: lưu cấu hình trước khi ép bật)
if Settings.AutoPlay then
    previousSettingsBeforeAutoPlay = {
        AutoMob = Settings.AutoMob,
        AutoMelee = Settings.AutoMelee,
        KillAura = Settings.KillAura,
        AutoSkill = Settings.AutoSkill,
        AutoAssistSkill = Settings.AutoAssistSkill,
        AutoFruitSkill = Settings.AutoFruitSkill,
        AutoReplay = Settings.AutoReplay,
        AutoSelectMap = Settings.AutoSelectMap
    }
    Settings.AutoMob = true
    Settings.AutoMelee = true
    Settings.KillAura = false
    Settings.AutoSkill = true
    Settings.AutoAssistSkill = true
    Settings.AutoFruitSkill = true
    Settings.AutoReplay = true
    if Settings.MapSelection == "Auto" then Settings.AutoSelectMap = true end
    task.spawn(function()
        task.wait(0.5)
        ProgrammaticSetToggle(ToggleAutoMob, true)
        ProgrammaticSetToggle(ToggleAutoMelee, true)
        ProgrammaticSetToggle(ToggleKillAura, false)
        ProgrammaticSetToggle(ToggleAutoSkill, true)
        ProgrammaticSetToggle(ToggleAutoAssistSkill, true)
        ProgrammaticSetToggle(ToggleAutoFruitSkill, true)
        ProgrammaticSetToggle(ToggleAutoReplay, true)
        if Settings.MapSelection == "Auto" then ProgrammaticSetToggle(ToggleAutoSelectMap, true) end
    end)
end

MainTab:AddTextbox({
    Name = "FarmDistance(OnlyNumber)",
    Default = tostring(Settings.FarmDistance or 7),
    TextDisappear = false,
    Callback = function(v)
        Settings.FarmDistance = tonumber(v) or 7
        AutoSave()
    end
})

MainTab:AddDropdown({
    Name = "FarmPosition",
    Default = Settings.FarmPosition or "Above",
    Options = { "Above", "Behind" },
    Callback = function(v)
        Settings.FarmPosition = v
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
    Options = { "Auto", "Fluffy Raid", "Beast Raid", "Chainsaw Raid", "King of Curses Raid", "Infinite Shiro Raid", "Combat Giant Raid", "Red Emperor Raid", "Sun God Sora Raid", "Warlord Raid", "Tengu Raid", "Hime Raid", "Dark One Hero Raid" },
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

local function ReturnToLobby()
    AutoSave(true)
    local method = Settings.GoLobbyMethod or "TeleportToLobby"
    if method == "Leave" then
        -- Đánh dấu chủ động Leave để TriggerRejoin không bắt sự kiện Rejoin tự động (CRIT-1, CRIT-3, MED-5, MED-7)
        userIntentionalLeave = true
        pcall(function() game:Shutdown() end)
        task.delay(0.2, function()
            local ok, err = pcall(function() LocalPlayer:Kick("Leaving game via SLH Hub...") end)
            if not ok then
                warn("⚠️ [Leave]: LocalPlayer:Kick bị giới hạn (" .. tostring(err) .. "), chuyển hướng Teleport về sảnh...")
                pcall(function() TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer) end)
            end
        end)
    elseif method == "Reconnect" then
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
    else
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("TeleportToLobby", true) 
                or ReplicatedStorage:FindFirstChild("ReturnLobby", true)
            if remote then
                remote:FireServer()
                task.delay(3, function()
                    if game.PlaceId ~= LOBBY_PLACE_ID then
                        TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
                    end
                end)
            else
                TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
            end
        end)
    end
end

MoreTab:AddButton({
    Name = "Return To Lobby",
    Callback = function()
        ReturnToLobby()
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

local originalTransparencies = setmetatable({}, { __mode = "k" })
local autoDeleteMapToken = 0
local autoDeleteMapConnection = nil
MoreTab:AddToggle({
    Name = "AutoDeleteMap",
    Default = Settings.AutoDeleteMap,
    Callback = function(v)
        Settings.AutoDeleteMap = v
        autoDeleteMapToken = autoDeleteMapToken + 1
        local currentToken = autoDeleteMapToken

        -- Hủy hook cũ nếu có và xóa khỏi mảng theo dõi kết nối
        if autoDeleteMapConnection then
            autoDeleteMapConnection = UntrackConnection(autoDeleteMapConnection)
        end

        -- Tự động ẩn texture/particle của quái mới spawn ngay lập tức (Track qua TrackConnection để dọn sạch khi reload kịch bản)
        if v then
            autoDeleteMapConnection = TrackConnection(workspace.DescendantAdded:Connect(function(obj)
                if not Settings.AutoDeleteMap then return end
                pcall(function()
                    if obj:IsA("Decal") or obj:IsA("Texture") then
                        if originalTransparencies[obj] == nil then
                            originalTransparencies[obj] = obj.Transparency
                        end
                        obj.Transparency = 1
                    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                        obj.Enabled = false
                    end
                end)
            end))
        end

        task.spawn(function()
            pcall(function()
                -- Prune dead keys an toàn, tránh văng lỗi 'Property Parent is locked' (Bug 1)
                for k in pairs(originalTransparencies) do
                    local ok, parent = pcall(function() return k.Parent end)
                    if not ok or not parent then
                        originalTransparencies[k] = nil
                    end
                end

                local descendants = workspace:GetDescendants()
                local count = 0
                for _, obj in ipairs(descendants) do
                    if autoDeleteMapToken ~= currentToken then return end -- Hủy task cũ tránh xung đột race condition (HIGH-1)
                    count = count + 1
                    if count % 500 == 0 then task.wait() end -- Tăng tốc batch 500 cho map lớn (MED-6)
                    if obj:IsA("Decal") or obj:IsA("Texture") then
                        if v then
                            if originalTransparencies[obj] == nil then
                                originalTransparencies[obj] = obj.Transparency
                            end
                            obj.Transparency = 1
                        else
                            if originalTransparencies[obj] ~= nil then
                                obj.Transparency = originalTransparencies[obj]
                            else
                                obj.Transparency = 0
                            end
                        end
                    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                        obj.Enabled = not v
                    end
                end
            end)
        end)
        AutoSave()
    end
})

local ToggleAutoRedeem; ToggleAutoRedeem = MoreTab:AddToggle({
    Name = "AutoRedeemAllCode",
    Default = Settings.AutoRedeemAllCode,
    Callback = function(v)
        Settings.AutoRedeemAllCode = v
        AutoSave()
    end
})

MoreTab:AddTextbox({
    Name = "Custom Codes (Separated by comma)",
    Default = Settings.CustomRedeemCodes or "UPDATE, DIMENSIONS, SEASON, FREEGEMS, BOOST",
    TextDisappear = false,
    Callback = function(v)
        Settings.CustomRedeemCodes = v
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
        ApplyHideName(v)
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
        if v then
            pcall(function()
                local char = GetMyChar()
                if char then
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                            p.CanCollide = true
                        end
                    end
                end
            end)
        end
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

local hasEquippedCharacter = false
local lastEquippedCardMode = ""

CharTab:AddToggle({
    Name = "AutoEquip Character",
    Default = Settings.AutoEquipCharacter,
    Callback = function(v)
        Settings.AutoEquipCharacter = v
        if v then hasEquippedCharacter = false end
        AutoSave()
    end
})

local ToggleAutoResetToMain, ToggleAutoResetToFirstAssist

ToggleAutoResetToMain = CharTab:AddToggle({
    Name = "Auto Reset To Main",
    Default = Settings.AutoResetToMain,
    Callback = function(v)
        Settings.AutoResetToMain = v
        if v then
            Settings.AutoResetToFirstAssist = false
            ProgrammaticSetToggle(ToggleAutoResetToFirstAssist, false)
            -- Chỉ gửi Remote nếu hiện tại không phải là Slot 1, tránh spam gây lag/kick
            if currentActiveSlot ~= 1 then
                pcall(function()
                    local switchRemote = ReplicatedStorage:FindFirstChild("SwitchCharacter", true) 
                        or ReplicatedStorage:FindFirstChild("ChangeCharacter", true)
                    if switchRemote then
                        switchRemote:FireServer(1)
                        currentActiveSlot = 1
                    end
                end)
            end
        end
        AutoSave()
    end
})

ToggleAutoResetToFirstAssist = CharTab:AddToggle({
    Name = "Auto Reset To First Assist",
    Default = Settings.AutoResetToFirstAssist,
    Callback = function(v)
        Settings.AutoResetToFirstAssist = v
        if v then
            Settings.AutoResetToMain = false
            ProgrammaticSetToggle(ToggleAutoResetToMain, false)
            -- Chỉ gửi Remote nếu hiện tại không phải là Slot 2, tránh spam gây lag/kick
            if currentActiveSlot ~= 2 then
                pcall(function()
                    local switchRemote = ReplicatedStorage:FindFirstChild("SwitchCharacter", true) 
                        or ReplicatedStorage:FindFirstChild("ChangeCharacter", true)
                    if switchRemote then
                        switchRemote:FireServer(2)
                        currentActiveSlot = 2
                    end
                end)
            end
        end
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
        if v then lastEquippedCardMode = "" end
        AutoSave()
    end
})

CharTab:AddDropdown({
    Name = "EquipBestCardMode",
    Default = Settings.EquipBestCardMode,
    Options = { "Damage/Crit", "Cooldown", "Health/Defense" },
    Callback = function(v)
        Settings.EquipBestCardMode = v
        lastEquippedCardMode = ""
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
    Name = "SizeDodgePart (Studs Radius)",
    Default = tostring(Settings.SizeDodgePart),
    TextDisappear = false,
    Callback = function(v)
        Settings.SizeDodgePart = tonumber(v) or 25
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
        if not Settings.WebhookURL or not (Settings.WebhookURL:find("discord%.com/api/webhooks/") or Settings.WebhookURL:find("discordapp%.com/api/webhooks/")) then
            OrionLib:MakeNotification({
                Name = "Webhook Error",
                Content = "Vui lòng nhập đúng định dạng Discord Webhook URL (discord.com/api/webhooks/)!",
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
        local hum = GetMyHumanoid()
        if Settings.WalkSpeed and hum then hum.WalkSpeed = Settings.Speed end
        AutoSave()
    end
})

MiscTab:AddTextbox({
    Name = "Jump",
    Default = tostring(Settings.Jump),
    TextDisappear = false,
    Callback = function(v)
        Settings.Jump = tonumber(v) or 50
        local hum = GetMyHumanoid()
        if Settings.JumpPower and hum then hum.JumpPower = Settings.Jump end
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "WalkSpeed",
    Default = Settings.WalkSpeed,
    Callback = function(v)
        Settings.WalkSpeed = v
        local hum = GetMyHumanoid()
        if hum then hum.WalkSpeed = v and Settings.Speed or 16 end
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "JumpPower",
    Default = Settings.JumpPower,
    Callback = function(v)
        Settings.JumpPower = v
        local hum = GetMyHumanoid()
        if hum then hum.JumpPower = v and Settings.Jump or 50 end
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
        pcall(function()
            for _, g in ipairs(CoreGui:GetDescendants()) do
                if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                    g.Enabled = not v
                end
            end
        end)
        AutoSave(true)
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
        pcall(function()
            for _, p in pairs(workspace:GetDescendants()) do
                if p:IsA("ProximityPrompt") then
                    pcall(function() fireproximityprompt(p) end)
                end
            end
        end)
    end
})

MiscTab:AddButton({
    Name = "InstantProximityPrompt",
    Callback = function()
        pcall(function()
            for _, p in pairs(workspace:GetDescendants()) do
                if p:IsA("ProximityPrompt") then
                    pcall(function() p.HoldDuration = 0 end)
                end
            end
        end)
    end
})

MiscTab:AddSection({ Name = "Section2" })

-- HỆ THỐNG STAT GUI & CREDIT GUI ĐỒ HỌA TRỰC QUAN (GIỮ NGUYÊN VỊ TRÍ KHI KÉO VÀ TÍNH GIỜ CHUẨN XÁC)
local statGuiInstance = nil
local creditGuiInstance = nil
local statGuiStartTime = nil
local lastStatGuiPos = nil
local statGuiPosConn = nil

local function UpdateStatGui(forcePosition)
    if not Settings.StatGui then
        if statGuiPosConn then
            statGuiPosConn = UntrackConnection(statGuiPosConn)
        end
        if statGuiInstance then
            statGuiInstance:Destroy()
            statGuiInstance = nil
        end
        statGuiStartTime = nil -- Reset timer khi tắt để lần bật tiếp theo tính từ 0 (LOW-4)
        return
    end

    if not statGuiStartTime then
        statGuiStartTime = os.clock()
    end

    if not statGuiInstance then
        pcall(function()
            local old = CoreGui:FindFirstChild("SLH_StatGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("SLH_StatGui"))
            if old then old:Destroy() end
        end)
        local sg = Instance.new("ScreenGui")
        sg.Name = "SLH_StatGui"
        sg.ResetOnSpawn = false
        pcall(function()
            if syn and syn.protect_gui then syn.protect_gui(sg) end
            sg.Parent = CoreGui
        end)
        if not sg.Parent then sg.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, 220, 0, 115)
        frame.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
        frame.BorderColor3 = Color3.fromRGB(0, 170, 255)
        frame.BorderSizePixel = 1
        frame.Active = true
        frame.Draggable = true
        -- Giữ nguyên vị trí kéo của người dùng khi bật/tắt (MED-5, LOW-4)
        if lastStatGuiPos then
            frame.Position = lastStatGuiPos
        elseif Settings.StatGuiPosition == "Left" then
            frame.Position = UDim2.new(0, 20, 0, 150)
        else
            frame.Position = UDim2.new(1, -240, 0, 150)
        end
        if statGuiPosConn then
            statGuiPosConn = UntrackConnection(statGuiPosConn)
        end
        statGuiPosConn = TrackConnection(frame:GetPropertyChangedSignal("Position"):Connect(function()
            lastStatGuiPos = frame.Position
        end))
        frame.Parent = sg

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 24)
        title.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
        title.BorderSizePixel = 0
        title.Text = "⚡ SLH STATS"
        title.TextColor3 = Color3.fromRGB(0, 200, 255)
        title.TextSize = 13
        title.Font = Enum.Font.GothamBold
        title.Parent = frame

        local content = Instance.new("TextLabel")
        content.Name = "Content"
        content.Size = UDim2.new(1, -16, 1, -28)
        content.Position = UDim2.new(0, 8, 0, 26)
        content.BackgroundTransparency = 1
        content.TextColor3 = Color3.fromRGB(220, 220, 220)
        content.TextSize = 12
        content.Font = Enum.Font.Gotham
        content.TextXAlignment = Enum.TextXAlignment.Left
        content.TextYAlignment = Enum.TextYAlignment.Top
        content.Parent = frame

        statGuiInstance = sg
    elseif forcePosition and statGuiInstance:FindFirstChild("MainFrame") then
        local frame = statGuiInstance.MainFrame
        if Settings.StatGuiPosition == "Left" then
            frame.Position = UDim2.new(0, 20, 0, 150)
        else
            frame.Position = UDim2.new(1, -240, 0, 150)
        end
    end
end

local function UpdateCreditGui(forcePosition)
    if not Settings.CreditGui then
        if creditGuiInstance then
            creditGuiInstance:Destroy()
            creditGuiInstance = nil
        end
        return
    end

    if not creditGuiInstance then
        pcall(function()
            local old = CoreGui:FindFirstChild("SLH_CreditGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("SLH_CreditGui"))
            if old then old:Destroy() end
        end)
        local sg = Instance.new("ScreenGui")
        sg.Name = "SLH_CreditGui"
        sg.ResetOnSpawn = false
        pcall(function()
            if syn and syn.protect_gui then syn.protect_gui(sg) end
            sg.Parent = CoreGui
        end)
        if not sg.Parent then sg.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, 260, 0, 48)
        frame.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
        frame.BorderColor3 = Color3.fromRGB(0, 255, 180)
        frame.BorderSizePixel = 1
        frame.Active = true
        frame.Draggable = true
        if Settings.CreditGuiPosition == "Right" then
            frame.Position = UDim2.new(1, -280, 1, -70)
        else
            frame.Position = UDim2.new(0, 20, 1, -70)
        end
        frame.Parent = sg

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0.5, 0)
        title.BackgroundTransparency = 1
        title.Text = "⚡ SLH Hub Modified Pro"
        title.TextColor3 = Color3.fromRGB(0, 255, 200)
        title.TextSize = 13
        title.Font = Enum.Font.GothamBold
        title.Parent = frame

        local sub = Instance.new("TextLabel")
        sub.Size = UDim2.new(1, 0, 0.5, 0)
        sub.Position = UDim2.new(0, 0, 0.5, 0)
        sub.BackgroundTransparency = 1
        sub.Text = "Discord: discord.gg/smelllikehacker"
        sub.TextColor3 = Color3.fromRGB(180, 180, 180)
        sub.TextSize = 11
        sub.Font = Enum.Font.Gotham
        sub.Parent = frame

        creditGuiInstance = sg
    elseif forcePosition and creditGuiInstance:FindFirstChild("MainFrame") then
        local frame = creditGuiInstance.MainFrame
        if Settings.CreditGuiPosition == "Right" then
            frame.Position = UDim2.new(1, -280, 1, -70)
        else
            frame.Position = UDim2.new(0, 20, 1, -70)
        end
    end
end

MiscTab:AddDropdown({
    Name = "StatGuiPosition",
    Default = Settings.StatGuiPosition,
    Options = { "Right", "Left" },
    Callback = function(v)
        Settings.StatGuiPosition = v
        UpdateStatGui(true)
        AutoSave()
    end
})

MiscTab:AddDropdown({
    Name = "CreditGuiPosition",
    Default = Settings.CreditGuiPosition,
    Options = { "Left", "Right" },
    Callback = function(v)
        Settings.CreditGuiPosition = v
        UpdateCreditGui(true)
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "StatGui",
    Default = Settings.StatGui,
    Callback = function(v)
        Settings.StatGui = v
        UpdateStatGui(false)
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "CreditGui",
    Default = Settings.CreditGui,
    Callback = function(v)
        Settings.CreditGui = v
        UpdateCreditGui(false)
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
        local success, err = pcall(function()
            RunService:Set3dRenderingEnabled(not v)
        end)
        if not success then
            warn("Executor does not support Set3dRenderingEnabled: " .. tostring(err))
        end
        AutoSave()
    end
})

MiscTab:AddButton({
    Name = "infiniteyield",
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))()
        end)
    end
})

MiscTab:AddButton({
    Name = "ResetCamera",
    Callback = function()
        pcall(function()
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
            local myHum = GetMyHumanoid() or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
            if myHum then
                workspace.CurrentCamera.CameraSubject = myHum
            end
        end)
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

-- 1. HỆ THỐNG AUTO REJOIN KHI BỊ KICK / MẤT KẾT NỐI (CÓ REENTRY GUARD & AUTO RESET KHI LỖI TELEPORT)
local isRejoining = false
local function TriggerRejoin()
    if userIntentionalLeave then return end -- Chặn tự động rejoin khi người dùng chủ động chọn Leave (CRIT-1, CRIT-3)
    if isRejoining then return end
    if not Settings.RejoinIfGotKick then return end
    isRejoining = true
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
                repeat task.wait() until game:IsLoaded()
                pcall(function()
                    loadstring(game:HttpGet("https://raw.githubusercontent.com/trongvo2010620-ctrl/animedimesiton/main/AnimeDimensions_CleanSource.lua"))()
                end)
            ]])
        end)
    end

    task.wait(3)
    AutoSave(true)
    local success, err = pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
    if not success then
        warn("⚠️ TeleportService:Teleport thất bại: " .. tostring(err))
    end
    -- Reset guard sau 10s nếu teleport thất bại tránh kẹt vĩnh viễn (CRIT-1)
    task.delay(10, function()
        isRejoining = false
    end)
end

TrackConnection(GuiService.ErrorMessageChanged:Connect(function()
    if userIntentionalLeave then return end
    pcall(function()
        local msg = ""
        pcall(function() msg = GuiService:GetErrorMessage():lower() end)
        if msg ~= "" and (msg:find("kick") or msg:find("disconnect") or msg:find("removed") or msg:find("lost connection") or msg:find("timed out") or msg:find("reconnect") or msg:find("unexpected")) then
            TriggerRejoin()
        end
    end)
end))

pcall(function()
    local promptOverlay = CoreGui:WaitForChild("RobloxPromptGui", 5):WaitForChild("promptOverlay", 5)
    if promptOverlay then
        TrackConnection(promptOverlay.ChildAdded:Connect(function(child)
            if userIntentionalLeave then return end
            if child.Name == "ErrorPrompt" then
                TriggerRejoin()
            end
        end))
    end
end)

-- ===================================================================
-- 🔄 LOGIC CORE CHẠY NGẦM ĐẦY ĐỦ (COMPLETE EXECUTION ENGINES)
-- ===================================================================

-- HÀM MÔ PHỎNG CLICK CHUỘT THẬT (TỰ ĐỘNG CHỌN 1 PHƯƠNG THỨC TỐI ƯU NHẤT TRÁNH NHÂN ĐÔI CLICK & TỰ ĐỘNG RE-TEST)
local preferredClickMethod = nil
local lastClickMethodTest = 0

local function SimulateLeftClick()
    local now = os.clock()
    -- Re-test phương thức click mỗi 60 giây để thích ứng kịp thời khi đổi môi trường (MED-7)
    if now - lastClickMethodTest > 60 then
        preferredClickMethod = nil
        lastClickMethodTest = now
    end

    if preferredClickMethod == "VIM" then
        local ok = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
        if ok then return else preferredClickMethod = nil end
    elseif preferredClickMethod == "VU" then
        local ok = pcall(function()
            VirtualUser:Button1Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            VirtualUser:Button1Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end)
        if ok then return else preferredClickMethod = nil end
    elseif preferredClickMethod == "M1" then
        if mouse1click then
            local ok = pcall(mouse1click)
            if ok then return end
        end
        preferredClickMethod = nil
    end

    local s1 = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
    if s1 then
        preferredClickMethod = "VIM"
        return
    end

    local s2 = pcall(function()
        VirtualUser:Button1Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        VirtualUser:Button1Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
    if s2 then
        preferredClickMethod = "VU"
        return
    end

    if mouse1click then
        local s3 = pcall(mouse1click)
        if s3 then
            preferredClickMethod = "M1"
            return
        end
    end
end

-- HÀM MÔ PHỎNG BẤM PHÍM SKILL (1, 2, 3, 4, 5) - CHỐNG DOUBLE-FIRE VÀ CÓ ĐẦY ĐỦ DỰ PHÒNG (CRIT-1)
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
        local fired = false
        pcall(function()
            if VirtualInputManager and VirtualInputManager.SendKeyEvent then
                VirtualInputManager:SendKeyEvent(true, kc, false, game)
                task.wait(0.02)
                VirtualInputManager:SendKeyEvent(false, kc, false, game)
                fired = true
            end
        end)
        -- Chỉ kích hoạt keypress dự phòng nếu VIM thất bại (CRIT-1: tránh double-fire)
        if not fired then
            pcall(function()
                if keypress and keyrelease then
                    keypress(kc.Value)
                    task.wait(0.02)
                    keyrelease(kc.Value)
                    fired = true
                end
            end)
        end
        if not fired and VirtualUser then
            pcall(function()
                VirtualUser:CaptureController()
            end)
        end
    end
end

-- HÀM KIỂM TRA MÁU AN TOÀN CHỐNG VĂNG RUNTIME LỖI NẾU 'Health' LÀ PART/FOLDER HITBOX
local function CheckIsAlive(model, hum)
    if hum and hum.Health and hum.Health > 0 then
        return true
    end
    if not model then return false end
    local hp = model:FindFirstChild("Health") or model:FindFirstChild("HP") or model:GetAttribute("Health") or model:GetAttribute("HP")
    if type(hp) == "number" and hp > 0 then
        return true
    end
    -- Kiểm tra chặt chẽ: Chỉ đọc .Value khi là ValueObject và bọc pcall an toàn
    if typeof(hp) == "Instance" and hp:IsA("ValueObject") then
        local ok, val = pcall(function() return tonumber(hp.Value) end)
        if ok and val and val > 0 then
            return true
        end
    end
    return false
end

-- HÀM TÌM TẤT CẢ QUÁI / BOSS TOÀN DIỆN (CÓ CACHE 0.35S CHỐNG TỤT FPS / LAG)
local cachedEnemies = {}
local lastEnemyScan = 0

local function GetAllEnemies(forceRefresh)
    local now = os.clock()
    if not forceRefresh and (now - lastEnemyScan < 0.35) then
        if #cachedEnemies == 0 then
            return cachedEnemies
        end
        local valid = {}
        for _, item in ipairs(cachedEnemies) do
            if item.model and item.model.Parent and item.root and item.root.Parent then
                local hum = item.hum or item.model:FindFirstChildOfClass("Humanoid")
                if CheckIsAlive(item.model, hum) then
                    table.insert(valid, item)
                end
            end
        end
        cachedEnemies = valid
        return cachedEnemies
    end

    lastEnemyScan = now
    local enemies = {}
    local seen = {}
    local myChar = GetMyChar()

    local function Inspect(model)
        if not model or not model:IsA("Model") or model == myChar or seen[model] then return end
        if Players:GetPlayerFromCharacter(model) then return end

        -- BẮT BUỘC: Phải là NPC / Quái vật còn sống (Health > 0)
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not CheckIsAlive(model, hum) then return end

        local root = model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Head")
        if not root then return end

        seen[model] = true
        table.insert(enemies, { model = model, root = root, hum = hum })
    end

    -- 1. Ưu tiên quét các folder quái đặc trưng của Anime Dimensions Simulator
    local potentialFolders = {
        workspace:FindFirstChild("Enemies"),
        workspace:FindFirstChild("Mobs"),
        workspace:FindFirstChild("Monsters"),
        workspace:FindFirstChild("Entities"),
    }
    
    local dungeon = workspace:FindFirstChild("Dungeon") or workspace:FindFirstChild("Map")
    if dungeon then
        table.insert(potentialFolders, dungeon:FindFirstChild("Enemies"))
        table.insert(potentialFolders, dungeon:FindFirstChild("Mobs"))
        table.insert(potentialFolders, dungeon:FindFirstChild("Monsters"))
    end

    for _, folder in ipairs(potentialFolders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                Inspect(child)
                if child:IsA("Folder") or child:IsA("Model") then
                    for _, sub in ipairs(child:GetChildren()) do
                        Inspect(sub)
                    end
                end
            end
        end
    end

    if #enemies > 0 then
        cachedEnemies = enemies
        return enemies
    end

    -- 2. Fallback: Nếu quái nằm ở folder khác trong Workspace (CHỈ LẤY MODEL CÓ HUMANOID CÒN SỐNG)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            Inspect(obj)
        elseif obj:IsA("Folder") and obj.Name ~= "Terrain" and obj.Name ~= "Camera" then
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA("Model") then
                    Inspect(child)
                elseif child:IsA("Folder") then
                    for _, sub in ipairs(child:GetChildren()) do
                        if sub:IsA("Model") then
                            Inspect(sub)
                        end
                    end
                end
            end
        end
    end

    cachedEnemies = enemies
    return enemies
end

-- HÀM LẤY MỤC TIÊU ƯU TIÊN GẦN NHẤT HOẶC BOSS (LỌC CHÍNH XÁC QUÁI CÒN SỐNG & CÒN PARENT)
local function GetTarget()
    local enemies = GetAllEnemies()
    if #enemies == 0 then return nil end

    local myRoot = GetMyRoot()
    if not myRoot then return nil end

    -- Ưu tiên Boss nếu được bật (Lọc cả MaxHealth, Name, BossLabel và attribute)
    if Settings.AutoWalkOnlyBoss then
        for _, item in ipairs(enemies) do
            if item.model and item.model.Parent and item.root and item.root.Parent then
                local hum = item.hum or item.model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local name = item.model.Name:lower()
                    if name:find("boss") or item.model:FindFirstChild("BossLabel") or item.model:FindFirstChild("Boss") or hum.MaxHealth > 50000 or item.model:GetAttribute("IsBoss") then
                        return item
                    end
                end
            end
        end
    end

    -- Tìm quái gần nhất còn sống thực sự (bỏ qua quái đang chạy animation chết)
    local closest = nil
    local minDist = math.huge
    for _, item in ipairs(enemies) do
        if item.model and item.model.Parent and item.root and item.root.Parent then
            local hum = item.hum or item.model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local dist = (myRoot.Position - item.root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    closest = item
                end
            end
        end
    end
    return closest
end

-- VÒNG LẶP NOCLIP LIÊN TỤC (TỐI ƯU ZERO-ALLOCATION CHỐNG TỤT FPS VÀ TRÀN RÁC BỘ NHỚ) (Bug 4)
TrackConnection(RunService.Stepped:Connect(function()
    if not Settings.DisableNoclip then
        for i = 1, #charParts do
            local part = charParts[i]
            if part and part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end))

-- 3. VÒNG LẶP FARM CHÍNH (TỰ ĐỘNG TELEPORT ĐẾN QUÁI & ĐÁNH, CHỐNG TỤT FPS & JITTER TWEEN)
local activeFarmTween = nil

task.spawn(function()
    while task.wait(0.03) do
        local hasOtherPlayers = Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1
        if not hasOtherPlayers and (Settings.AutoMob or Settings.AutoPlay) then
            local char = GetMyChar()
            local myRoot = GetMyRoot()
            local myHum = GetMyHumanoid()

            if char and myRoot and (not myHum or myHum.Health > 0) then
                local target = GetTarget()
                if target and target.root then
                    local targetCFrame = target.root.CFrame
                    local farmDist = tonumber(Settings.FarmDistance) or 7

                    local targetCF
                    if Settings.FarmPosition == "Behind" then
                        -- Phía sau quái: CFrame lùi về sau
                        targetCF = targetCFrame * CFrame.new(0, 0, farmDist)
                    else
                        -- Mặc định "Above" (Trên đầu quái): CFrame ở trên đầu và nhìn thẳng xuống
                        targetCF = targetCFrame * CFrame.new(0, farmDist, 0) * CFrame.Angles(math.rad(-90), 0, 0)
                    end

                    -- Di chuyển trực tiếp hoặc Tween nhân vật đến vị trí quái theo TweenSpeed (Quản lý 1 tween duy nhất chống giật lag)
                    pcall(function()
                        local tSpeed = tonumber(Settings.TweenSpeed) or 500
                        local dist = (myRoot.Position - targetCF.Position).Magnitude
                        if tSpeed < 500 and dist > 15 then
                            if not activeFarmTween then
                                local duration = math.clamp(dist / tSpeed, 0.1, 0.8)
                                activeFarmTween = TweenService:Create(myRoot, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = targetCF })
                                activeFarmTween.Completed:Connect(function() activeFarmTween = nil end)
                                activeFarmTween:Play()
                            end
                        else
                            if activeFarmTween then
                                activeFarmTween:Cancel()
                                activeFarmTween = nil
                            end
                            if char.PrimaryPart then
                                pcall(function() char:PivotTo(targetCF) end)
                            end
                            myRoot.CFrame = targetCF
                        end
                    end)

                    -- Đóng băng rơi tự do bằng BodyVelocity để nhân vật lơ lửng ổn định (Tránh tranh chấp physics gây jitter) (MED-5)
                    local bv = myRoot:FindFirstChild("FarmBV")
                    if not bv then
                        myRoot.Velocity = Vector3.new(0, 0, 0)
                        myRoot.RotVelocity = Vector3.new(0, 0, 0)
                        bv = Instance.new("BodyVelocity")
                        bv.Name = "FarmBV"
                        bv.MaxForce = Vector3.new(100000, 100000, 100000)
                        bv.Velocity = Vector3.new(0, 0, 0)
                        bv.Parent = myRoot
                    else
                        bv.Velocity = Vector3.new(0, 0, 0)
                    end

                    -- Chém thường & Click (Tuân thủ SelectAttackMethod = "Skill" / "Melee" / "Click")
                    local attackMethod = Settings.SelectAttackMethod or "Click"
                    local canMelee = (attackMethod ~= "Skill") and (Settings.AutoMelee or attackMethod == "Melee" or attackMethod == "Click")
                    if canMelee then
                        SimulateLeftClick()
                    end
                else
                    if activeFarmTween then
                        activeFarmTween:Cancel()
                        activeFarmTween = nil
                    end
                    -- Xóa BodyVelocity khi không có quái
                    local bv = myRoot:FindFirstChild("FarmBV")
                    if bv then bv:Destroy() end
                end
            end
        else
            if activeFarmTween then
                activeFarmTween:Cancel()
                activeFarmTween = nil
            end
            -- Xóa BodyVelocity khi tắt AutoMob hoặc phát hiện người chơi khác
            local myRoot = GetMyRoot()
            if myRoot then
                local bv = myRoot:FindFirstChild("FarmBV")
                if bv then bv:Destroy() end
            end
        end
    end
end)

-- 4. VÒNG LẶP KILL AURA (DÀNH RIÊNG EXTREME DIMENSION - TUÂN THỦ PHƯƠNG THỨC TẤN CÔNG)
local lastKillAuraSkillTime = 0
task.spawn(function()
    while task.wait(0.15) do
        local hasOtherPlayers = Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1
        if not hasOtherPlayers and Settings.KillAura then
            local attackMethod = Settings.SelectAttackMethod or "Click"
            local enemies = GetAllEnemies()
            if #enemies > 0 then
                if attackMethod ~= "Skill" then
                    SimulateLeftClick()
                elseif not Settings.AutoSkill then
                    -- AttackMethod là Skill và AutoSkill tắt -> Kích hoạt 1 skill ngẫu nhiên với nhịp an toàn 2.0s (HIGH-5, MED-4)
                    local now = os.clock()
                    if now - lastKillAuraSkillTime >= 2.0 then
                        lastKillAuraSkillTime = now
                        local skills = { Settings.SkillFirst, Settings.SkillSecond, Settings.SkillThird, Settings.SkillFourth, Settings.SkillFifth }
                        local chosenSkill = skills[math.random(1, #skills)] or 1
                        SimulateSkillKey(chosenSkill)
                    end
                end
            end
        end
    end
end)

-- 5. VÒNG LẶP AUTO SKILL (MÔ PHỎNG PHÍM 1-5 & THỨ TỰ ƯU TIÊN + REMOTES + KHOẢNG CÁCH DISTANCETOSKILL)
task.spawn(function()
    while task.wait(0.25) do
        local hasOther = Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1
        local myHum = GetMyHumanoid()
        local myRoot = GetMyRoot()

        local attackMethod = Settings.SelectAttackMethod or "Click"
        local allowSkill = (attackMethod ~= "Melee") and (Settings.AutoSkill or Settings.AutoPlay or attackMethod == "Skill")

        -- Cho phép skill hoạt động khi chọn SelectAttackMethod = "Skill" (CRIT-2)
        if not hasOther and allowSkill and myHum and myHum.Health > 0 and myRoot then
            local target = GetTarget()
            local inRange = false
            if target and target.root then
                local dist = (myRoot.Position - target.root.Position).Magnitude
                if dist <= (tonumber(Settings.DistanceToSkill) or 30) then
                    inRange = true
                end
            end

            if inRange then
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
                    task.wait(0.04) -- Nhịp 0.04s giữa các skill tránh spam vượt ngưỡng anti-cheat (MED-7)
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
    end
end)

-- 6. VÒNG LẶP AUTO DODGE SKILL (DÙNG TRỰC TIẾP RADIUS STUDS VÀ CHECK NÉ NGƯỜI CHƠI)
task.spawn(function()
    while task.wait(Settings.TweenSpeedDodgePart or 0.15) do
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then
            continue
        end
        local myHum = GetMyHumanoid()
        local myRoot = GetMyRoot()
        if Settings.AutoDodgeSkill and myHum and myHum.Health > 0 and myRoot then
            local dodgeRadius = tonumber(Settings.SizeDodgePart) or 25
            for _, obj in pairs(workspace:GetChildren()) do
                if obj:IsA("BasePart") and (obj.Name:find("Warning") or (obj.Color == Color3.fromRGB(255, 0, 0) and obj.Transparency < (Settings.DodgePartTransparency or 0.9))) then
                    local dist = (myRoot.Position - obj.Position).Magnitude
                    if dist < dodgeRadius then
                        myRoot.CFrame = myRoot.CFrame * CFrame.new(0, tonumber(Settings.SizeDodgePartY) or 100, 0)
                        task.wait(0.5)
                        break
                    end
                end
            end
        end
    end
end)

-- 7. VÒNG LẶP AUTO REPLAY & RAID & INFINITE MODE RESET (CHỐNG SPAM REMOTE & LỌC VISIBLE ĐẦY ĐỦ)
local lastWebhookClearTime_Raid = 0
local lastWebhookClearTime_Dimension = 0
local replayPausedByRaid = false
local backToLobbyFired = false

task.spawn(function()
    while task.wait(1.5) do
        local isRaidOpen = false
        pcall(function()
            local raidTimer = LocalPlayer.PlayerGui:FindFirstChild("RaidTimer", true)
            if raidTimer and raidTimer.Text:lower():find("open") then isRaidOpen = true end
        end)

        if isRaidOpen then
            if Settings.StopReplayIfRaidOpen and Settings.AutoReplay and not userManuallyOverrodeReplay then
                replayPausedByRaid = true
                Settings.AutoReplay = false
                ProgrammaticSetToggle(ToggleAutoReplay, false)
            end
            if Settings.BackToLobbyIfRaidOpen and not backToLobbyFired then
                backToLobbyFired = true
                ReturnToLobby()
            end
        else
            backToLobbyFired = false
            if replayPausedByRaid then
                replayPausedByRaid = false
                if not userManuallyOverrodeReplay then
                    Settings.AutoReplay = true
                    ProgrammaticSetToggle(ToggleAutoReplay, true)
                end
            end
            userManuallyOverrodeReplay = false -- Reset mỗi iteration khi raid đóng (CRIT-4)

            if Settings.GoAFKIfRaidNotOpen then
                local myRoot = GetMyRoot()
                if myRoot then
                    pcall(function()
                        local afkSpot = workspace:FindFirstChild("AFKZone") or workspace:FindFirstChild("SpawnLocation")
                        if afkSpot then myRoot.CFrame = afkSpot.CFrame * CFrame.new(0, 5, 0) end
                    end)
                end
            end
        end

        -- Infinite Mode Wave Reset Check (Dùng dynamic GetMyHumanoid tránh stale biến)
        if Settings.ResetINFMode then
            pcall(function()
                local waveGui = LocalPlayer.PlayerGui:FindFirstChild("Wave", true) or LocalPlayer.PlayerGui:FindFirstChild("WaveLabel", true)
                if waveGui and waveGui.Text then
                    local currentWave = tonumber(waveGui.Text:match("%d+"))
                    if currentWave and currentWave >= (Settings.SelectWaveToReset or 100) then
                        local myHum = GetMyHumanoid()
                        if myHum then myHum.Health = 0 end
                    end
                end
            end)
        end

        -- Auto Replay (HỖ TRỢ CẢ REMOTE LẪN CLICK NÚT TRÊN MÀN HÌNH - KIỂM TRA CHÍNH XÁC VISIBILITY)
        if Settings.AutoReplay and not (isRaidOpen and Settings.StopReplayIfRaidOpen) then
            local matchEnded = false
            pcall(function()
                for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                    if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                        local btnText = (gui:IsA("TextButton") and gui.Text:lower()) or ""
                        local btnName = gui.Name:lower()
                        local isUnrelated = btnName:find("tutorial") or btnText:find("tutorial")
                            or btnName:find("quest") or btnText:find("quest")
                            or btnName:find("daily") or btnText:find("daily")
                            or btnName:find("practice") or btnText:find("practice")
                        if (btnName:find("replay") or btnText:find("replay") or btnName:find("retry") or btnText:find("retry")) and not isUnrelated then
                            local isReallyVisible = gui.Visible and gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0
                            local p = gui.Parent
                            while isReallyVisible and p do
                                if p:IsA("GuiObject") then
                                    if not p.Visible then
                                        isReallyVisible = false
                                        break
                                    end
                                elseif p:IsA("ScreenGui") or p:IsA("LayerCollector") then
                                    if not p.Enabled then
                                        isReallyVisible = false
                                        break
                                    end
                                end
                                p = p.Parent
                            end
                            if isReallyVisible then
                                matchEnded = true
                                if getconnections then
                                    for _, conn in pairs(getconnections(gui.MouseButton1Click) or {}) do conn:Fire() end
                                    for _, conn in pairs(getconnections(gui.Activated) or {}) do conn:Fire() end
                                end
                            end
                        end
                    end
                end
            end)

            if matchEnded then
                pcall(function()
                    local replayRemote = ReplicatedStorage:FindFirstChild("ReplayVote", true) 
                        or ReplicatedStorage:FindFirstChild("VoteReplay", true)
                        or ReplicatedStorage:FindFirstChild("Replay", true)
                    if replayRemote then 
                        replayRemote:FireServer(true)
                    end
                end)

                local isInRaid = (workspace:FindFirstChild("Raid") ~= nil) or (LocalPlayer.PlayerGui:FindFirstChild("RaidGui") ~= nil)
                if isInRaid then
                    -- Webhook Raid độc lập với Dimension (Bug 5)
                    if Settings.SendRaidDrops and (os.clock() - lastWebhookClearTime_Raid > 90) then
                        lastWebhookClearTime_Raid = os.clock()
                        SendDiscordWebhook(
                            "🏆 [RAID CLEARED] Raid Stage Cleared!",
                            "Player **" .. LocalPlayer.Name .. "** cleared the raid stage successfully!",
                            {
                                { name = "Player", value = LocalPlayer.Name, inline = true },
                                { name = "Time", value = os.date("%H:%M:%S"), inline = true },
                                { name = "Auto Replay", value = tostring(Settings.AutoReplay), inline = true }
                            },
                            65280
                        )
                    end
                else
                    -- Webhook Dimension độc lập với Raid (Bug 5)
                    if Settings.SendDimensionDrops and (os.clock() - lastWebhookClearTime_Dimension > 90) then
                        lastWebhookClearTime_Dimension = os.clock()
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
        end
    end
end)

-- 8. VÒNG LẶP AUTO BUY (VÉ RAID / TOKEN / METHOD)
task.spawn(function()
    while task.wait(6) do
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end
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

-- 9. VÒNG LẶP AUTO BÁN THẺ RÁC THEO ĐỘ HIẾM (AUTO SELL CARD - KIỂM TRA TỒN TẠI TRÁNH SPAM)
task.spawn(function()
    while task.wait(10) do
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end
        if Settings.AutoSellCard then
            pcall(function()
                local hasCardToSell = false
                local targetRarity = (Settings.SelectRarity or "Common"):lower()
                local cardsFolder = LocalPlayer:FindFirstChild("Cards", true) 
                    or (LocalPlayer:FindFirstChild("Inventory") and LocalPlayer.Inventory:FindFirstChild("Cards"))
                    or (LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Cards"))
                if cardsFolder then
                    for _, card in ipairs(cardsFolder:GetChildren()) do
                        local rarityVal = card:FindFirstChild("Rarity") or card:FindFirstChild("Tier")
                        if rarityVal and tostring(rarityVal.Value):lower():find(targetRarity) then
                            hasCardToSell = true
                            break
                        elseif card.Name:lower():find(targetRarity) then
                            hasCardToSell = true
                            break
                        end
                    end
                end

                if hasCardToSell then
                    local sellRemote = ReplicatedStorage:FindFirstChild("SellCards", true) or ReplicatedStorage:FindFirstChild("SellCard", true)
                    if sellRemote then
                        sellRemote:FireServer(Settings.SelectRarity or "Common")
                    end
                end
            end)
        end
    end
end)

-- 10. VÒNG LẶP AUTO CLAIM QUESTS & REWARDS (HỖ TRỢ CUSTOM CODES TÙY CHỈNH)
task.spawn(function()
    while task.wait(5) do
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end
        if Settings.AutoClaimQuestAndReward then
            pcall(function()
                local claimQuests = ReplicatedStorage:FindFirstChild("ClaimQuests", true) or ReplicatedStorage:FindFirstChild("ClaimQuest", true)
                if claimQuests then claimQuests:FireServer() end
                local claimDaily = ReplicatedStorage:FindFirstChild("ClaimDailyRewards", true) or ReplicatedStorage:FindFirstChild("ClaimDaily", true)
                if claimDaily then claimDaily:FireServer() end
            end)
        end
        if Settings.AutoRedeemAllCode then
            local redeemedAny = false
            pcall(function()
                local codeString = Settings.CustomRedeemCodes or "UPDATE, DIMENSIONS, SEASON, FREEGEMS, BOOST"
                local codeRemote = ReplicatedStorage:FindFirstChild("RedeemCode", true) or ReplicatedStorage:FindFirstChild("Code", true)
                if codeRemote then
                    for code in string.gmatch(codeString, "([^,%s]+)") do
                        pcall(function() codeRemote:FireServer(code) end)
                        redeemedAny = true
                        task.wait(0.5)
                    end
                end
            end)
            -- Chỉ tắt toggle nếu đã thực sự tìm thấy remote và gửi code thành công (HIGH-4, MED-3)
            if redeemedAny then
                Settings.AutoRedeemAllCode = false
                ProgrammaticSetToggle(ToggleAutoRedeem, false)
                AutoSave()
            end
        end
    end
end)

-- 11. CTRL + CLICK TP (DÙNG DYNAMIC ROOT TRÁNH LỖI SAU RESPAWN)
TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and Settings.CtrlClickTP and input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        local mouse = LocalPlayer:GetMouse()
        local myRoot = GetMyRoot()
        if mouse.Hit and myRoot then
            myRoot.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
        end
    end
end))

-- 12. GIỮ SPEED / JUMP / DASH NO COOLDOWN (CACHE CACHEDHUMANOID & DASH SCRIPT CHỐNG TỤT FPS)
local cachedDashScript = nil
local lastDashScan = 0

TrackConnection(RunService.Stepped:Connect(function()
    if not cachedHumanoid or not cachedHumanoid.Parent then
        cachedHumanoid = GetMyHumanoid()
    end
    if cachedHumanoid then
        if Settings.WalkSpeed and cachedHumanoid.WalkSpeed ~= Settings.Speed then
            cachedHumanoid.WalkSpeed = Settings.Speed
        end
        if Settings.JumpPower and cachedHumanoid.JumpPower ~= Settings.Jump then
            cachedHumanoid.JumpPower = Settings.Jump
        end
    end
    if Settings.DashNoCooldown then
        local now = os.clock()
        if not cachedDashScript or not cachedDashScript.Parent or (now - lastDashScan > 2) then
            lastDashScan = now
            local char = GetMyChar()
            cachedDashScript = char and (char:FindFirstChild("Dash") or LocalPlayer.PlayerScripts:FindFirstChild("DashClient"))
        end
        if cachedDashScript and cachedDashScript:FindFirstChild("Cooldown") then
            pcall(function()
                cachedDashScript.Cooldown.Value = 0
            end)
        end
    end
end))

-- 13. HỆ THỐNG AUTO JOIN MAP & AUTO RAID TỰ ĐỘNG Ở SẢNH (THÔNG SỐ THẬT ANIME DIMENSIONS)
local dimensionLevels = {
    { name = "Titan Dimension", minLevel = 1, keywords = { "titan", "shingeki" } },
    { name = "Demon Dimension", minLevel = 16, keywords = { "demon", "kimetsu", "slayer" } },
    { name = "Curse Dimension", minLevel = 31, keywords = { "curse", "jujutsu", "sukuna" } },
    { name = "Villain Dimension", minLevel = 46, keywords = { "villain", "hero", "academia" } },
    { name = "Sword Dimension", minLevel = 61, keywords = { "sword", "sao", "kirito" } },
    { name = "Ghoul Dimension", minLevel = 76, keywords = { "ghoul", "tokyo", "kaneki" } },
    { name = "Fate Dimension", minLevel = 91, keywords = { "fate", "stay", "night" } },
    { name = "Slime Dimension", minLevel = 106, keywords = { "slime", "rimuru", "tempest" } },
    { name = "Devil Dimension", minLevel = 121, keywords = { "devil", "clover", "chainsaw" } },
    { name = "Pirate Dimension", minLevel = 136, keywords = { "pirate", "piece", "luffy" } },
    { name = "Alien Dimension", minLevel = 151, keywords = { "alien", "dragon", "ball" } },
    { name = "Giant Dimension", minLevel = 166, keywords = { "giant" } },
    { name = "Shadow Dimension", minLevel = 181, keywords = { "shadow", "level" } },
    { name = "Esper Dimension", minLevel = 196, keywords = { "esper", "mob", "psychic" } },
    { name = "Soul Dimension", minLevel = 211, keywords = { "soul", "bleach", "shinigami" } }
}

local function GetPlayerLevel()
    local level = 1
    pcall(function()
        local searchFolders = { "leaderstats", "Data", "Stats", "PlayerData", "PlayerStats" }
        for _, name in ipairs(searchFolders) do
            local f = LocalPlayer:FindFirstChild(name)
            if f and f:FindFirstChild("Level") then
                level = tonumber(f.Level.Value) or level
                return
            end
        end
        if LocalPlayer:FindFirstChild("Level") then
            level = tonumber(LocalPlayer.Level.Value) or level
            return
        end
        local lvlLabel = LocalPlayer.PlayerGui:FindFirstChild("Level", true)
        if lvlLabel and lvlLabel:IsA("TextLabel") then
            local n = tonumber(lvlLabel.Text:match("%d+"))
            if n then level = n return end
        end
    end)
    return level
end

local function GetBestMapName()
    if not Settings.AutoSelectMap and Settings.MapSelection and Settings.MapSelection ~= "Auto" then
        return Settings.MapSelection
    end
    local currentLevel = GetPlayerLevel()
    local bestMap = "Titan Dimension"
    for _, dim in ipairs(dimensionLevels) do
        if currentLevel >= dim.minLevel then
            bestMap = dim.name
        end
    end
    return bestMap
end

local portalCache = {}
local function FindPortalPart(mapName)
    local targetClean = mapName:lower():gsub(" dimension", ""):gsub(" ", "")
    if portalCache[targetClean] and portalCache[targetClean].Parent then
        return portalCache[targetClean]
    end

    local searchContainers = {
        workspace:FindFirstChild("Portals"),
        workspace:FindFirstChild("Elevators"),
        workspace:FindFirstChild("Dimensions"),
        workspace:FindFirstChild("Lobby")
    }

    -- Pass 1: Tìm theo tên map chính xác hoàn toàn trước (MED-6: tránh match nhầm portal có từ khóa trùng)
    for _, container in ipairs(searchContainers) do
        if container then
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local objName = obj.Name:lower():gsub(" ", "")
                    local parentName = (obj.Parent and obj.Parent.Name:lower():gsub(" ", "")) or ""
                    if not objName:find("deco") and not parentName:find("deco") then
                        if objName == targetClean or objName == targetClean .. "portal" or parentName == targetClean or parentName == targetClean .. "portal" then
                            portalCache[targetClean] = obj
                            return obj
                        end
                    end
                end
            end
        end
    end

    -- Pass 2: Tìm theo tên map chứa từ khóa targetClean
    for _, container in ipairs(searchContainers) do
        if container then
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local objName = obj.Name:lower():gsub(" ", "")
                    local parentName = (obj.Parent and obj.Parent.Name:lower():gsub(" ", "")) or ""
                    if not objName:find("deco") and not parentName:find("deco") then
                        if objName:find(targetClean) or parentName:find(targetClean) then
                            portalCache[targetClean] = obj
                            return obj
                        end
                    end
                end
            end
        end
    end

    -- Pass 3: Tìm theo từ khóa keywords dự phòng của map
    local keywords = {}
    for _, dim in ipairs(dimensionLevels) do
        if dim.name:lower() == mapName:lower() then
            keywords = dim.keywords or {}
            break
        end
    end
    for _, kw in ipairs(keywords) do
        for _, container in ipairs(searchContainers) do
            if container then
                for _, obj in ipairs(container:GetDescendants()) do
                    if obj:IsA("BasePart") then
                        local objName = obj.Name:lower():gsub(" ", "")
                        local parentName = (obj.Parent and obj.Parent.Name:lower():gsub(" ", "")) or ""
                        if not objName:find("deco") and not parentName:find("deco") then
                            if objName:find(kw) or parentName:find(kw) then
                                portalCache[targetClean] = obj
                                return obj
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function CheckInGame()
    if #GetAllEnemies() > 0 then return true end
    if workspace:FindFirstChild("Dungeon") ~= nil then return true end
    if LocalPlayer.PlayerGui:FindFirstChild("DungeonUI", true) ~= nil then return true end
    if LocalPlayer.PlayerGui:FindFirstChild("Wave", true) ~= nil or LocalPlayer.PlayerGui:FindFirstChild("WaveLabel", true) ~= nil then return true end
    if LocalPlayer.PlayerGui:FindFirstChild("StageTimer", true) ~= nil then return true end
    -- Chỉ coi là ở sảnh khi không tìm thấy bất kỳ dấu hiệu in-game/stage/dungeon nào phía trên (HIGH-3, HIGH-7, LOW-5)
    if workspace:FindFirstChild("Lobby") ~= nil or workspace:FindFirstChild("LobbySpawns") ~= nil then
        return false
    end
    return false
end

local isJoining = false
local hasWaitedLobby = false
local raidJoinFails = 0
task.spawn(function()
    while task.wait(2) do
        local enemyCount = #GetAllEnemies()
        local isLobby = (game.PlaceId == LOBBY_PLACE_ID) 
            or (workspace:FindFirstChild("Lobby") ~= nil and enemyCount == 0) 
            or (workspace:FindFirstChild("LobbySpawns") ~= nil and enemyCount == 0)

        if isLobby then
            if not hasWaitedLobby then
                local waitSec = tonumber(Settings.WaitOnLobbyAfterJoin) or 10
                if waitSec > 0 then
                    task.wait(waitSec)
                end
                hasWaitedLobby = true
            end

            local shouldJoin = Settings.AutoPlay or Settings.AutoSelectMap or Settings.AutoRaid or Settings.AutoSpeedRaid
                or Settings.BossRush or Settings.FreeBossRush or Settings.AutoRaidChallenge or Settings.ExtremeDimension

            if shouldJoin and not isJoining then
                isJoining = true

                -- 1. Ưu tiên Boss Rush / Free Boss Rush (ĐỘC LẬP - KHÔNG ĐƯỢC CHẠY DIMENSION)
                if Settings.BossRush or Settings.FreeBossRush then
                    local initialJob = game.JobId
                    pcall(function()
                        local brRemote = ReplicatedStorage:FindFirstChild("StartBossRush", true)
                            or ReplicatedStorage:FindFirstChild("JoinBossRush", true)
                            or ReplicatedStorage:FindFirstChild("BossRush", true)
                        if brRemote then brRemote:FireServer(Settings.FreeBossRush) end
                    end)
                    for _ = 1, 10 do
                        task.wait(0.5)
                        if game.JobId ~= initialJob or CheckInGame() then break end
                    end
                    isJoining = false

                -- 2. Ưu tiên Raid Challenge (ĐỘC LẬP)
                elseif Settings.AutoRaidChallenge then
                    local initialJob = game.JobId
                    pcall(function()
                        local rcRemote = ReplicatedStorage:FindFirstChild("StartRaidChallenge", true)
                            or ReplicatedStorage:FindFirstChild("JoinRaidChallenge", true)
                            or ReplicatedStorage:FindFirstChild("RaidChallenge", true)
                        if rcRemote then rcRemote:FireServer() end
                    end)
                    for _ = 1, 10 do
                        task.wait(0.5)
                        if game.JobId ~= initialJob or CheckInGame() then break end
                    end
                    isJoining = false

                -- 3. Ưu tiên Extreme Dimension (ĐỘC LẬP)
                elseif Settings.ExtremeDimension then
                    local initialJob = game.JobId
                    pcall(function()
                        local edRemote = ReplicatedStorage:FindFirstChild("StartExtremeDimension", true)
                            or ReplicatedStorage:FindFirstChild("JoinExtremeDimension", true)
                            or ReplicatedStorage:FindFirstChild("ExtremeDimension", true)
                        if edRemote then
                            edRemote:FireServer(Settings.SelectExtremeDimensionDifficulty or "Extreme", Settings.ExtremeDimensionMinReward or 100)
                        end
                    end)
                    for _ = 1, 10 do
                        task.wait(0.5)
                        if game.JobId ~= initialJob or CheckInGame() then break end
                    end
                    isJoining = false

                -- 4. Auto Raid hoặc Auto Speed Raid (CÓ RANDOM KHI CHỌN AUTO)
                elseif Settings.AutoRaid or Settings.AutoSpeedRaid then
                    local initialJob = game.JobId
                    pcall(function()
                        local raidTarget = Settings.RaidSelection or "Auto"
                        if Settings.AutoSpeedRaid and (raidTarget == "Auto" or raidTarget == "") then
                            local raidList = { "Fluffy Raid", "Beast Raid", "Chainsaw Raid", "King of Curses Raid", "Infinite Shiro Raid", "Combat Giant Raid", "Red Emperor Raid", "Sun God Sora Raid", "Warlord Raid", "Tengu Raid", "Hime Raid", "Dark One Hero Raid" }
                            raidTarget = raidList[math.random(1, #raidList)]
                        end
                        local raidRemote = ReplicatedStorage:FindFirstChild("JoinRaid", true)
                            or ReplicatedStorage:FindFirstChild("EnterRaid", true)
                            or ReplicatedStorage:FindFirstChild("RaidQueue", true)
                        if raidRemote then
                            raidRemote:FireServer(raidTarget, Settings.SelectExtremeDimensionDifficulty or "Extreme")
                        end
                    end)
                    local raidCooldown = tonumber(Settings.CooldownJoinRaid) or 10
                    task.wait(raidCooldown)
                    if game.JobId ~= initialJob or CheckInGame() then
                        raidJoinFails = 0
                    else
                        raidJoinFails = raidJoinFails + 1
                        if raidJoinFails >= 5 then
                            warn("⚠️ [AUTO RAID] Không thể vào raid sau 5 lần thử liên tiếp. Tạm dừng 45 giây...")
                            task.wait(45)
                            raidJoinFails = 0
                        end
                    end
                    isJoining = false

                -- 5. Auto Dimension Map (CHỈ CHẠY KHI BẬT AUTOPLAY HOẶC AUTOSELECTMAP)
                elseif Settings.AutoPlay or Settings.AutoSelectMap then
                    local targetMap = GetBestMapName()

                    -- Gửi Remote tạo phòng / tham gia phòng Dimension
                    pcall(function()
                        local roomRemote = ReplicatedStorage:FindFirstChild("CreateRoom", true)
                            or ReplicatedStorage:FindFirstChild("JoinRoom", true)
                            or ReplicatedStorage:FindFirstChild("StartDungeon", true)
                            or ReplicatedStorage:FindFirstChild("EnterDimension", true)
                            or ReplicatedStorage:FindFirstChild("Elevator", true)
                        if roomRemote then
                            roomRemote:FireServer(targetMap, Settings.SelectDifficulty or "Easy", Settings.FriendOnly, Settings.Hardcore)
                        end
                    end)

                    -- Dịch chuyển và Touch vào Cổng Portal / Bục Elevators
                    pcall(function()
                        local portal = FindPortalPart(targetMap)
                        local myRoot = GetMyRoot()
                        if portal and myRoot then
                            myRoot.CFrame = portal.CFrame * CFrame.new(0, 3, 0)
                            if firetouchinterest then
                                firetouchinterest(myRoot, portal, 0)
                                task.wait(0.1)
                                firetouchinterest(myRoot, portal, 1)
                            end
                            for _, p in pairs(portal:GetDescendants()) do
                                if p:IsA("ProximityPrompt") then
                                    if fireproximityprompt then
                                        pcall(function() fireproximityprompt(p) end)
                                    end
                                end
                            end
                        end
                    end)

                    -- Tự động click các nút Start / Create / Ready / Enter trên giao diện phòng
                    pcall(function()
                        task.wait(0.5)
                        for _, btn in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                            if btn:IsA("TextButton") or btn:IsA("ImageButton") then
                                local btnText = (btn:IsA("TextButton") and btn.Text:lower()) or btn.Name:lower()
                                if btnText:find("start") or btnText:find("create") or btnText:find("ready") or btnText:find("enter") or btnText:find("confirm") or btnText:find("play") then
                                    if btn.Visible and (not btn.Parent:IsA("GuiObject") or btn.Parent.Visible) then
                                        if getconnections then
                                            for _, conn in pairs(getconnections(btn.MouseButton1Click) or {}) do conn:Fire() end
                                            for _, conn in pairs(getconnections(btn.Activated) or {}) do conn:Fire() end
                                        end
                                    end
                                end
                            end
                        end
                    end)

                    -- Dimension thường chỉ cần chờ 2.5s là đủ load
                    task.wait(2.5)
                    isJoining = false
                end
            end
        else
            if not Settings.WaitLobbyOnlyFirstTime then
                hasWaitedLobby = false
            end
        end
    end
end)

-- 14. VÒNG LẶP CHARACTER & CARDS (CHỈ EQUIP KHI THỰC SỰ CẦN, TRÁNH SPAM REMOTE KICK) (CRIT-3, CRIT-4, HIGH-1, HIGH-2, HIGH-3, HIGH-6, MED-1, MED-9)
local lastDetectedCharName = ""

local function GetCharacterIdentifier(char)
    if not char then return "" end
    local charVal = char:FindFirstChild("CharacterName") or char:FindFirstChild("Character") or char:FindFirstChild("Config")
    if charVal and charVal:IsA("ValueObject") then return tostring(charVal.Value) end
    local attr = char:GetAttribute("Character") or char:GetAttribute("CharacterName")
    if attr then return tostring(attr) end
    local config = char:FindFirstChild("Configuration")
    if config then
        local nameVal = config:FindFirstChild("Name") or config:FindFirstChild("CharacterName")
        if nameVal and nameVal:IsA("ValueObject") then return tostring(nameVal.Value) end
    end
    local lpData = LocalPlayer:FindFirstChild("Data") or LocalPlayer:FindFirstChild("PlayerData")
    if lpData then
        local eq = lpData:FindFirstChild("EquippedCharacter") or lpData:FindFirstChild("CurrentCharacter")
        if eq and eq:IsA("ValueObject") then return tostring(eq.Value) end
    end
    local guiChar = LocalPlayer.PlayerGui:FindFirstChild("CharacterName", true)
    if guiChar and (guiChar:IsA("TextLabel") or guiChar:IsA("TextButton")) and guiChar.Text ~= "" then
        return guiChar.Text
    end
    return "" -- Trả về rỗng nếu không tìm thấy thay vì trả tên người chơi char.Name (HIGH-2)
end

local function GetCurrentActiveSlot()
    local lpData = LocalPlayer:FindFirstChild("Data") or LocalPlayer:FindFirstChild("PlayerData")
    if lpData then
        local slotVal = lpData:FindFirstChild("CurrentSlot") or lpData:FindFirstChild("Slot") or lpData:FindFirstChild("ActiveSlot")
        if slotVal and slotVal:IsA("ValueObject") then return tonumber(slotVal.Value) end
    end
    local attr = LocalPlayer:GetAttribute("CurrentSlot") or LocalPlayer:GetAttribute("Slot") or LocalPlayer:GetAttribute("ActiveSlot")
    if attr then return tonumber(attr) end
    local char = GetMyChar()
    if char then
        local cAttr = char:GetAttribute("CurrentSlot") or char:GetAttribute("Slot") or char:GetAttribute("ActiveSlot")
        if cAttr then return tonumber(cAttr) end
        local cVal = char:FindFirstChild("CurrentSlot") or char:FindFirstChild("Slot")
        if cVal and cVal:IsA("ValueObject") then return tonumber(cVal.Value) end
    end
    return nil
end

task.spawn(function()
    while task.wait(15) do
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end

        -- Nhận diện nhân vật đa nguồn chống miss (HIGH-2, HIGH-3, HIGH-6)
        local curChar = GetMyChar()
        if curChar then
            local charTag = GetCharacterIdentifier(curChar)
            if charTag ~= "" and lastDetectedCharName ~= "" and lastDetectedCharName ~= charTag then
                lastDetectedCharName = charTag
                if Settings.AutoEquipCharacter then
                    hasEquippedCharacter = false
                end
            elseif charTag ~= "" and lastDetectedCharName == "" then
                lastDetectedCharName = charTag
            end
        end

        if Settings.AutoEquipCharacter and not hasEquippedCharacter then
            pcall(function()
                local equipRemote = ReplicatedStorage:FindFirstChild("EquipBestCharacter", true)
                    or ReplicatedStorage:FindFirstChild("EquipCharacter", true)
                    or ReplicatedStorage:FindFirstChild("AutoEquip", true)
                if equipRemote then
                    equipRemote:FireServer()
                    hasEquippedCharacter = true
                end
            end)
        end

        -- Đồng bộ slot từ game nếu game cung cấp dữ liệu
        local detectedSlot = GetCurrentActiveSlot()
        if detectedSlot then
            currentActiveSlot = detectedSlot
        end

        -- Chỉ chuyển đổi slot khi slot hiện tại KHÁC slot đích (LOẠI BỎ HOÀN TOÀN VIỆC SPAM 20S VÔ ĐIỀU KIỆN)
        if Settings.AutoResetToMain and currentActiveSlot ~= 1 then
            pcall(function()
                local switchRemote = ReplicatedStorage:FindFirstChild("SwitchCharacter", true) 
                    or ReplicatedStorage:FindFirstChild("ChangeCharacter", true)
                if switchRemote then
                    switchRemote:FireServer(1)
                    currentActiveSlot = 1
                end
            end)
        elseif Settings.AutoResetToFirstAssist and currentActiveSlot ~= 2 then
            pcall(function()
                local switchRemote = ReplicatedStorage:FindFirstChild("SwitchCharacter", true) 
                    or ReplicatedStorage:FindFirstChild("ChangeCharacter", true)
                if switchRemote then
                    switchRemote:FireServer(2)
                    currentActiveSlot = 2
                end
            end)
        end

        -- Chỉ fire equip card nếu mode hiện tại chưa được equip (HIGH-6: loại bỏ timer 60s gây spam re-equip liên tục)
        if Settings.EquipBestCard and lastEquippedCardMode ~= (Settings.EquipBestCardMode or "Damage/Crit") then
            pcall(function()
                local cardRemote = ReplicatedStorage:FindFirstChild("EquipBestCards", true)
                    or ReplicatedStorage:FindFirstChild("EquipBestCard", true)
                    or ReplicatedStorage:FindFirstChild("EquipCards", true)
                if cardRemote then
                    local targetMode = Settings.EquipBestCardMode or "Damage/Crit"
                    cardRemote:FireServer(targetMode)
                    lastEquippedCardMode = targetMode
                end
            end)
        end
    end
end)

-- 15. THEO DÕI VÀ BẢO VỆ KHI BỊ PHÁT HIỆN EXPLOIT (ANTI-EXPLOIT DETECTED - LOẠI TRỪ CHAT VÀ COOLDOWN 45S)
local isReturningLobby = false
local exploitCooldown = 45
task.spawn(function()
    while task.wait(3) do
        if Settings.BackToLobbyIfGotExploitsDetected and not isReturningLobby then
            pcall(function()
                local detected = false
                local checkGuis = {
                    CoreGui:FindFirstChild("RobloxPromptGui"),
                    CoreGui:FindFirstChild("SecurityPrompt"),
                    LocalPlayer.PlayerGui:FindFirstChild("SecurityPrompt"),
                    LocalPlayer.PlayerGui:FindFirstChild("WarningPrompt")
                }
                for _, rootGui in ipairs(checkGuis) do
                    if rootGui then
                        for _, g in ipairs(rootGui:GetDescendants()) do
                            if g:IsA("TextLabel") or g:IsA("TextButton") then
                                local txt = g.Text:lower()
                                if txt:find("exploit") or txt:find("suspicious") or txt:find("cheat detected") or txt:find("security kick") then
                                    detected = true
                                    break
                                end
                            end
                        end
                    end
                    if detected then break end
                end

                if detected then
                    isReturningLobby = true
                    warn("⚠️ [EXPLOIT WARNING DETECTED!] Tự động quay về sảnh để an toàn!")
                    local initialPlace = game.PlaceId
                    ReturnToLobby()
                    task.wait(exploitCooldown)
                    if game.PlaceId == initialPlace then
                        exploitCooldown = math.min(exploitCooldown * 2, 300) -- Exponential backoff tối đa 5 phút nếu kẹt (MED-2)
                    else
                        exploitCooldown = 45
                    end
                    isReturningLobby = false
                end
            end)
        end
    end
end)

-- 16. CẬP NHẬT CHỈ SỐ STAT GUI THEO THỜI GIAN THẬT (TỰ ĐỘNG DISCONNECT KHI RELOAD & TÍNH GIỜ CHÍNH XÁC)
task.spawn(function()
    local frameCount = 0
    local lastFpsTick = os.clock()
    local fps = 60
    TrackConnection(RunService.RenderStepped:Connect(function()
        if not Settings.StatGui then
            -- Liên tục đồng bộ thời gian và reset số đếm khung hình khi tắt GUI để không bị kẹt 1 FPS khi bật lại
            frameCount = 0
            lastFpsTick = os.clock()
            return
        end
        frameCount = frameCount + 1
        local now = os.clock()
        local delta = now - lastFpsTick
        if delta >= 1 then
            fps = math.floor(frameCount / delta)
            frameCount = 0
            lastFpsTick = now
        end
    end))

    while task.wait(1) do
        if Settings.StatGui and statGuiInstance and statGuiInstance:FindFirstChild("MainFrame") then
            local label = statGuiInstance.MainFrame:FindFirstChild("Content")
            if label then
                local elapsed = math.floor(os.clock() - (statGuiStartTime or os.clock()))
                local m = math.floor(elapsed / 60)
                local s = elapsed % 60
                local curMap = (workspace:FindFirstChild("Map") and workspace.Map.Name) or (workspace:FindFirstChild("Dungeon") and workspace.Dungeon.Name) or GetBestMapName()
                local fpsDisplay = Settings.WhiteScreen and "Reduced (3D Off)" or string.format("%d", fps)
                label.Text = string.format(
                    "User: %s\nLevel: %s\nMap: %s\nFPS: %s | Time: %02d:%02d",
                    LocalPlayer.Name,
                    tostring(GetPlayerLevel()),
                    curMap,
                    fpsDisplay,
                    m,
                    s
                )
            end
        end
    end
end)

-- 17. ĐÓNG GUI SAU KHI THỰC THI NẾU BẬT
if Settings.CloseGuiAfterExecute then
    task.spawn(function()
        pcall(function()
            OrionLib:MakeNotification({
                Name = "Auto Close GUI",
                Content = "GUI sẽ tự động ẩn sau 4 giây theo cài đặt...",
                Image = "rbxassetid://4483345998",
                Time = 4
            })
        end)
        task.wait(4)
        pcall(function()
            for _, g in ipairs(CoreGui:GetDescendants()) do
                if g.Name == "Orion" or g.Name:find("Orion") then
                    if g:IsA("ScreenGui") then g.Enabled = false end
                end
            end
        end)
    end)
end

OrionLib:Init()
print("🎉 SLH Hub Modified - Loaded Successfully with Full 7 Tabs!")
