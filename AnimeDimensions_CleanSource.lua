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

if not game:IsLoaded() then
    pcall(function() game.Loaded:Wait() end)
end

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Players.LocalPlayer
end

local LOBBY_PLACE_ID = 6938803436
local ALT_LOBBY_PLACE_ID = 6379034480
local userIntentionalLeave = false -- Cờ đánh dấu người dùng chủ động Leave, chặn Rejoin tự động (CRIT-1, CRIT-3)
local currentActiveSlot = 1 -- Quản lý slot nhân vật hiện tại (1: Main, 2: First Assist) tránh spam remote đổi nhân vật

-- ===================================================================
-- QUẢN LÝ VÒNG ĐỜI PHIÊN CHẠY (SESSION LIFECYCLE) & DỌN DẸP PHIÊN CŨ
-- ===================================================================
_G.VHT_SessionID = (_G.VHT_SessionID or 0) + 1
local currentSessionID = _G.VHT_SessionID

pcall(function()
    if LocalPlayer and LocalPlayer.Character then
        local oldRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart
        if oldRoot then
            local bv = oldRoot:FindFirstChild("FarmBV")
            if bv then bv:Destroy() end
        end
    end
end)

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

_G.VHT_Connections = _G.SLH_Connections

-- HÀM HỖ TRỢ NẠP LẠI SCRIPT KHI TELEPORT SẢNH / MAP / REJOIN (CHỐNG QUEUE TRÙNG LẶP) (A1)
local teleportQueued = false
local function QueueScriptReload()
    if teleportQueued then return end
    local queue = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    if queue then
        pcall(function()
            queue([[
                repeat task.wait() until game:IsLoaded()
                pcall(function()
                    if isfile and isfile("AnimeDimensions_Protected.lua") then
                        loadstring(readfile("AnimeDimensions_Protected.lua"))()
                    elseif isfile and isfile("AnimeDimensions_CleanSource.lua") then
                        loadstring(readfile("AnimeDimensions_CleanSource.lua"))()
                    else
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/trongvo2010620-ctrl/animedimesiton/main/AnimeDimensions_CleanSource.lua"))()
                    end
                end)
            ]])
            teleportQueued = true
        end)
    end
end

TrackConnection(LocalPlayer.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then
        QueueScriptReload()
    end
end))

-- HÀM TÌM VÀ BẢO ĐẢM ĐÚNG ĐỐI TƯỢNG REMOTE (REMOTEEVENT HOẶC REMOTEFUNCTION) CÓ CACHE (B1)
local remoteCache = {}
local remoteMissUntil = {}
local function FindRemote(names)
    local nameList = type(names) == "table" and names or { names }
    local cacheKey = table.concat(nameList, "|")
    if remoteCache[cacheKey] and remoteCache[cacheKey].Parent then
        return remoteCache[cacheKey]
    end
    if remoteMissUntil[cacheKey] and os.clock() < remoteMissUntil[cacheKey] then
        return nil
    end
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            for _, n in ipairs(nameList) do
                if desc.Name == n then
                    remoteCache[cacheKey] = desc
                    remoteMissUntil[cacheKey] = nil
                    return desc
                end
            end
        end
    end
    remoteMissUntil[cacheKey] = os.clock() + 10
    return nil
end

local function SafeFireRemote(remote, ...)
    if not remote then return false end
    if remote:IsA("RemoteEvent") then
        local ok = pcall(function(...) remote:FireServer(...) end, ...)
        return ok
    elseif remote:IsA("RemoteFunction") then
        local args = { ... }
        local nArgs = select("#", ...)
        local callingThread = coroutine.running()
        local isDone = false
        local success = false
        local result = nil

        task.spawn(function()
            local ok, res = pcall(function()
                return remote:InvokeServer(unpack(args, 1, nArgs))
            end)
            if not isDone then
                isDone = true
                success = ok
                result = res
                if callingThread and coroutine.status(callingThread) == "suspended" then
                    task.spawn(callingThread)
                end
            end
        end)

        task.delay(3, function()
            if not isDone then
                isDone = true
                success = false
                result = "Timeout"
                if callingThread and coroutine.status(callingThread) == "suspended" then
                    task.spawn(callingThread)
                end
            end
        end)

        if not isDone then
            coroutine.yield()
        end

        return success, result
    end
    return false
end

-- HÀM KIỂM TRA HIỂN THỊ THẬT CỦA PHẦN TỬ GUI QUA TOÀN BỘ CHUỖI CHA (A5, B4)
local function IsGuiElementReallyVisible(gui)
    if not gui or not gui.Parent then return false end
    if not (gui.Visible and gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0) then
        return false
    end
    local p = gui.Parent
    while p do
        if p:IsA("GuiObject") then
            if not p.Visible then return false end
        elseif p:IsA("ScreenGui") or p:IsA("LayerCollector") then
            if not p.Enabled then return false end
        end
        p = p.Parent
    end
    return true
end

-- ===================================================================
-- 2. HỆ THỐNG CẤU HÌNH & TỰ ĐỘNG LƯU NGẦM 100% (ZERO ACTION AUTO-SAVE)
-- ĐƯỢC ĐẶT TRƯỚC TOÀN BỘ CÁC HÀM GETTER VÀ SỰ KIỆN CHARACTER
-- ===================================================================
local AutoSaveFile = "AnimeDimensions_AutoSave.json"

local Settings = {
     Language = "Tiếng Việt", -- Ngôn ngữ mặc định (Tiếng Việt / English)
   -- TAB 1: MAIN & FARMING
    AutoJoinMap = false, -- Tự động vào map và tự động farm trọn gói
    MapSelection = "Auto",
    SelectDifficulty = "Auto", -- Tự động chọn độ khó (Auto / Nightmare / Hard / Easy) theo Level và Sức Mạnh
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
    SelectAttackMethod = "Skill",
    AutoMelee = false,
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
    AutoNextRoom = false, -- Tự động chuyển phòng khi hết quái (mặc định tắt)
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
    SkillFirst = "5",
    SkillSecond = "4",
    SkillThird = "1",
    SkillFourth = "2",
    SkillFifth = "3",

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
            -- Nâng cấp cấu hình mặc định cũ (4, 3, 5, 1, 2) lên thứ tự mới (5, 4, 1, 2, 3)
            if Settings.SkillFirst == "4" and Settings.SkillSecond == "3" and Settings.SkillThird == "5" and Settings.SkillFourth == "1" and Settings.SkillFifth == "2" then
                Settings.SkillFirst = "5"
                Settings.SkillSecond = "4"
                Settings.SkillThird = "1"
                Settings.SkillFourth = "2"
                Settings.SkillFifth = "3"
            end
            -- Kiểm tra và chuẩn hóa cấu hình phím skill (MED-9)
            local validSkills = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true }
            if not validSkills[tostring(Settings.SkillFirst)] then Settings.SkillFirst = "5" end
            if not validSkills[tostring(Settings.SkillSecond)] then Settings.SkillSecond = "4" end
            if not validSkills[tostring(Settings.SkillThird)] then Settings.SkillThird = "1" end
            if not validSkills[tostring(Settings.SkillFourth)] then Settings.SkillFourth = "2" end
            if not validSkills[tostring(Settings.SkillFifth)] then Settings.SkillFifth = "3" end
            -- Chuyển đổi an toàn: Đưa SelectAttackMethod sang 'Skill' để tuyệt đối không click chuột, tránh kẹt giao diện
            if Settings.SelectAttackMethod == "Click" or not Settings.SelectAttackMethod then
                Settings.SelectAttackMethod = "Skill"
                Settings.AutoMelee = false
            end
            local validDifficulties = { ["Auto"] = true, ["Nightmare"] = true, ["Hard"] = true, ["Easy"] = true }
            if not validDifficulties[Settings.SelectDifficulty] then Settings.SelectDifficulty = "Auto" end
            if not Settings.Language or (Settings.Language ~= "Tiếng Việt" and Settings.Language ~= "English") then Settings.Language = "Tiếng Việt" end

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
    if immediate then
        currentSaveToken = currentSaveToken + 1
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
    local token = currentSaveToken
    task.delay(0.5, function()
        saveDebounce = false
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
        username = "VHT HUB",
        avatar_url = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=150&height=150&format=png",
        embeds = {
            {
                title = title or "⚡ VHT Hub Notification",
                description = description or "",
                color = color or 16711680,
                fields = fields or {},
                footer = {
                    text = "VHT HUB • " .. os.date("%d/%m/%Y %H:%M:%S")
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
-- 3. KHỞI TẠO GIAO DIỆN CHÍNH (ORION UI - TÍCH HỢP NỘI HÀM 100% OFFLINE)
-- KHÔNG PHỤ THUỘC MẠNG / CDN, KHÔNG BAO GIỜ BỊ CHẶN ISP HAY LỖI TẢI THƯ VIỆN
-- ===================================================================

-- Hiển thị thông báo trạng thái nạp VHT HUB ngay tức thì
pcall(function()
    local oldSplash = CoreGui:FindFirstChild("VHT_SplashGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("VHT_SplashGui"))
    if oldSplash then oldSplash:Destroy() end
    local splashGui = Instance.new("ScreenGui")
    splashGui.Name = "VHT_SplashGui"
    splashGui.ResetOnSpawn = false
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(splashGui) end
        splashGui.Parent = CoreGui
    end)
    if not splashGui.Parent then splashGui.Parent = LocalPlayer:FindFirstChild("PlayerGui") end
    if splashGui.Parent then
        local splashFrame = Instance.new("Frame")
        splashFrame.Size = UDim2.new(0, 260, 0, 38)
        splashFrame.Position = UDim2.new(0.5, -130, 0.05, 0)
        splashFrame.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
        splashFrame.BorderSizePixel = 0
        splashFrame.Parent = splashGui
        local sCorner = Instance.new("UICorner")
        sCorner.CornerRadius = UDim.new(0, 8)
        sCorner.Parent = splashFrame
        local sStroke = Instance.new("UIStroke")
        sStroke.Color = Color3.fromRGB(0, 220, 255)
        sStroke.Thickness = 1.2
        sStroke.Parent = splashFrame
        local sLabel = Instance.new("TextLabel")
        sLabel.Size = UDim2.new(1, -20, 1, 0)
        sLabel.Position = UDim2.new(0, 10, 0, 0)
        sLabel.BackgroundTransparency = 1
        sLabel.Text = "⚡ VHT HUB: Đang khởi động giao diện..."
        sLabel.TextColor3 = Color3.fromRGB(0, 255, 220)
        sLabel.Font = Enum.Font.GothamBold
        sLabel.TextSize = 13
        sLabel.TextXAlignment = Enum.TextXAlignment.Center
        sLabel.Parent = splashFrame
        task.delay(3, function()
            pcall(function() splashGui:Destroy() end)
        end)
    end
end)

local function LoadEmbeddedOrion()


local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local LocalPlayer = game:GetService("Players").LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local HttpService = game:GetService("HttpService")

local OrionLib = {
	Elements = {},
	ThemeObjects = {},
	Connections = {},
	Flags = {},
	Themes = {
		Default = {
			Main = Color3.fromRGB(25, 25, 25),
			Second = Color3.fromRGB(32, 32, 32),
			Stroke = Color3.fromRGB(60, 60, 60),
			Divider = Color3.fromRGB(60, 60, 60),
			Text = Color3.fromRGB(240, 240, 240),
			TextDark = Color3.fromRGB(150, 150, 150)
		}
	},
	SelectedTheme = "Default",
	Folder = nil,
	SaveCfg = false
}

-- Feather Icons (offline, network fetch disabled for 100% stability)
local Icons = {}

local function GetIcon(IconName)
	if Icons[IconName] ~= nil then
		return Icons[IconName]
	else
		return nil
	end
end   

local Orion = Instance.new("ScreenGui")
Orion.Name = "Orion"
Orion.ResetOnSpawn = false
local safeParent = nil
if gethui then pcall(function() safeParent = gethui() end) end
if not safeParent then
	pcall(function()
		if syn and syn.protect_gui then syn.protect_gui(Orion) end
		Orion.Parent = game:GetService("CoreGui")
		safeParent = Orion.Parent
	end)
end
if not safeParent or Orion.Parent ~= safeParent then
	pcall(function()
		safeParent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		Orion.Parent = safeParent
	end)
end

pcall(function()
	local searchContainers = {}
	if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
	pcall(function() table.insert(searchContainers, game:GetService("CoreGui")) end)
	pcall(function() table.insert(searchContainers, game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")) end)
	for _, cont in ipairs(searchContainers) do
		if cont then
			for _, Interface in ipairs(cont:GetChildren()) do
				if Interface:IsA("ScreenGui") and Interface.Name == Orion.Name and Interface ~= Orion then
					pcall(function() Interface:Destroy() end)
				end
			end
		end
	end
end)

function OrionLib:IsRunning()
	return Orion and Orion.Parent ~= nil
end

local function AddConnection(Signal, Function)
	if (not OrionLib:IsRunning()) then
		return
	end
	local SignalConnect = Signal:Connect(Function)
	table.insert(OrionLib.Connections, SignalConnect)
	return SignalConnect
end

task.spawn(function()
	while (OrionLib:IsRunning()) do
		wait()
	end

	for _, Connection in next, OrionLib.Connections do
		Connection:Disconnect()
	end
end)

local function AddDraggingFunctionality(DragPoint, Main)
	pcall(function()
		local Dragging, DragInput, MousePos, FramePos = false
		DragPoint.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				Dragging = true
				MousePos = Input.Position
				FramePos = Main.Position

				Input.Changed:Connect(function()
					if Input.UserInputState == Enum.UserInputState.End then
						Dragging = false
					end
				end)
			end
		end)
		DragPoint.InputChanged:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				DragInput = Input
			end
		end)
		UserInputService.InputChanged:Connect(function(Input)
			if Input == DragInput and Dragging then
				local Delta = Input.Position - MousePos
				TweenService:Create(Main, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position  = UDim2.new(FramePos.X.Scale,FramePos.X.Offset + Delta.X, FramePos.Y.Scale, FramePos.Y.Offset + Delta.Y)}):Play()
			end
		end)
	end)
end   

local function Create(Name, Properties, Children)
	local Object = Instance.new(Name)
	for i, v in next, Properties or {} do
		Object[i] = v
	end
	for i, v in next, Children or {} do
		v.Parent = Object
	end
	return Object
end

local function CreateElement(ElementName, ElementFunction)
	OrionLib.Elements[ElementName] = function(...)
		return ElementFunction(...)
	end
end

local function MakeElement(ElementName, ...)
	local NewElement = OrionLib.Elements[ElementName](...)
	return NewElement
end

local function SetProps(Element, Props)
	table.foreach(Props, function(Property, Value)
		Element[Property] = Value
	end)
	return Element
end

local function SetChildren(Element, Children)
	table.foreach(Children, function(_, Child)
		Child.Parent = Element
	end)
	return Element
end

local function Round(Number, Factor)
	local Result = math.floor(Number/Factor + (math.sign(Number) * 0.5)) * Factor
	if Result < 0 then Result = Result + Factor end
	return Result
end

local function ReturnProperty(Object)
	if Object:IsA("Frame") or Object:IsA("TextButton") then
		return "BackgroundColor3"
	end 
	if Object:IsA("ScrollingFrame") then
		return "ScrollBarImageColor3"
	end 
	if Object:IsA("UIStroke") then
		return "Color"
	end 
	if Object:IsA("TextLabel") or Object:IsA("TextBox") then
		return "TextColor3"
	end   
	if Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
		return "ImageColor3"
	end   
end

local function AddThemeObject(Object, Type)
	if not OrionLib.ThemeObjects[Type] then
		OrionLib.ThemeObjects[Type] = {}
	end    
	table.insert(OrionLib.ThemeObjects[Type], Object)
	Object[ReturnProperty(Object)] = OrionLib.Themes[OrionLib.SelectedTheme][Type]
	return Object
end    

local function SetTheme()
	for Name, Type in pairs(OrionLib.ThemeObjects) do
		for _, Object in pairs(Type) do
			Object[ReturnProperty(Object)] = OrionLib.Themes[OrionLib.SelectedTheme][Name]
		end    
	end    
end

local function PackColor(Color)
	return {R = Color.R * 255, G = Color.G * 255, B = Color.B * 255}
end    

local function UnpackColor(Color)
	return Color3.fromRGB(Color.R, Color.G, Color.B)
end

local function LoadCfg(Config)
	local Data = HttpService:JSONDecode(Config)
	table.foreach(Data, function(a,b)
		if OrionLib.Flags[a] then
			spawn(function() 
				if OrionLib.Flags[a].Type == "Colorpicker" then
					OrionLib.Flags[a]:Set(UnpackColor(b))
				else
					OrionLib.Flags[a]:Set(b)
				end    
			end)
		else
			warn("Orion Library Config Loader - Could not find ", a ,b)
		end
	end)
end

local function SaveCfg(Name)
	local Data = {}
	for i,v in pairs(OrionLib.Flags) do
		if v.Save then
			if v.Type == "Colorpicker" then
				Data[i] = PackColor(v.Value)
			else
				Data[i] = v.Value
			end
		end	
	end
	writefile(OrionLib.Folder .. "/" .. Name .. ".txt", tostring(HttpService:JSONEncode(Data)))
end

local WhitelistedMouse = {Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2,Enum.UserInputType.MouseButton3}
local BlacklistedKeys = {Enum.KeyCode.Unknown,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Up,Enum.KeyCode.Left,Enum.KeyCode.Down,Enum.KeyCode.Right,Enum.KeyCode.Slash,Enum.KeyCode.Tab,Enum.KeyCode.Backspace,Enum.KeyCode.Escape}

local function CheckKey(Table, Key)
	for _, v in next, Table do
		if v == Key then
			return true
		end
	end
end

CreateElement("Corner", function(Scale, Offset)
	local Corner = Create("UICorner", {
		CornerRadius = UDim.new(Scale or 0, Offset or 10)
	})
	return Corner
end)

CreateElement("Stroke", function(Color, Thickness)
	local Stroke = Create("UIStroke", {
		Color = Color or Color3.fromRGB(255, 255, 255),
		Thickness = Thickness or 1
	})
	return Stroke
end)

CreateElement("List", function(Scale, Offset)
	local List = Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(Scale or 0, Offset or 0)
	})
	return List
end)

CreateElement("Padding", function(Bottom, Left, Right, Top)
	local Padding = Create("UIPadding", {
		PaddingBottom = UDim.new(0, Bottom or 4),
		PaddingLeft = UDim.new(0, Left or 4),
		PaddingRight = UDim.new(0, Right or 4),
		PaddingTop = UDim.new(0, Top or 4)
	})
	return Padding
end)

CreateElement("TFrame", function()
	local TFrame = Create("Frame", {
		BackgroundTransparency = 1
	})
	return TFrame
end)

CreateElement("Frame", function(Color)
	local Frame = Create("Frame", {
		BackgroundColor3 = Color or Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0
	})
	return Frame
end)

CreateElement("RoundFrame", function(Color, Scale, Offset)
	local Frame = Create("Frame", {
		BackgroundColor3 = Color or Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0
	}, {
		Create("UICorner", {
			CornerRadius = UDim.new(Scale, Offset)
		})
	})
	return Frame
end)

CreateElement("Button", function()
	local Button = Create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0
	})
	return Button
end)

CreateElement("ScrollFrame", function(Color, Width)
	local ScrollFrame = Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		MidImage = "rbxassetid://7445543667",
		BottomImage = "rbxassetid://7445543667",
		TopImage = "rbxassetid://7445543667",
		ScrollBarImageColor3 = Color,
		BorderSizePixel = 0,
		ScrollBarThickness = Width,
		CanvasSize = UDim2.new(0, 0, 0, 0)
	})
	return ScrollFrame
end)

CreateElement("Image", function(ImageID)
	local ImageNew = Create("ImageLabel", {
		Image = ImageID,
		BackgroundTransparency = 1
	})

	if GetIcon(ImageID) ~= nil then
		ImageNew.Image = GetIcon(ImageID)
	end	

	return ImageNew
end)

CreateElement("ImageButton", function(ImageID)
	local Image = Create("ImageButton", {
		Image = ImageID,
		BackgroundTransparency = 1
	})
	return Image
end)

CreateElement("Label", function(Text, TextSize, Transparency)
	local Label = Create("TextLabel", {
		Text = Text or "",
		TextColor3 = Color3.fromRGB(240, 240, 240),
		TextTransparency = Transparency or 0,
		TextSize = TextSize or 15,
		Font = Enum.Font.Gotham,
		RichText = true,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left
	})
	return Label
end)

local NotificationHolder = SetProps(SetChildren(MakeElement("TFrame"), {
	SetProps(MakeElement("List"), {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 5)
	})
}), {
	Position = UDim2.new(1, -25, 1, -25),
	Size = UDim2.new(0, 300, 1, -25),
	AnchorPoint = Vector2.new(1, 1),
	Parent = Orion
})

function OrionLib:MakeNotification(NotificationConfig)
	spawn(function()
		NotificationConfig.Name = NotificationConfig.Name or "Notification"
		NotificationConfig.Content = NotificationConfig.Content or "Test"
		NotificationConfig.Image = NotificationConfig.Image or "rbxassetid://4384403532"
		NotificationConfig.Time = NotificationConfig.Time or 15

		local NotificationParent = SetProps(MakeElement("TFrame"), {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = NotificationHolder
		})

		local NotificationFrame = SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(25, 25, 25), 0, 10), {
			Parent = NotificationParent, 
			Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.new(1, -55, 0, 0),
			BackgroundTransparency = 0,
			AutomaticSize = Enum.AutomaticSize.Y
		}), {
			MakeElement("Stroke", Color3.fromRGB(93, 93, 93), 1.2),
			MakeElement("Padding", 12, 12, 12, 12),
			SetProps(MakeElement("Image", NotificationConfig.Image), {
				Size = UDim2.new(0, 20, 0, 20),
				ImageColor3 = Color3.fromRGB(240, 240, 240),
				Name = "Icon"
			}),
			SetProps(MakeElement("Label", NotificationConfig.Name, 15), {
				Size = UDim2.new(1, -30, 0, 20),
				Position = UDim2.new(0, 30, 0, 0),
				Font = Enum.Font.GothamBold,
				Name = "Title"
			}),
			SetProps(MakeElement("Label", NotificationConfig.Content, 14), {
				Size = UDim2.new(1, 0, 0, 0),
				Position = UDim2.new(0, 0, 0, 25),
				Font = Enum.Font.GothamSemibold,
				Name = "Content",
				AutomaticSize = Enum.AutomaticSize.Y,
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextWrapped = true
			})
		})

		TweenService:Create(NotificationFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {Position = UDim2.new(0, 0, 0, 0)}):Play()

		wait(NotificationConfig.Time - 0.88)
		TweenService:Create(NotificationFrame.Icon, TweenInfo.new(0.4, Enum.EasingStyle.Quint), {ImageTransparency = 1}):Play()
		TweenService:Create(NotificationFrame, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {BackgroundTransparency = 0.6}):Play()
		wait(0.3)
		TweenService:Create(NotificationFrame.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quint), {Transparency = 0.9}):Play()
		TweenService:Create(NotificationFrame.Title, TweenInfo.new(0.6, Enum.EasingStyle.Quint), {TextTransparency = 0.4}):Play()
		TweenService:Create(NotificationFrame.Content, TweenInfo.new(0.6, Enum.EasingStyle.Quint), {TextTransparency = 0.5}):Play()
		wait(0.05)

		NotificationFrame:TweenPosition(UDim2.new(1, 20, 0, 0),'In','Quint',0.8,true)
		wait(1.35)
		NotificationFrame:Destroy()
	end)
end    

function OrionLib:Init()
	if OrionLib.SaveCfg then	
		pcall(function()
			if isfile(OrionLib.Folder .. "/" .. game.GameId .. ".txt") then
				LoadCfg(readfile(OrionLib.Folder .. "/" .. game.GameId .. ".txt"))
				OrionLib:MakeNotification({
					Name = "Configuration",
					Content = "Auto-loaded configuration for the game " .. game.GameId .. ".",
					Time = 5
				})
			end
		end)		
	end	
end	

function OrionLib:MakeWindow(WindowConfig)
	local FirstTab = true
	local Minimized = false
	local Loaded = false
	local UIHidden = false

	WindowConfig = WindowConfig or {}
	WindowConfig.Name = WindowConfig.Name or "Orion Library"
	WindowConfig.ConfigFolder = WindowConfig.ConfigFolder or WindowConfig.Name
	WindowConfig.SaveConfig = WindowConfig.SaveConfig or false
	WindowConfig.HidePremium = WindowConfig.HidePremium or false
	if WindowConfig.IntroEnabled == nil then
		WindowConfig.IntroEnabled = true
	end
	WindowConfig.IntroText = WindowConfig.IntroText or "Orion Library"
	WindowConfig.CloseCallback = WindowConfig.CloseCallback or function() end
	WindowConfig.ShowIcon = WindowConfig.ShowIcon or false
	WindowConfig.Icon = WindowConfig.Icon or "rbxassetid://8834748103"
	WindowConfig.IntroIcon = WindowConfig.IntroIcon or "rbxassetid://8834748103"
	OrionLib.Folder = WindowConfig.ConfigFolder
	OrionLib.SaveCfg = WindowConfig.SaveConfig

	-- [VHT] Sirius telemetry disabled

	if WindowConfig.SaveConfig then
		if not isfolder(WindowConfig.ConfigFolder) then
			makefolder(WindowConfig.ConfigFolder)
		end	
	end

	local TabHolder = AddThemeObject(SetChildren(SetProps(MakeElement("ScrollFrame", Color3.fromRGB(255, 255, 255), 4), {
		Size = UDim2.new(1, 0, 1, -50)
	}), {
		MakeElement("List"),
		MakeElement("Padding", 8, 0, 0, 8)
	}), "Divider")

	AddConnection(TabHolder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		TabHolder.CanvasSize = UDim2.new(0, 0, 0, TabHolder.UIListLayout.AbsoluteContentSize.Y + 16)
	end)

	local CloseBtn = SetChildren(SetProps(MakeElement("Button"), {
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1
	}), {
		AddThemeObject(SetProps(MakeElement("Image", "rbxassetid://7072725342"), {
			Position = UDim2.new(0, 9, 0, 6),
			Size = UDim2.new(0, 18, 0, 18)
		}), "Text")
	})

	local MinimizeBtn = SetChildren(SetProps(MakeElement("Button"), {
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1
	}), {
		AddThemeObject(SetProps(MakeElement("Image", "rbxassetid://7072719338"), {
			Position = UDim2.new(0, 9, 0, 6),
			Size = UDim2.new(0, 18, 0, 18),
			Name = "Ico"
		}), "Text")
	})

	local DragPoint = SetProps(MakeElement("TFrame"), {
		Size = UDim2.new(1, 0, 0, 50)
	})

	local WindowStuff = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 10), {
		Size = UDim2.new(0, 150, 1, -50),
		Position = UDim2.new(0, 0, 0, 50)
	}), {
		AddThemeObject(SetProps(MakeElement("Frame"), {
			Size = UDim2.new(1, 0, 0, 10),
			Position = UDim2.new(0, 0, 0, 0)
		}), "Second"), 
		AddThemeObject(SetProps(MakeElement("Frame"), {
			Size = UDim2.new(0, 10, 1, 0),
			Position = UDim2.new(1, -10, 0, 0)
		}), "Second"), 
		AddThemeObject(SetProps(MakeElement("Frame"), {
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.new(1, -1, 0, 0)
		}), "Stroke"), 
		TabHolder,
		SetChildren(SetProps(MakeElement("TFrame"), {
			Size = UDim2.new(1, 0, 0, 50),
			Position = UDim2.new(0, 0, 1, -50)
		}), {
			AddThemeObject(SetProps(MakeElement("Frame"), {
				Size = UDim2.new(1, 0, 0, 1)
			}), "Stroke"), 
			AddThemeObject(SetChildren(SetProps(MakeElement("Frame"), {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(0, 32, 0, 32),
				Position = UDim2.new(0, 10, 0.5, 0)
			}), {
				SetProps(MakeElement("Image", "https://www.roblox.com/headshot-thumbnail/image?userId=".. LocalPlayer.UserId .."&width=420&height=420&format=png"), {
					Size = UDim2.new(1, 0, 1, 0)
				}),
				AddThemeObject(SetProps(MakeElement("Image", "rbxassetid://4031889928"), {
					Size = UDim2.new(1, 0, 1, 0),
				}), "Second"),
				MakeElement("Corner", 1)
			}), "Divider"),
			SetChildren(SetProps(MakeElement("TFrame"), {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(0, 32, 0, 32),
				Position = UDim2.new(0, 10, 0.5, 0)
			}), {
				AddThemeObject(MakeElement("Stroke"), "Stroke"),
				MakeElement("Corner", 1)
			}),
			AddThemeObject(SetProps(MakeElement("Label", LocalPlayer.DisplayName, WindowConfig.HidePremium and 14 or 13), {
				Size = UDim2.new(1, -60, 0, 13),
				Position = WindowConfig.HidePremium and UDim2.new(0, 50, 0, 19) or UDim2.new(0, 50, 0, 12),
				Font = Enum.Font.GothamBold,
				ClipsDescendants = true
			}), "Text"),
			AddThemeObject(SetProps(MakeElement("Label", "", 12), {
				Size = UDim2.new(1, -60, 0, 12),
				Position = UDim2.new(0, 50, 1, -25),
				Visible = not WindowConfig.HidePremium
			}), "TextDark")
		}),
	}), "Second")

	local WindowName = AddThemeObject(SetProps(MakeElement("Label", WindowConfig.Name, 14), {
		Size = UDim2.new(1, -30, 2, 0),
		Position = UDim2.new(0, 25, 0, -24),
		Font = Enum.Font.GothamBlack,
		TextSize = 20
	}), "Text")

	local WindowTopBarLine = AddThemeObject(SetProps(MakeElement("Frame"), {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1)
	}), "Stroke")

	local MainWindow = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 10), {
		Parent = Orion,
		Position = UDim2.new(0.5, -307, 0.5, -172),
		Size = UDim2.new(0, 615, 0, 344),
		ClipsDescendants = true
	}), {
		--SetProps(MakeElement("Image", "rbxassetid://3523728077"), {
		--	AnchorPoint = Vector2.new(0.5, 0.5),
		--	Position = UDim2.new(0.5, 0, 0.5, 0),
		--	Size = UDim2.new(1, 80, 1, 320),
		--	ImageColor3 = Color3.fromRGB(33, 33, 33),
		--	ImageTransparency = 0.7
		--}),
		SetChildren(SetProps(MakeElement("TFrame"), {
			Size = UDim2.new(1, 0, 0, 50),
			Name = "TopBar"
		}), {
			WindowName,
			WindowTopBarLine,
			AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 7), {
				Size = UDim2.new(0, 70, 0, 30),
				Position = UDim2.new(1, -90, 0, 10)
			}), {
				AddThemeObject(MakeElement("Stroke"), "Stroke"),
				AddThemeObject(SetProps(MakeElement("Frame"), {
					Size = UDim2.new(0, 1, 1, 0),
					Position = UDim2.new(0.5, 0, 0, 0)
				}), "Stroke"), 
				CloseBtn,
				MinimizeBtn
			}), "Second"), 
		}),
		DragPoint,
		WindowStuff
	}), "Main")

	if WindowConfig.ShowIcon then
		WindowName.Position = UDim2.new(0, 50, 0, -24)
		local WindowIcon = SetProps(MakeElement("Image", WindowConfig.Icon), {
			Size = UDim2.new(0, 20, 0, 20),
			Position = UDim2.new(0, 25, 0, 15)
		})
		WindowIcon.Parent = MainWindow.TopBar
	end	

	AddDraggingFunctionality(DragPoint, MainWindow)

	AddConnection(CloseBtn.MouseButton1Up, function()
		MainWindow.Visible = false
		UIHidden = true
		OrionLib:MakeNotification({
			Name = "Interface Hidden",
			Content = "Tap RightShift to reopen the interface",
			Time = 5
		})
		WindowConfig.CloseCallback()
	end)

	AddConnection(UserInputService.InputBegan, function(Input)
		if Input.KeyCode == Enum.KeyCode.RightShift and UIHidden then
			MainWindow.Visible = true
		end
	end)

	AddConnection(MinimizeBtn.MouseButton1Up, function()
		if Minimized then
			TweenService:Create(MainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0, 615, 0, 344)}):Play()
			MinimizeBtn.Ico.Image = "rbxassetid://7072719338"
			wait(.02)
			MainWindow.ClipsDescendants = false
			WindowStuff.Visible = true
			WindowTopBarLine.Visible = true
		else
			MainWindow.ClipsDescendants = true
			WindowTopBarLine.Visible = false
			MinimizeBtn.Ico.Image = "rbxassetid://7072720870"

			TweenService:Create(MainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0, WindowName.TextBounds.X + 140, 0, 50)}):Play()
			wait(0.1)
			WindowStuff.Visible = false	
		end
		Minimized = not Minimized    
	end)

	local function LoadSequence()
		MainWindow.Visible = false
		local LoadSequenceLogo = SetProps(MakeElement("Image", WindowConfig.IntroIcon), {
			Parent = Orion,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.4, 0),
			Size = UDim2.new(0, 28, 0, 28),
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			ImageTransparency = 1
		})

		local LoadSequenceText = SetProps(MakeElement("Label", WindowConfig.IntroText, 14), {
			Parent = Orion,
			Size = UDim2.new(1, 0, 1, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 19, 0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold,
			TextTransparency = 1
		})

		TweenService:Create(LoadSequenceLogo, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
		wait(0.8)
		TweenService:Create(LoadSequenceLogo, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, -(LoadSequenceText.TextBounds.X/2), 0.5, 0)}):Play()
		wait(0.3)
		TweenService:Create(LoadSequenceText, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
		wait(2)
		TweenService:Create(LoadSequenceText, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1}):Play()
		MainWindow.Visible = true
		LoadSequenceLogo:Destroy()
		LoadSequenceText:Destroy()
	end 

	if WindowConfig.IntroEnabled then
		LoadSequence()
	end	

	local TabFunction = {}
	function TabFunction:MakeTab(TabConfig)
		TabConfig = TabConfig or {}
		TabConfig.Name = TabConfig.Name or "Tab"
		TabConfig.Icon = TabConfig.Icon or ""
		TabConfig.PremiumOnly = TabConfig.PremiumOnly or false

		local TabFrame = SetChildren(SetProps(MakeElement("Button"), {
			Size = UDim2.new(1, 0, 0, 30),
			Parent = TabHolder
		}), {
			AddThemeObject(SetProps(MakeElement("Image", TabConfig.Icon), {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(0, 18, 0, 18),
				Position = UDim2.new(0, 10, 0.5, 0),
				ImageTransparency = 0.4,
				Name = "Ico"
			}), "Text"),
			AddThemeObject(SetProps(MakeElement("Label", TabConfig.Name, 14), {
				Size = UDim2.new(1, -35, 1, 0),
				Position = UDim2.new(0, 35, 0, 0),
				Font = Enum.Font.GothamSemibold,
				TextTransparency = 0.4,
				Name = "Title"
			}), "Text")
		})

		if GetIcon(TabConfig.Icon) ~= nil then
			TabFrame.Ico.Image = GetIcon(TabConfig.Icon)
		end	

		local Container = AddThemeObject(SetChildren(SetProps(MakeElement("ScrollFrame", Color3.fromRGB(255, 255, 255), 5), {
			Size = UDim2.new(1, -150, 1, -50),
			Position = UDim2.new(0, 150, 0, 50),
			Parent = MainWindow,
			Visible = false,
			Name = "ItemContainer"
		}), {
			MakeElement("List", 0, 6),
			MakeElement("Padding", 15, 10, 10, 15)
		}), "Divider")

		AddConnection(Container.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Container.CanvasSize = UDim2.new(0, 0, 0, Container.UIListLayout.AbsoluteContentSize.Y + 30)
		end)

		if FirstTab then
			FirstTab = false
			TabFrame.Ico.ImageTransparency = 0
			TabFrame.Title.TextTransparency = 0
			TabFrame.Title.Font = Enum.Font.GothamBlack
			Container.Visible = true
		end    

		AddConnection(TabFrame.MouseButton1Click, function()
			for _, Tab in next, TabHolder:GetChildren() do
				if Tab:IsA("TextButton") then
					Tab.Title.Font = Enum.Font.GothamSemibold
					TweenService:Create(Tab.Ico, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0.4}):Play()
					TweenService:Create(Tab.Title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency = 0.4}):Play()
				end    
			end
			for _, ItemContainer in next, MainWindow:GetChildren() do
				if ItemContainer.Name == "ItemContainer" then
					ItemContainer.Visible = false
				end    
			end  
			TweenService:Create(TabFrame.Ico, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0}):Play()
			TweenService:Create(TabFrame.Title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
			TabFrame.Title.Font = Enum.Font.GothamBlack
			Container.Visible = true   
		end)

		local function GetElements(ItemParent)
			local ElementFunction = {}
			function ElementFunction:AddLabel(Text)
				local LabelFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 0.7,
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", Text, 15), {
						Size = UDim2.new(1, -12, 1, 0),
						Position = UDim2.new(0, 12, 0, 0),
						Font = Enum.Font.GothamBold,
						Name = "Content"
					}), "Text"),
					AddThemeObject(MakeElement("Stroke"), "Stroke")
				}), "Second")

				local LabelFunction = {}
				function LabelFunction:Set(ToChange)
					LabelFrame.Content.Text = ToChange
				end
				return LabelFunction
			end
			function ElementFunction:AddParagraph(Text, Content)
				Text = Text or "Text"
				Content = Content or "Content"

				local ParagraphFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 0.7,
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", Text, 15), {
						Size = UDim2.new(1, -12, 0, 14),
						Position = UDim2.new(0, 12, 0, 10),
						Font = Enum.Font.GothamBold,
						Name = "Title"
					}), "Text"),
					AddThemeObject(SetProps(MakeElement("Label", "", 13), {
						Size = UDim2.new(1, -24, 0, 0),
						Position = UDim2.new(0, 12, 0, 26),
						Font = Enum.Font.GothamSemibold,
						Name = "Content",
						TextWrapped = true
					}), "TextDark"),
					AddThemeObject(MakeElement("Stroke"), "Stroke")
				}), "Second")

				AddConnection(ParagraphFrame.Content:GetPropertyChangedSignal("Text"), function()
					ParagraphFrame.Content.Size = UDim2.new(1, -24, 0, ParagraphFrame.Content.TextBounds.Y)
					ParagraphFrame.Size = UDim2.new(1, 0, 0, ParagraphFrame.Content.TextBounds.Y + 35)
				end)

				ParagraphFrame.Content.Text = Content

				local ParagraphFunction = {}
				function ParagraphFunction:Set(ToChange)
					ParagraphFrame.Content.Text = ToChange
				end
				return ParagraphFunction
			end    
			function ElementFunction:AddButton(ButtonConfig)
				ButtonConfig = ButtonConfig or {}
				ButtonConfig.Name = ButtonConfig.Name or "Button"
				ButtonConfig.Callback = ButtonConfig.Callback or function() end
				ButtonConfig.Icon = ButtonConfig.Icon or "rbxassetid://3944703587"

				local Button = {}

				local Click = SetProps(MakeElement("Button"), {
					Size = UDim2.new(1, 0, 1, 0)
				})

				local ButtonFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 33),
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", ButtonConfig.Name, 15), {
						Size = UDim2.new(1, -12, 1, 0),
						Position = UDim2.new(0, 12, 0, 0),
						Font = Enum.Font.GothamBold,
						Name = "Content"
					}), "Text"),
					AddThemeObject(SetProps(MakeElement("Image", ButtonConfig.Icon), {
						Size = UDim2.new(0, 20, 0, 20),
						Position = UDim2.new(1, -30, 0, 7),
					}), "TextDark"),
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					Click
				}), "Second")

				AddConnection(Click.MouseEnter, function()
					TweenService:Create(ButtonFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
				end)

				AddConnection(Click.MouseLeave, function()
					TweenService:Create(ButtonFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = OrionLib.Themes[OrionLib.SelectedTheme].Second}):Play()
				end)

				AddConnection(Click.MouseButton1Up, function()
					TweenService:Create(ButtonFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
					spawn(function()
						ButtonConfig.Callback()
					end)
				end)

				AddConnection(Click.MouseButton1Down, function()
					TweenService:Create(ButtonFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 6)}):Play()
				end)

				function Button:Set(ButtonText)
					ButtonFrame.Content.Text = ButtonText
				end	

				return Button
			end    
			function ElementFunction:AddToggle(ToggleConfig)
				ToggleConfig = ToggleConfig or {}
				ToggleConfig.Name = ToggleConfig.Name or "Toggle"
				ToggleConfig.Default = ToggleConfig.Default or false
				ToggleConfig.Callback = ToggleConfig.Callback or function() end
				ToggleConfig.Color = ToggleConfig.Color or Color3.fromRGB(9, 99, 195)
				ToggleConfig.Flag = ToggleConfig.Flag or nil
				ToggleConfig.Save = ToggleConfig.Save or false

				local Toggle = {Value = ToggleConfig.Default, Save = ToggleConfig.Save}

				local Click = SetProps(MakeElement("Button"), {
					Size = UDim2.new(1, 0, 1, 0)
				})

				local ToggleBox = SetChildren(SetProps(MakeElement("RoundFrame", ToggleConfig.Color, 0, 4), {
					Size = UDim2.new(0, 24, 0, 24),
					Position = UDim2.new(1, -24, 0.5, 0),
					AnchorPoint = Vector2.new(0.5, 0.5)
				}), {
					SetProps(MakeElement("Stroke"), {
						Color = ToggleConfig.Color,
						Name = "Stroke",
						Transparency = 0.5
					}),
					SetProps(MakeElement("Image", "rbxassetid://3944680095"), {
						Size = UDim2.new(0, 20, 0, 20),
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						ImageColor3 = Color3.fromRGB(255, 255, 255),
						Name = "Ico"
					}),
				})

				local ToggleFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 38),
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", ToggleConfig.Name, 15), {
						Size = UDim2.new(1, -12, 1, 0),
						Position = UDim2.new(0, 12, 0, 0),
						Font = Enum.Font.GothamBold,
						Name = "Content"
					}), "Text"),
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					ToggleBox,
					Click
				}), "Second")

				function Toggle:Set(Value)
					Toggle.Value = Value
					TweenService:Create(ToggleBox, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Toggle.Value and ToggleConfig.Color or OrionLib.Themes.Default.Divider}):Play()
					TweenService:Create(ToggleBox.Stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Color = Toggle.Value and ToggleConfig.Color or OrionLib.Themes.Default.Stroke}):Play()
					TweenService:Create(ToggleBox.Ico, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = Toggle.Value and 0 or 1, Size = Toggle.Value and UDim2.new(0, 20, 0, 20) or UDim2.new(0, 8, 0, 8)}):Play()
					ToggleConfig.Callback(Toggle.Value)
				end    

				Toggle:Set(Toggle.Value)

				AddConnection(Click.MouseEnter, function()
					TweenService:Create(ToggleFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
				end)

				AddConnection(Click.MouseLeave, function()
					TweenService:Create(ToggleFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = OrionLib.Themes[OrionLib.SelectedTheme].Second}):Play()
				end)

				AddConnection(Click.MouseButton1Up, function()
					TweenService:Create(ToggleFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
					SaveCfg(game.GameId)
					Toggle:Set(not Toggle.Value)
				end)

				AddConnection(Click.MouseButton1Down, function()
					TweenService:Create(ToggleFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 6)}):Play()
				end)

				if ToggleConfig.Flag then
					OrionLib.Flags[ToggleConfig.Flag] = Toggle
				end	
				return Toggle
			end  
			function ElementFunction:AddSlider(SliderConfig)
				SliderConfig = SliderConfig or {}
				SliderConfig.Name = SliderConfig.Name or "Slider"
				SliderConfig.Min = SliderConfig.Min or 0
				SliderConfig.Max = SliderConfig.Max or 100
				SliderConfig.Increment = SliderConfig.Increment or 1
				SliderConfig.Default = SliderConfig.Default or 50
				SliderConfig.Callback = SliderConfig.Callback or function() end
				SliderConfig.ValueName = SliderConfig.ValueName or ""
				SliderConfig.Color = SliderConfig.Color or Color3.fromRGB(9, 149, 98)
				SliderConfig.Flag = SliderConfig.Flag or nil
				SliderConfig.Save = SliderConfig.Save or false

				local Slider = {Value = SliderConfig.Default, Save = SliderConfig.Save}
				local Dragging = false

				local SliderDrag = SetChildren(SetProps(MakeElement("RoundFrame", SliderConfig.Color, 0, 5), {
					Size = UDim2.new(0, 0, 1, 0),
					BackgroundTransparency = 0.3,
					ClipsDescendants = true
				}), {
					AddThemeObject(SetProps(MakeElement("Label", "value", 13), {
						Size = UDim2.new(1, -12, 0, 14),
						Position = UDim2.new(0, 12, 0, 6),
						Font = Enum.Font.GothamBold,
						Name = "Value",
						TextTransparency = 0
					}), "Text")
				})

				local SliderBar = SetChildren(SetProps(MakeElement("RoundFrame", SliderConfig.Color, 0, 5), {
					Size = UDim2.new(1, -24, 0, 26),
					Position = UDim2.new(0, 12, 0, 30),
					BackgroundTransparency = 0.9
				}), {
					SetProps(MakeElement("Stroke"), {
						Color = SliderConfig.Color
					}),
					AddThemeObject(SetProps(MakeElement("Label", "value", 13), {
						Size = UDim2.new(1, -12, 0, 14),
						Position = UDim2.new(0, 12, 0, 6),
						Font = Enum.Font.GothamBold,
						Name = "Value",
						TextTransparency = 0.8
					}), "Text"),
					SliderDrag
				})

				local SliderFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 4), {
					Size = UDim2.new(1, 0, 0, 65),
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", SliderConfig.Name, 15), {
						Size = UDim2.new(1, -12, 0, 14),
						Position = UDim2.new(0, 12, 0, 10),
						Font = Enum.Font.GothamBold,
						Name = "Content"
					}), "Text"),
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					SliderBar
				}), "Second")

				SliderBar.InputBegan:Connect(function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then 
						Dragging = true 
					end 
				end)
				SliderBar.InputEnded:Connect(function(Input) 
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then 
						Dragging = false 
					end 
				end)

				UserInputService.InputChanged:Connect(function(Input)
					if Dragging and Input.UserInputType == Enum.UserInputType.MouseMovement then 
						local SizeScale = math.clamp((Input.Position.X - SliderBar.AbsolutePosition.X) / SliderBar.AbsoluteSize.X, 0, 1)
						Slider:Set(SliderConfig.Min + ((SliderConfig.Max - SliderConfig.Min) * SizeScale)) 
						SaveCfg(game.GameId)
					end
				end)

				function Slider:Set(Value)
					self.Value = math.clamp(Round(Value, SliderConfig.Increment), SliderConfig.Min, SliderConfig.Max)
					TweenService:Create(SliderDrag,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{Size = UDim2.fromScale((self.Value - SliderConfig.Min) / (SliderConfig.Max - SliderConfig.Min), 1)}):Play()
					SliderBar.Value.Text = tostring(self.Value) .. " " .. SliderConfig.ValueName
					SliderDrag.Value.Text = tostring(self.Value) .. " " .. SliderConfig.ValueName
					SliderConfig.Callback(self.Value)
				end      

				Slider:Set(Slider.Value)
				if SliderConfig.Flag then				
					OrionLib.Flags[SliderConfig.Flag] = Slider
				end
				return Slider
			end  
			function ElementFunction:AddDropdown(DropdownConfig)
				DropdownConfig = DropdownConfig or {}
				DropdownConfig.Name = DropdownConfig.Name or "Dropdown"
				DropdownConfig.Options = DropdownConfig.Options or {}
				DropdownConfig.Default = DropdownConfig.Default or ""
				DropdownConfig.Callback = DropdownConfig.Callback or function() end
				DropdownConfig.Flag = DropdownConfig.Flag or nil
				DropdownConfig.Save = DropdownConfig.Save or false

				local Dropdown = {Value = DropdownConfig.Default, Options = DropdownConfig.Options, Buttons = {}, Toggled = false, Type = "Dropdown", Save = DropdownConfig.Save}
				local MaxElements = 5

				if not table.find(Dropdown.Options, Dropdown.Value) then
					Dropdown.Value = "..."
				end

				local DropdownList = MakeElement("List")

				local DropdownContainer = AddThemeObject(SetProps(SetChildren(MakeElement("ScrollFrame", Color3.fromRGB(40, 40, 40), 4), {
					DropdownList
				}), {
					Parent = ItemParent,
					Position = UDim2.new(0, 0, 0, 38),
					Size = UDim2.new(1, 0, 1, -38),
					ClipsDescendants = true
				}), "Divider")

				local Click = SetProps(MakeElement("Button"), {
					Size = UDim2.new(1, 0, 1, 0)
				})

				local DropdownFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 38),
					Parent = ItemParent,
					ClipsDescendants = true
				}), {
					DropdownContainer,
					SetProps(SetChildren(MakeElement("TFrame"), {
						AddThemeObject(SetProps(MakeElement("Label", DropdownConfig.Name, 15), {
							Size = UDim2.new(1, -12, 1, 0),
							Position = UDim2.new(0, 12, 0, 0),
							Font = Enum.Font.GothamBold,
							Name = "Content"
						}), "Text"),
						AddThemeObject(SetProps(MakeElement("Image", "rbxassetid://7072706796"), {
							Size = UDim2.new(0, 20, 0, 20),
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(1, -30, 0.5, 0),
							ImageColor3 = Color3.fromRGB(240, 240, 240),
							Name = "Ico"
						}), "TextDark"),
						AddThemeObject(SetProps(MakeElement("Label", "Selected", 13), {
							Size = UDim2.new(1, -40, 1, 0),
							Font = Enum.Font.Gotham,
							Name = "Selected",
							TextXAlignment = Enum.TextXAlignment.Right
						}), "TextDark"),
						AddThemeObject(SetProps(MakeElement("Frame"), {
							Size = UDim2.new(1, 0, 0, 1),
							Position = UDim2.new(0, 0, 1, -1),
							Name = "Line",
							Visible = false
						}), "Stroke"), 
						Click
					}), {
						Size = UDim2.new(1, 0, 0, 38),
						ClipsDescendants = true,
						Name = "F"
					}),
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					MakeElement("Corner")
				}), "Second")

				AddConnection(DropdownList:GetPropertyChangedSignal("AbsoluteContentSize"), function()
					DropdownContainer.CanvasSize = UDim2.new(0, 0, 0, DropdownList.AbsoluteContentSize.Y)
				end)  

				local function AddOptions(Options)
					for _, Option in pairs(Options) do
						local OptionBtn = AddThemeObject(SetProps(SetChildren(MakeElement("Button", Color3.fromRGB(40, 40, 40)), {
							MakeElement("Corner", 0, 6),
							AddThemeObject(SetProps(MakeElement("Label", Option, 13, 0.4), {
								Position = UDim2.new(0, 8, 0, 0),
								Size = UDim2.new(1, -8, 1, 0),
								Name = "Title"
							}), "Text")
						}), {
							Parent = DropdownContainer,
							Size = UDim2.new(1, 0, 0, 28),
							BackgroundTransparency = 1,
							ClipsDescendants = true
						}), "Divider")

						AddConnection(OptionBtn.MouseButton1Click, function()
							Dropdown:Set(Option)
							SaveCfg(game.GameId)
						end)

						Dropdown.Buttons[Option] = OptionBtn
					end
				end	

				function Dropdown:Refresh(Options, Delete)
					if Delete then
						for _,v in pairs(Dropdown.Buttons) do
							v:Destroy()
						end    
						table.clear(Dropdown.Options)
						table.clear(Dropdown.Buttons)
					end
					Dropdown.Options = Options
					AddOptions(Dropdown.Options)
				end  

				function Dropdown:Set(Value)
					if not table.find(Dropdown.Options, Value) then
						Dropdown.Value = "..."
						DropdownFrame.F.Selected.Text = Dropdown.Value
						for _, v in pairs(Dropdown.Buttons) do
							TweenService:Create(v,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{BackgroundTransparency = 1}):Play()
							TweenService:Create(v.Title,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{TextTransparency = 0.4}):Play()
						end	
						return
					end

					Dropdown.Value = Value
					DropdownFrame.F.Selected.Text = Dropdown.Value

					for _, v in pairs(Dropdown.Buttons) do
						TweenService:Create(v,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{BackgroundTransparency = 1}):Play()
						TweenService:Create(v.Title,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{TextTransparency = 0.4}):Play()
					end	
					TweenService:Create(Dropdown.Buttons[Value],TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{BackgroundTransparency = 0}):Play()
					TweenService:Create(Dropdown.Buttons[Value].Title,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{TextTransparency = 0}):Play()
					return DropdownConfig.Callback(Dropdown.Value)
				end

				AddConnection(Click.MouseButton1Click, function()
					Dropdown.Toggled = not Dropdown.Toggled
					DropdownFrame.F.Line.Visible = Dropdown.Toggled
					TweenService:Create(DropdownFrame.F.Ico,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{Rotation = Dropdown.Toggled and 180 or 0}):Play()
					if #Dropdown.Options > MaxElements then
						TweenService:Create(DropdownFrame,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{Size = Dropdown.Toggled and UDim2.new(1, 0, 0, 38 + (MaxElements * 28)) or UDim2.new(1, 0, 0, 38)}):Play()
					else
						TweenService:Create(DropdownFrame,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{Size = Dropdown.Toggled and UDim2.new(1, 0, 0, DropdownList.AbsoluteContentSize.Y + 38) or UDim2.new(1, 0, 0, 38)}):Play()
					end
				end)

				Dropdown:Refresh(Dropdown.Options, false)
				Dropdown:Set(Dropdown.Value)
				if DropdownConfig.Flag then				
					OrionLib.Flags[DropdownConfig.Flag] = Dropdown
				end
				return Dropdown
			end
			function ElementFunction:AddBind(BindConfig)
				BindConfig.Name = BindConfig.Name or "Bind"
				BindConfig.Default = BindConfig.Default or Enum.KeyCode.Unknown
				BindConfig.Hold = BindConfig.Hold or false
				BindConfig.Callback = BindConfig.Callback or function() end
				BindConfig.Flag = BindConfig.Flag or nil
				BindConfig.Save = BindConfig.Save or false

				local Bind = {Value = nil, Binding = false, Type = "Bind", Save = BindConfig.Save}
				local Holding = false

				local Click = SetProps(MakeElement("Button"), {
					Size = UDim2.new(1, 0, 1, 0)
				})

				local BindBox = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 4), {
					Size = UDim2.new(0, 24, 0, 24),
					Position = UDim2.new(1, -12, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5)
				}), {
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					AddThemeObject(SetProps(MakeElement("Label", BindConfig.Name, 14), {
						Size = UDim2.new(1, 0, 1, 0),
						Font = Enum.Font.GothamBold,
						TextXAlignment = Enum.TextXAlignment.Center,
						Name = "Value"
					}), "Text")
				}), "Main")

				local BindFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 38),
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", BindConfig.Name, 15), {
						Size = UDim2.new(1, -12, 1, 0),
						Position = UDim2.new(0, 12, 0, 0),
						Font = Enum.Font.GothamBold,
						Name = "Content"
					}), "Text"),
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					BindBox,
					Click
				}), "Second")

				AddConnection(BindBox.Value:GetPropertyChangedSignal("Text"), function()
					--BindBox.Size = UDim2.new(0, BindBox.Value.TextBounds.X + 16, 0, 24)
					TweenService:Create(BindBox, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0, BindBox.Value.TextBounds.X + 16, 0, 24)}):Play()
				end)

				AddConnection(Click.InputEnded, function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						if Bind.Binding then return end
						Bind.Binding = true
						BindBox.Value.Text = ""
					end
				end)

				AddConnection(UserInputService.InputBegan, function(Input)
					if UserInputService:GetFocusedTextBox() then return end
					if (Input.KeyCode.Name == Bind.Value or Input.UserInputType.Name == Bind.Value) and not Bind.Binding then
						if BindConfig.Hold then
							Holding = true
							BindConfig.Callback(Holding)
						else
							BindConfig.Callback()
						end
					elseif Bind.Binding then
						local Key
						pcall(function()
							if not CheckKey(BlacklistedKeys, Input.KeyCode) then
								Key = Input.KeyCode
							end
						end)
						pcall(function()
							if CheckKey(WhitelistedMouse, Input.UserInputType) and not Key then
								Key = Input.UserInputType
							end
						end)
						Key = Key or Bind.Value
						Bind:Set(Key)
						SaveCfg(game.GameId)
					end
				end)

				AddConnection(UserInputService.InputEnded, function(Input)
					if Input.KeyCode.Name == Bind.Value or Input.UserInputType.Name == Bind.Value then
						if BindConfig.Hold and Holding then
							Holding = false
							BindConfig.Callback(Holding)
						end
					end
				end)

				AddConnection(Click.MouseEnter, function()
					TweenService:Create(BindFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
				end)

				AddConnection(Click.MouseLeave, function()
					TweenService:Create(BindFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = OrionLib.Themes[OrionLib.SelectedTheme].Second}):Play()
				end)

				AddConnection(Click.MouseButton1Up, function()
					TweenService:Create(BindFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
				end)

				AddConnection(Click.MouseButton1Down, function()
					TweenService:Create(BindFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 6)}):Play()
				end)

				function Bind:Set(Key)
					Bind.Binding = false
					Bind.Value = Key or Bind.Value
					Bind.Value = Bind.Value.Name or Bind.Value
					BindBox.Value.Text = Bind.Value
				end

				Bind:Set(BindConfig.Default)
				if BindConfig.Flag then				
					OrionLib.Flags[BindConfig.Flag] = Bind
				end
				return Bind
			end  
			function ElementFunction:AddTextbox(TextboxConfig)
				TextboxConfig = TextboxConfig or {}
				TextboxConfig.Name = TextboxConfig.Name or "Textbox"
				TextboxConfig.Default = TextboxConfig.Default or ""
				TextboxConfig.TextDisappear = TextboxConfig.TextDisappear or false
				TextboxConfig.Callback = TextboxConfig.Callback or function() end

				local Click = SetProps(MakeElement("Button"), {
					Size = UDim2.new(1, 0, 1, 0)
				})

				local TextboxActual = AddThemeObject(Create("TextBox", {
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					PlaceholderColor3 = Color3.fromRGB(210,210,210),
					PlaceholderText = "Input",
					Font = Enum.Font.GothamSemibold,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextSize = 14,
					ClearTextOnFocus = false
				}), "Text")

				local TextContainer = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 4), {
					Size = UDim2.new(0, 24, 0, 24),
					Position = UDim2.new(1, -12, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5)
				}), {
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					TextboxActual
				}), "Main")


				local TextboxFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 38),
					Parent = ItemParent
				}), {
					AddThemeObject(SetProps(MakeElement("Label", TextboxConfig.Name, 15), {
						Size = UDim2.new(1, -12, 1, 0),
						Position = UDim2.new(0, 12, 0, 0),
						Font = Enum.Font.GothamBold,
						Name = "Content"
					}), "Text"),
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
					TextContainer,
					Click
				}), "Second")

				AddConnection(TextboxActual:GetPropertyChangedSignal("Text"), function()
					--TextContainer.Size = UDim2.new(0, TextboxActual.TextBounds.X + 16, 0, 24)
					TweenService:Create(TextContainer, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0, TextboxActual.TextBounds.X + 16, 0, 24)}):Play()
				end)

				AddConnection(TextboxActual.FocusLost, function()
					TextboxConfig.Callback(TextboxActual.Text)
					if TextboxConfig.TextDisappear then
						TextboxActual.Text = ""
					end	
				end)

				TextboxActual.Text = TextboxConfig.Default

				AddConnection(Click.MouseEnter, function()
					TweenService:Create(TextboxFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
				end)

				AddConnection(Click.MouseLeave, function()
					TweenService:Create(TextboxFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = OrionLib.Themes[OrionLib.SelectedTheme].Second}):Play()
				end)

				AddConnection(Click.MouseButton1Up, function()
					TweenService:Create(TextboxFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 3, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 3)}):Play()
					TextboxActual:CaptureFocus()
				end)

				AddConnection(Click.MouseButton1Down, function()
					TweenService:Create(TextboxFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(OrionLib.Themes[OrionLib.SelectedTheme].Second.R * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.G * 255 + 6, OrionLib.Themes[OrionLib.SelectedTheme].Second.B * 255 + 6)}):Play()
				end)
			end 
			function ElementFunction:AddColorpicker(ColorpickerConfig)
				ColorpickerConfig = ColorpickerConfig or {}
				ColorpickerConfig.Name = ColorpickerConfig.Name or "Colorpicker"
				ColorpickerConfig.Default = ColorpickerConfig.Default or Color3.fromRGB(255,255,255)
				ColorpickerConfig.Callback = ColorpickerConfig.Callback or function() end
				ColorpickerConfig.Flag = ColorpickerConfig.Flag or nil
				ColorpickerConfig.Save = ColorpickerConfig.Save or false

				local ColorH, ColorS, ColorV = 1, 1, 1
				local Colorpicker = {Value = ColorpickerConfig.Default, Toggled = false, Type = "Colorpicker", Save = ColorpickerConfig.Save}

				local ColorSelection = Create("ImageLabel", {
					Size = UDim2.new(0, 18, 0, 18),
					Position = UDim2.new(select(3, Color3.toHSV(Colorpicker.Value))),
					ScaleType = Enum.ScaleType.Fit,
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = "http://www.roblox.com/asset/?id=4805639000"
				})

				local HueSelection = Create("ImageLabel", {
					Size = UDim2.new(0, 18, 0, 18),
					Position = UDim2.new(0.5, 0, 1 - select(1, Color3.toHSV(Colorpicker.Value))),
					ScaleType = Enum.ScaleType.Fit,
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = "http://www.roblox.com/asset/?id=4805639000"
				})

				local Color = Create("ImageLabel", {
					Size = UDim2.new(1, -25, 1, 0),
					Visible = false,
					Image = "rbxassetid://4155801252"
				}, {
					Create("UICorner", {CornerRadius = UDim.new(0, 5)}),
					ColorSelection
				})

				local Hue = Create("Frame", {
					Size = UDim2.new(0, 20, 1, 0),
					Position = UDim2.new(1, -20, 0, 0),
					Visible = false
				}, {
					Create("UIGradient", {Rotation = 270, Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 4)), ColorSequenceKeypoint.new(0.20, Color3.fromRGB(234, 255, 0)), ColorSequenceKeypoint.new(0.40, Color3.fromRGB(21, 255, 0)), ColorSequenceKeypoint.new(0.60, Color3.fromRGB(0, 255, 255)), ColorSequenceKeypoint.new(0.80, Color3.fromRGB(0, 17, 255)), ColorSequenceKeypoint.new(0.90, Color3.fromRGB(255, 0, 251)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 4))},}),
					Create("UICorner", {CornerRadius = UDim.new(0, 5)}),
					HueSelection
				})

				local ColorpickerContainer = Create("Frame", {
					Position = UDim2.new(0, 0, 0, 32),
					Size = UDim2.new(1, 0, 1, -32),
					BackgroundTransparency = 1,
					ClipsDescendants = true
				}, {
					Hue,
					Color,
					Create("UIPadding", {
						PaddingLeft = UDim.new(0, 35),
						PaddingRight = UDim.new(0, 35),
						PaddingBottom = UDim.new(0, 10),
						PaddingTop = UDim.new(0, 17)
					})
				})

				local Click = SetProps(MakeElement("Button"), {
					Size = UDim2.new(1, 0, 1, 0)
				})

				local ColorpickerBox = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 4), {
					Size = UDim2.new(0, 24, 0, 24),
					Position = UDim2.new(1, -12, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5)
				}), {
					AddThemeObject(MakeElement("Stroke"), "Stroke")
				}), "Main")

				local ColorpickerFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", Color3.fromRGB(255, 255, 255), 0, 5), {
					Size = UDim2.new(1, 0, 0, 38),
					Parent = ItemParent
				}), {
					SetProps(SetChildren(MakeElement("TFrame"), {
						AddThemeObject(SetProps(MakeElement("Label", ColorpickerConfig.Name, 15), {
							Size = UDim2.new(1, -12, 1, 0),
							Position = UDim2.new(0, 12, 0, 0),
							Font = Enum.Font.GothamBold,
							Name = "Content"
						}), "Text"),
						ColorpickerBox,
						Click,
						AddThemeObject(SetProps(MakeElement("Frame"), {
							Size = UDim2.new(1, 0, 0, 1),
							Position = UDim2.new(0, 0, 1, -1),
							Name = "Line",
							Visible = false
						}), "Stroke"), 
					}), {
						Size = UDim2.new(1, 0, 0, 38),
						ClipsDescendants = true,
						Name = "F"
					}),
					ColorpickerContainer,
					AddThemeObject(MakeElement("Stroke"), "Stroke"),
				}), "Second")

				AddConnection(Click.MouseButton1Click, function()
					Colorpicker.Toggled = not Colorpicker.Toggled
					TweenService:Create(ColorpickerFrame,TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),{Size = Colorpicker.Toggled and UDim2.new(1, 0, 0, 148) or UDim2.new(1, 0, 0, 38)}):Play()
					Color.Visible = Colorpicker.Toggled
					Hue.Visible = Colorpicker.Toggled
					ColorpickerFrame.F.Line.Visible = Colorpicker.Toggled
				end)

				local function UpdateColorPicker()
					ColorpickerBox.BackgroundColor3 = Color3.fromHSV(ColorH, ColorS, ColorV)
					Color.BackgroundColor3 = Color3.fromHSV(ColorH, 1, 1)
					Colorpicker:Set(ColorpickerBox.BackgroundColor3)
					ColorpickerConfig.Callback(ColorpickerBox.BackgroundColor3)
					SaveCfg(game.GameId)
				end

				ColorH = 1 - (math.clamp(HueSelection.AbsolutePosition.Y - Hue.AbsolutePosition.Y, 0, Hue.AbsoluteSize.Y) / Hue.AbsoluteSize.Y)
				ColorS = (math.clamp(ColorSelection.AbsolutePosition.X - Color.AbsolutePosition.X, 0, Color.AbsoluteSize.X) / Color.AbsoluteSize.X)
				ColorV = 1 - (math.clamp(ColorSelection.AbsolutePosition.Y - Color.AbsolutePosition.Y, 0, Color.AbsoluteSize.Y) / Color.AbsoluteSize.Y)

				local ColorInput, HueInput

				AddConnection(Color.InputBegan, function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if ColorInput then
							ColorInput:Disconnect()
						end
						ColorInput = AddConnection(RunService.RenderStepped, function()
							local ColorX = (math.clamp(Mouse.X - Color.AbsolutePosition.X, 0, Color.AbsoluteSize.X) / Color.AbsoluteSize.X)
							local ColorY = (math.clamp(Mouse.Y - Color.AbsolutePosition.Y, 0, Color.AbsoluteSize.Y) / Color.AbsoluteSize.Y)
							ColorSelection.Position = UDim2.new(ColorX, 0, ColorY, 0)
							ColorS = ColorX
							ColorV = 1 - ColorY
							UpdateColorPicker()
						end)
					end
				end)

				AddConnection(Color.InputEnded, function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if ColorInput then
							ColorInput:Disconnect()
						end
					end
				end)

				AddConnection(Hue.InputBegan, function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if HueInput then
							HueInput:Disconnect()
						end;

						HueInput = AddConnection(RunService.RenderStepped, function()
							local HueY = (math.clamp(Mouse.Y - Hue.AbsolutePosition.Y, 0, Hue.AbsoluteSize.Y) / Hue.AbsoluteSize.Y)

							HueSelection.Position = UDim2.new(0.5, 0, HueY, 0)
							ColorH = 1 - HueY

							UpdateColorPicker()
						end)
					end
				end)

				AddConnection(Hue.InputEnded, function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if HueInput then
							HueInput:Disconnect()
						end
					end
				end)

				function Colorpicker:Set(Value)
					Colorpicker.Value = Value
					ColorpickerBox.BackgroundColor3 = Colorpicker.Value
					ColorpickerConfig.Callback(Colorpicker.Value)
				end

				Colorpicker:Set(Colorpicker.Value)
				if ColorpickerConfig.Flag then				
					OrionLib.Flags[ColorpickerConfig.Flag] = Colorpicker
				end
				return Colorpicker
			end  
			return ElementFunction   
		end	

		local ElementFunction = {}

		function ElementFunction:AddSection(SectionConfig)
			SectionConfig.Name = SectionConfig.Name or "Section"

			local SectionFrame = SetChildren(SetProps(MakeElement("TFrame"), {
				Size = UDim2.new(1, 0, 0, 26),
				Parent = Container
			}), {
				AddThemeObject(SetProps(MakeElement("Label", SectionConfig.Name, 14), {
					Size = UDim2.new(1, -12, 0, 16),
					Position = UDim2.new(0, 0, 0, 3),
					Font = Enum.Font.GothamSemibold
				}), "TextDark"),
				SetChildren(SetProps(MakeElement("TFrame"), {
					AnchorPoint = Vector2.new(0, 0),
					Size = UDim2.new(1, 0, 1, -24),
					Position = UDim2.new(0, 0, 0, 23),
					Name = "Holder"
				}), {
					MakeElement("List", 0, 6)
				}),
			})

			AddConnection(SectionFrame.Holder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
				SectionFrame.Size = UDim2.new(1, 0, 0, SectionFrame.Holder.UIListLayout.AbsoluteContentSize.Y + 31)
				SectionFrame.Holder.Size = UDim2.new(1, 0, 0, SectionFrame.Holder.UIListLayout.AbsoluteContentSize.Y)
			end)

			local SectionFunction = {}
			for i, v in next, GetElements(SectionFrame.Holder) do
				SectionFunction[i] = v 
			end
			return SectionFunction
		end	

		for i, v in next, GetElements(Container) do
			ElementFunction[i] = v 
		end

		if TabConfig.PremiumOnly then
			for i, v in next, ElementFunction do
				ElementFunction[i] = function() end
			end    
			Container:FindFirstChild("UIListLayout"):Destroy()
			Container:FindFirstChild("UIPadding"):Destroy()
			SetChildren(SetProps(MakeElement("TFrame"), {
				Size = UDim2.new(1, 0, 1, 0),
				Parent = Container
			}), {
				AddThemeObject(SetProps(MakeElement("Image", "rbxassetid://3610239960"), {
					Size = UDim2.new(0, 18, 0, 18),
					Position = UDim2.new(0, 15, 0, 15),
					ImageTransparency = 0.4
				}), "Text"),
				AddThemeObject(SetProps(MakeElement("Label", "Unauthorised Access", 14), {
					Size = UDim2.new(1, -38, 0, 14),
					Position = UDim2.new(0, 38, 0, 18),
					TextTransparency = 0.4
				}), "Text"),
				AddThemeObject(SetProps(MakeElement("Image", "rbxassetid://4483345875"), {
					Size = UDim2.new(0, 56, 0, 56),
					Position = UDim2.new(0, 84, 0, 110),
				}), "Text"),
				AddThemeObject(SetProps(MakeElement("Label", "Premium Features", 14), {
					Size = UDim2.new(1, -150, 0, 14),
					Position = UDim2.new(0, 150, 0, 112),
					Font = Enum.Font.GothamBold
				}), "Text"),
				AddThemeObject(SetProps(MakeElement("Label", "This part of the script is locked to Sirius Premium users. Purchase Premium in the Discord server (sirius.menu/discord)", 12), {
					Size = UDim2.new(1, -200, 0, 14),
					Position = UDim2.new(0, 150, 0, 138),
					TextWrapped = true,
					TextTransparency = 0.4
				}), "Text")
			})
		end
		return ElementFunction   
	end  
	
	-- Upgrade notification disabled
	

	
	return TabFunction
end   

function OrionLib:Destroy()
	Orion:Destroy()
end

return OrionLib

end

local OrionLib = nil
local orionSuccess, orionRes = pcall(LoadEmbeddedOrion)
if orionSuccess and type(orionRes) == "table" and orionRes.MakeWindow then
    OrionLib = orionRes
else
    warn("⚠️ [VHT HUB] Lỗi nạp Embedded Orion: " .. tostring(orionRes))
    -- Fallback nếu executor có môi trường đặc thù
    pcall(function()
        OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/jensonhirst/Orion/main/source"))()
    end)
end

if not OrionLib then
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "VHT HUB LỖI",
            Text = "Không thể khởi tạo Orion UI! Vui lòng kiểm tra executor.",
            Duration = 10
        })
    end)
    warn("❌ Không thể tải thư viện Orion UI!")
    return
end

local uiBuilding = true
local Window = OrionLib:MakeWindow({
    Name = "VHT HUB | Anime Dimensions",
    HidePremium = false,
    SaveConfig = false,
    IntroText = "VHT HUB Pro",
    IntroEnabled = false -- Tắt Intro animation để Menu hiển thị NGAY LẬP TỨC 100% không bị kẹt hay ẩn giao diện
})

-- ===================================================================
-- TAB 1: MAIN
-- ===================================================================
-- HỆ THỐNG ĐA NGÔN NGỮ (I18N MULTI-LANGUAGE SYSTEM: TIẾNG VIỆT & ENGLISH)
-- ===================================================================
local I18N = {
    -- Tabs
    ["Main"] = { ["Tiếng Việt"] = "Chính", ["English"] = "Main" },
    ["More"] = { ["Tiếng Việt"] = "Mở Rộng", ["English"] = "More" },
    ["Character"] = { ["Tiếng Việt"] = "Nhân Vật", ["English"] = "Character" },
    ["Setting"] = { ["Tiếng Việt"] = "Cài Đặt", ["English"] = "Setting" },
    ["Buy"] = { ["Tiếng Việt"] = "Cửa Hàng", ["English"] = "Buy" },
    ["Webhook"] = { ["Tiếng Việt"] = "Webhook", ["English"] = "Webhook" },
    ["Misc"] = { ["Tiếng Việt"] = "Tiện Ích", ["English"] = "Misc" },

    -- Tab 1: Main (Chính)
    ["Farming"] = { ["Tiếng Việt"] = "Cày Cuốc (Farming)", ["English"] = "Farming" },
    ["AutoJoinMap"] = { ["Tiếng Việt"] = "Tự Động Vào & Farm Map (Auto Join & Farm)", ["English"] = "Auto Join & Farm Map" },
    ["JoinMapNow"] = { ["Tiếng Việt"] = "Vào Map Ngay (Join Map Now)", ["English"] = "Join Map Now" },
    ["MapSelection(AutoUpdate!)"] = { ["Tiếng Việt"] = "Chọn Bản Đồ (Map Selection)", ["English"] = "Map Selection (Auto Update!)" },
    ["SelectDifficulty"] = { ["Tiếng Việt"] = "Chọn Độ Khó (Auto/Nightmare/Hard/Easy)", ["English"] = "Select Difficulty (Auto/Nightmare/Hard/Easy)" },
    ["WaitOnLobbyAfterJoin(OnlyNumber)"] = { ["Tiếng Việt"] = "Thời Gian Đợi Sảnh (Giây)", ["English"] = "Wait On Lobby After Join (Sec)" },
    ["WaitLobbyOnlyFirstTime"] = { ["Tiếng Việt"] = "Chỉ Đợi Sảnh Lần Đầu Tiên", ["English"] = "Wait Lobby Only First Time" },
    ["AutoPlay"] = { ["Tiếng Việt"] = "Tự Động Chơi (Auto Play)", ["English"] = "Auto Play" },
    ["Hardcore"] = { ["Tiếng Việt"] = "Chế Độ Khó (Hardcore)", ["English"] = "Hardcore" },
    ["AutoReplay"] = { ["Tiếng Việt"] = "Tự Động Chơi Lại (Auto Replay)", ["English"] = "Auto Replay" },
    ["FriendOnly"] = { ["Tiếng Việt"] = "Chỉ Bạn Bè (Friend Only)", ["English"] = "Friend Only" },
    ["AutoSelectMap(DetectedLevel)"] = { ["Tiếng Việt"] = "Tự Chọn Map & Độ Khó Theo LV & Sức Mạnh", ["English"] = "Auto Select Map & Diff (By Level & Power)" },
    ["Combat & Movement"] = { ["Tiếng Việt"] = "Chiến Đấu & Di Chuyển", ["English"] = "Combat & Movement" },
    ["TweenSpeed (>=500: Instant, <500: Smooth)"] = { ["Tiếng Việt"] = "Tốc Độ Bay (>=500: Ngay Lập Tức)", ["English"] = "Tween Speed (>=500: Instant, <500: Smooth)" },
    ["AutoMob"] = { ["Tiếng Việt"] = "Tự Động Đánh Quái (Auto Mob)", ["English"] = "Auto Mob" },
    ["Kill Aura"] = { ["Tiếng Việt"] = "Vùng Diệt Quái (Kill Aura)", ["English"] = "Kill Aura" },
    ["DistanceToSkill(OnlyNumber)"] = { ["Tiếng Việt"] = "Khoảng Cách Dùng Skill (Studs)", ["English"] = "Distance To Skill (Studs)" },
    ["AutoSkill"] = { ["Tiếng Việt"] = "Tự Động Dùng Chiêu (Auto Skill)", ["English"] = "Auto Skill" },
    ["AutoAssistSkill"] = { ["Tiếng Việt"] = "Tự Dùng Chiêu Phụ (Auto Assist)", ["English"] = "Auto Assist Skill" },
    ["AutoFruitSkill"] = { ["Tiếng Việt"] = "Tự Dùng Chiêu Trái (Auto Fruit)", ["English"] = "Auto Fruit Skill" },
    ["SelectAttackMethod"] = { ["Tiếng Việt"] = "Phương Thức Tấn Công (Method)", ["English"] = "Select Attack Method" },
    ["AutoMelee"] = { ["Tiếng Việt"] = "Tự Đánh Thường (Auto Melee)", ["English"] = "Auto Melee" },
    ["FarmDistance(OnlyNumber)"] = { ["Tiếng Việt"] = "Khoảng Cách Farm Quái (Studs)", ["English"] = "Farm Distance (Studs)" },
    ["FarmPosition"] = { ["Tiếng Việt"] = "Vị Trí Farm (Trên/Dưới Quái)", ["English"] = "Farm Position" },

    -- Tab 2: More (Mở Rộng)
    ["JoiningCombo"] = { ["Tiếng Việt"] = "Tự Vào Phòng (Joining Combo)", ["English"] = "Joining Combo" },
    ["RaidSelection"] = { ["Tiếng Việt"] = "Chọn Phòng Raid (Raid Selection)", ["English"] = "Raid Selection" },
    ["SelectExtremeDimensionDifficulty"] = { ["Tiếng Việt"] = "Độ Khó Thứ Nguyên Siêu Cấp", ["English"] = "Extreme Dimension Difficulty" },
    ["ExtremeDimensionMinReward(%)"] = { ["Tiếng Việt"] = "Phần Thưởng Tối Thiểu (%)", ["English"] = "Extreme Dimension Min Reward (%)" },
    ["Cooldown JoinRaid(OnlyNumber)"] = { ["Tiếng Việt"] = "Thời Gian Chờ Vào Raid (Giây)", ["English"] = "Cooldown Join Raid (Sec)" },
    ["AutoRaid"] = { ["Tiếng Việt"] = "Tự Động Đi Raid (Auto Raid)", ["English"] = "Auto Raid" },
    ["FreeBossRush"] = { ["Tiếng Việt"] = "Vé Boss Rush Miễn Phí", ["English"] = "Free Boss Rush" },
    ["BossRush"] = { ["Tiếng Việt"] = "Tự Động Đi Boss Rush", ["English"] = "Boss Rush" },
    ["AutoSpeedRaid(RandomSelect)"] = { ["Tiếng Việt"] = "Tự Đi Speed Raid (Ngẫu Nhiên)", ["English"] = "Auto Speed Raid (Random Select)" },
    ["AutoRaidChallenge(IfRewardAvailable)"] = { ["Tiếng Việt"] = "Tự Đi Raid Thử Thách (Khi Có Thưởng)", ["English"] = "Auto Raid Challenge (If Reward Available)" },
    ["ExtremeDimension(MinReward%)"] = { ["Tiếng Việt"] = "Thứ Nguyên Siêu Cấp (Theo % Thưởng)", ["English"] = "Extreme Dimension (Min Reward %)" },
    ["MoreFunction"] = { ["Tiếng Việt"] = "Tính Năng Bổ Sung", ["English"] = "More Functions" },
    ["Return To Lobby"] = { ["Tiếng Việt"] = "Quay Về Sảnh (Return To Lobby)", ["English"] = "Return To Lobby" },
    ["AutoDodgeSkill"] = { ["Tiếng Việt"] = "Tự Động Né Chiêu (Auto Dodge)", ["English"] = "Auto Dodge Skill" },
    ["AutoDeleteMap"] = { ["Tiếng Việt"] = "Xóa Bản Đồ Giảm Lag (Delete Map)", ["English"] = "Auto Delete Map" },
    ["AutoNextRoom"] = { ["Tiếng Việt"] = "Tự Chuyển Phòng Khi Hết Quái", ["English"] = "Auto Next Room" },
    ["AutoRedeemAllCode"] = { ["Tiếng Việt"] = "Tự Nhập Toàn Bộ Code Game", ["English"] = "Auto Redeem All Codes" },
    ["Custom Codes (Separated by comma)"] = { ["Tiếng Việt"] = "Mã Code Tùy Chỉnh (Cách bằng dấu phẩy)", ["English"] = "Custom Codes (Separated by comma)" },
    ["BackToLobbyIfGotExploitsDetected"] = { ["Tiếng Việt"] = "Về Sảnh Nếu Bị Phát Hiện Exploit", ["English"] = "Back To Lobby If Exploits Detected" },
    ["HideName"] = { ["Tiếng Việt"] = "Ẩn Tên Người Chơi (Hide Name)", ["English"] = "Hide Name" },
    ["DashNoCooldown"] = { ["Tiếng Việt"] = "Lướt Không Hồi Chiêu (Infinite Dash)", ["English"] = "Dash No Cooldown" },
    ["AutoWalk(Only Boss)"] = { ["Tiếng Việt"] = "Chỉ Nhắm Đánh Boss (Auto Walk Boss)", ["English"] = "Auto Walk (Only Boss)" },
    ["AutoClaimQuestAndReward"] = { ["Tiếng Việt"] = "Tự Nhận Nhiệm Vụ & Phần Thưởng", ["English"] = "Auto Claim Quest & Reward" },
    ["GoLobbyMethod"] = { ["Tiếng Việt"] = "Phương Thức Về Sảnh (Lobby Method)", ["English"] = "Go Lobby Method" },
    ["BackToLobbyIfRaidOpen"] = { ["Tiếng Việt"] = "Về Sảnh Khi Raid Mở (Raid Open)", ["English"] = "Back To Lobby If Raid Open" },
    ["StopReplayIfRaidOpen"] = { ["Tiếng Việt"] = "Dừng Chơi Lại Khi Raid Mở", ["English"] = "Stop Replay If Raid Open" },
    ["Disable Noclip"] = { ["Tiếng Việt"] = "Tắt Đi Xuyên Tường (Disable Noclip)", ["English"] = "Disable Noclip" },
    ["DoNotThingIfHavePlayer"] = { ["Tiếng Việt"] = "Dừng Hoạt Động Nếu Có Người Chơi", ["English"] = "Do Nothing If Have Player" },

    -- Tab 3: Character (Nhân Vật)
    ["Character & Equipment"] = { ["Tiếng Việt"] = "Nhân Vật & Trang Bị", ["English"] = "Character & Equipment" },
    ["AutoEquip Character"] = { ["Tiếng Việt"] = "Tự Trang Bị Nhân Vật Tốt Nhất", ["English"] = "Auto Equip Best Character" },
    ["Auto Reset To Main"] = { ["Tiếng Việt"] = "Tự Đổi Về Nhân Vật Chính (Main)", ["English"] = "Auto Reset To Main" },
    ["Auto Reset To First Assist"] = { ["Tiếng Việt"] = "Tự Đổi Sang Trợ Thủ 1 (Assist)", ["English"] = "Auto Reset To First Assist" },
    ["SaveCharacter"] = { ["Tiếng Việt"] = "Lưu Cấu Hình Nhân Vật", ["English"] = "Save Character" },
    ["SellCard"] = { ["Tiếng Việt"] = "Bán Thẻ Bài (Sell Card)", ["English"] = "Sell Card" },
    ["SelectRarity"] = { ["Tiếng Việt"] = "Chọn Độ Hiếm Thẻ Bán (Rarity)", ["English"] = "Select Card Rarity" },
    ["AutoSellCard"] = { ["Tiếng Việt"] = "Tự Động Bán Thẻ Thường", ["English"] = "Auto Sell Card" },
    ["EquipCard"] = { ["Tiếng Việt"] = "Trang Bị Thẻ Bài (Equip Card)", ["English"] = "Equip Card" },
    ["EquipBestCard"] = { ["Tiếng Việt"] = "Tự Trang Bị Thẻ Tốt Nhất", ["English"] = "Auto Equip Best Card" },
    ["EquipBestCardMode"] = { ["Tiếng Việt"] = "Chế Độ Ưu Tiên Thẻ (Damage/Def)", ["English"] = "Equip Best Card Mode" },

    -- Tab 4: Setting (Cài Đặt)
    ["LanguageSection"] = { ["Tiếng Việt"] = "Ngôn Ngữ / Language", ["English"] = "Language / Ngôn Ngữ" },
    ["SelectLanguage"] = { ["Tiếng Việt"] = "Chọn Ngôn Ngữ / Select Language", ["English"] = "Select Language / Chọn Ngôn Ngữ" },
    ["Setting DodgeSkill"] = { ["Tiếng Việt"] = "Cài Đặt Né Chiêu (Dodge Skill)", ["English"] = "Setting Dodge Skill" },
    ["SizeDodgePart (Studs Radius)"] = { ["Tiếng Việt"] = "Bán Kính Vùng Né (Studs Radius)", ["English"] = "Size Dodge Part (Studs Radius)" },
    ["SizeDodgePart Y (OnlyNumber)"] = { ["Tiếng Việt"] = "Độ Cao Vùng Né Y (Trục Đứng)", ["English"] = "Size Dodge Part Y (Only Number)" },
    ["TweenSpeedDodgePart (Sec)"] = { ["Tiếng Việt"] = "Tốc Độ Lướt Né (Giây)", ["English"] = "Tween Speed Dodge Part (Sec)" },
    ["DodgePartTransparency (OnlyNumber)"] = { ["Tiếng Việt"] = "Độ Trong Suốt Vùng Né (0 - 1)", ["English"] = "Dodge Part Transparency (0 - 1)" },
    ["MoreFunction2"] = { ["Tiếng Việt"] = "Cài Đặt Chế Độ Vô Tận & Raid", ["English"] = "Other Mode Settings" },
    ["Go AFK (If Raid Not Open)"] = { ["Tiếng Việt"] = "Treo Máy (Nếu Raid Chưa Mở)", ["English"] = "Go AFK (If Raid Not Open)" },
    ["SelectWaveToReset"] = { ["Tiếng Việt"] = "Chọn Wave Để Reset (Vô Tận)", ["English"] = "Select Wave To Reset" },
    ["Reset INF Mode (SelectWave)"] = { ["Tiếng Việt"] = "Tự Reset Chế Độ Vô Tận", ["English"] = "Reset INF Mode (Select Wave)" },
    ["Setting AutoSkill"] = { ["Tiếng Việt"] = "Thứ Tự Ra Chiêu (5 ➔ 4 ➔ 1 ➔ 2 ➔ 3)", ["English"] = "Setting Auto Skill Priority" },
    ["SkillFirst"] = { ["Tiếng Việt"] = "Chiêu Thứ 1 (Mặc định: 5)", ["English"] = "Skill First (Default: 5)" },
    ["SkillSecond"] = { ["Tiếng Việt"] = "Chiêu Thứ 2 (Mặc định: 4)", ["English"] = "Skill Second (Default: 4)" },
    ["SkillThird"] = { ["Tiếng Việt"] = "Chiêu Thứ 3 (Mặc định: 1)", ["English"] = "Skill Third (Default: 1)" },
    ["SkillFourth"] = { ["Tiếng Việt"] = "Chiêu Thứ 4 (Mặc định: 2)", ["English"] = "Skill Fourth (Default: 2)" },
    ["SkillFifth"] = { ["Tiếng Việt"] = "Chiêu Thứ 5 (Mặc định: 3)", ["English"] = "Skill Fifth (Default: 3)" },

    -- Tab 5: Buy (Cửa Hàng)
    ["AutoBuy"] = { ["Tiếng Việt"] = "Tự Động Mua (Auto Buy)", ["English"] = "Auto Buy" },
    ["Select method buy"] = { ["Tiếng Việt"] = "Loại Tiền Tệ Thanh Toán", ["English"] = "Select Method Buy" },
    ["BuyRushTicket"] = { ["Tiếng Việt"] = "Tự Mua Vé Đi Nhanh (Rush Ticket)", ["English"] = "Buy Rush Ticket" },
    ["Buy100RaidToken(BossRushToken)"] = { ["Tiếng Việt"] = "Tự Mua 100 Vé Raid Token", ["English"] = "Buy 100 Raid Token (Boss Rush)" },

    -- Tab 6: Webhook (Thông Báo Discord)
    ["Url Webhook"] = { ["Tiếng Việt"] = "Đường Dẫn Webhook (URL)", ["English"] = "Webhook URL" },
    ["Send(DimensionDropsResult)"] = { ["Tiếng Việt"] = "Gửi Kết Quả Rơi Đồ Dimension", ["English"] = "Send (Dimension Drops Result)" },
    ["Send(RaidDropsResult)"] = { ["Tiếng Việt"] = "Gửi Kết Quả Rơi Đồ Raid", ["English"] = "Send (Raid Drops Result)" },
    ["Send(RejoinAlert)"] = { ["Tiếng Việt"] = "Gửi Cảnh Báo Vào Lại Game", ["English"] = "Send (Rejoin Alert)" },
    ["🔔 Test Webhook"] = { ["Tiếng Việt"] = "🔔 Thử Nghiệm Webhook", ["English"] = "🔔 Test Webhook" },

    -- Tab 7: Misc (Tiện Ích)
    ["Section1"] = { ["Tiếng Việt"] = "Công Cụ Di Chuyển & Nhân Vật", ["English"] = "Movement & Character Tools" },
    ["Speed"] = { ["Tiếng Việt"] = "Bật Tăng Tốc Độ Chạy", ["English"] = "Speed Boost" },
    ["Jump"] = { ["Tiếng Việt"] = "Bật Tăng Sức Bật Nhảy", ["English"] = "Jump Boost" },
    ["WalkSpeed"] = { ["Tiếng Việt"] = "Tùy Chỉnh Tốc Độ (WalkSpeed)", ["English"] = "WalkSpeed" },
    ["JumpPower"] = { ["Tiếng Việt"] = "Tùy Chỉnh Sức Nhảy (JumpPower)", ["English"] = "JumpPower" },
    ["Ctrl+ClickTP"] = { ["Tiếng Việt"] = "Ctrl + Click Dịch Chuyển (TP)", ["English"] = "Ctrl+Click TP" },
    ["CloseGuiAfterExecute"] = { ["Tiếng Việt"] = "Tự Đóng Menu Sau Khi Chạy", ["English"] = "Close GUI After Execute" },
    ["Rejoin"] = { ["Tiếng Việt"] = "Vào Lại Server Hiện Tại (Rejoin)", ["English"] = "Rejoin Server" },
    ["HopServer"] = { ["Tiếng Việt"] = "Đổi Sang Server Khác (Server Hop)", ["English"] = "Hop Server" },
    ["FireProximityPrompt"] = { ["Tiếng Việt"] = "Tự Tương Tác Cổng (Proximity Prompt)", ["English"] = "Fire Proximity Prompt" },
    ["InstantProximityPrompt"] = { ["Tiếng Việt"] = "Tương Tác Cổng Tức Thì (0s)", ["English"] = "Instant Proximity Prompt" },
    ["Section2"] = { ["Tiếng Việt"] = "Giao Diện & Tối Ưu Hóa", ["English"] = "GUI & Optimization" },
    ["StatGuiPosition"] = { ["Tiếng Việt"] = "Vị Trí Bảng Thống Kê (Stat GUI)", ["English"] = "Stat GUI Position" },
    ["CreditGuiPosition"] = { ["Tiếng Việt"] = "Vị Trí Bảng Bản Quyền (Credits)", ["English"] = "Credit GUI Position" },
    ["StatGui"] = { ["Tiếng Việt"] = "Bảng Thống Kê Nổi (Stat GUI)", ["English"] = "Stat GUI" },
    ["CreditGui"] = { ["Tiếng Việt"] = "Bảng Thông Tin Bản Quyền (Credits)", ["English"] = "Credit GUI" },
    ["RejoinIfGotKick"] = { ["Tiếng Việt"] = "Tự Vào Lại Khi Bị Mất Mạng/Kick", ["English"] = "Rejoin If Disconnected/Kicked" },
    ["Whitescreen(Reduce Cpu)"] = { ["Tiếng Việt"] = "Màn Hình Trắng Giảm Lag CPU/GPU", ["English"] = "White Screen (Reduce CPU)" },
    ["infiniteyield"] = { ["Tiếng Việt"] = "Mở Infinite Yield Admin Script", ["English"] = "Launch Infinite Yield" },
    ["ResetCamera"] = { ["Tiếng Việt"] = "Đặt Lại Góc Nhìn Camera", ["English"] = "Reset Camera" },
    ["Copy VHT HUB Discord Link"] = { ["Tiếng Việt"] = "Sao Chép Link Discord VHT HUB", ["English"] = "Copy VHT HUB Discord Link" },
    ["⚡ VHT STATS"] = { ["Tiếng Việt"] = "⚡ BẢNG THỐNG KÊ VHT", ["English"] = "⚡ VHT STATS" },
    ["⚡ VHT Hub Pro"] = { ["Tiếng Việt"] = "⚡ VHT Hub Bản Quyền", ["English"] = "⚡ VHT Hub Pro" },
    ["⚡ VHT STATS (Right)"] = { ["Tiếng Việt"] = "⚡ BẢNG THỐNG KÊ VHT (Phải)", ["English"] = "⚡ VHT STATS (Right)" },
    ["⚡ VHT STATS (Left)"] = { ["Tiếng Việt"] = "⚡ BẢNG THỐNG KÊ VHT (Trái)", ["English"] = "⚡ VHT STATS (Left)" },
    ["Hop Server Error"] = { ["Tiếng Việt"] = "Lỗi kết nối khi lấy danh sách server!", ["English"] = "Connection error getting servers!" },
    ["Hop Server Rate Limit"] = { ["Tiếng Việt"] = "Bị giới hạn tần suất (Rate limit) hoặc dữ liệu không hợp lệ!", ["English"] = "Rate limited or invalid server data!" },
    ["Hop Server No Match"] = { ["Tiếng Việt"] = "Không tìm thấy server phù hợp để chuyển!", ["English"] = "No suitable server found to hop!" }
}

local function T(key)
    local lang = Settings.Language or "Tiếng Việt"
    local item = I18N[key]
    if item then
        return item[lang] or item["Tiếng Việt"] or item["English"] or key
    end
    return key
end

local function ApplyLanguage(newLang)
    Settings.Language = newLang
    pcall(function()
        local searchContainers = {}
        if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
        pcall(function() table.insert(searchContainers, CoreGui) end)
        pcall(function() table.insert(searchContainers, LocalPlayer:FindFirstChild("PlayerGui")) end)
        for _, container in ipairs(searchContainers) do
            if container then
                for _, g in ipairs(container:GetChildren()) do
                    if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                        for _, desc in ipairs(g:GetDescendants()) do
                            if desc:IsA("TextLabel") and (desc.Name == "Content" or desc.Name == "Title" or (desc.Parent and desc.Parent:IsA("Frame"))) then
                                local curText = desc.Text
                                for k, trans in pairs(I18N) do
                                    if trans["Tiếng Việt"] == curText or trans["English"] == curText or k == curText then
                                        desc.Text = trans[newLang] or trans["Tiếng Việt"] or k
                                        break
                                    end
                                end
                            end
                        end
                    elseif (g.Name == "VHT_StatGui" or g.Name == "VHT_CreditGui") and g:IsA("ScreenGui") then
                        for _, desc in ipairs(g:GetDescendants()) do
                            if desc:IsA("TextLabel") then
                                local curText = desc.Text
                                for k, trans in pairs(I18N) do
                                    if trans["Tiếng Việt"] == curText or trans["English"] == curText or k == curText then
                                        desc.Text = trans[newLang] or trans["Tiếng Việt"] or k
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    AutoSave(true)
    pcall(function()
        OrionLib:MakeNotification({
            Name = newLang == "Tiếng Việt" and "Ngôn Ngữ Đã Đổi" or "Language Changed",
            Content = newLang == "Tiếng Việt" and "Đã chuyển đổi giao diện sang Tiếng Việt thành công!" or "Successfully switched UI language to English!",
            Image = "rbxassetid://4483345998",
            Time = 3
        })
    end)
end

-- ===================================================================
local GetPlayerLevel
local GetPlayerPower
local GetBestMapName
local GetBestDifficulty

local MainTab = Window:MakeTab({ Name = T("Main"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MainTab:AddSection({ Name = T("Farming") })

local ToggleAutoJoinMap, ToggleAutoMob, ToggleAutoMelee, ToggleKillAura, ToggleAutoSkill, ToggleAutoAssistSkill, ToggleAutoFruitSkill, ToggleAutoReplay, ToggleAutoSelectMap
local DropdownMapSelection, DropdownSelectDifficulty

ToggleAutoJoinMap = MainTab:AddToggle({ Name = T("AutoJoinMap"),
    Default = Settings.AutoJoinMap,
    Callback = function(v)
        Settings.AutoJoinMap = v
        if uiBuilding then return end
        if v then
            Settings.AutoMob = true
            Settings.AutoSkill = true
            Settings.AutoAssistSkill = true
            Settings.AutoFruitSkill = true
            Settings.AutoReplay = true
            Settings.AutoNextRoom = true

            ProgrammaticSetToggle(ToggleAutoMob, true)
            ProgrammaticSetToggle(ToggleAutoSkill, true)
            ProgrammaticSetToggle(ToggleAutoAssistSkill, true)
            ProgrammaticSetToggle(ToggleAutoFruitSkill, true)
            ProgrammaticSetToggle(ToggleAutoReplay, true)

            pcall(function()
                OrionLib:MakeNotification({
                    Name = "🚀 Auto Join & Farm Map",
                    Content = "Đã BẬT Tự Động Vào Map & Farm tự động trọn gói!",
                    Image = "rbxassetid://4483345998",
                    Time = 4
                })
            end)
        end
        AutoSave()
    end
})

MainTab:AddButton({ Name = T("JoinMapNow"),
    Callback = function()
        pcall(function()
            if not IsLobby() then
                OrionLib:MakeNotification({
                    Name = "⚠️ Thông Báo",
                    Content = "Bạn đang ở trong trận đấu, không cần vào lại!",
                    Image = "rbxassetid://4483345998",
                    Time = 3
                })
                return
            end
            local targetMap = (Settings.MapSelection and Settings.MapSelection ~= "" and Settings.MapSelection ~= "Auto") and Settings.MapSelection or (GetBestMapName and GetBestMapName() or "Titan Dimension")
            local targetDiff = GetBestDifficulty and GetBestDifficulty(targetMap) or "Easy"
            OrionLib:MakeNotification({
                Name = "🎯 Đang Vào Map...",
                Content = "Map: " .. tostring(targetMap) .. " (" .. tostring(targetDiff) .. ")",
                Image = "rbxassetid://4483345998",
                Time = 3
            })
            local roomRemote = FindRemote({"CreateRoom", "JoinRoom", "StartDungeon", "EnterDimension", "Elevator", "JoinDimension", "CreateDimension", "StartMatch", "EnterDungeon", "PlayDungeon", "QueueDimension", "SelectDimension"})
            if roomRemote then
                SafeFireRemote(roomRemote, targetMap, targetDiff, Settings.FriendOnly, Settings.Hardcore)
                SafeFireRemote(roomRemote, targetMap, targetDiff)
            end
            local portal = FindPortalPart and FindPortalPart(targetMap)
            local myRoot = GetMyRoot and GetMyRoot()
            if portal and myRoot then
                local portalPart = portal:IsA("BasePart") and portal or (portal:IsA("Model") and (portal.PrimaryPart or portal:FindFirstChildWhichIsA("BasePart", true)))
                local portalCF = portalPart and portalPart.CFrame or (portal:IsA("Model") and portal:GetPivot())
                if portalCF then
                    myRoot.CFrame = portalCF * CFrame.new(0, 3, 0)
                    if firetouchinterest and portalPart then
                        firetouchinterest(myRoot, portalPart, 0)
                        task.wait(0.05)
                        firetouchinterest(myRoot, portalPart, 1)
                    end
                end
            end
        end)
    end
})

ToggleAutoSelectMap = MainTab:AddToggle({ Name = T("AutoSelectMap(DetectedLevel)"),
    Default = Settings.AutoSelectMap,
    Callback = function(v)
        Settings.AutoSelectMap = v
        if uiBuilding then return end
        if v then
            local bestMap = GetBestMapName and GetBestMapName() or "Titan Dimension"
            local bestDiff = GetBestDifficulty and GetBestDifficulty(bestMap) or "Easy"
            local curLvl = GetPlayerLevel and GetPlayerLevel() or 1
            local curPwr = GetPlayerPower and GetPlayerPower() or 0
            if DropdownMapSelection and DropdownMapSelection.Set then
                pcall(function() DropdownMapSelection:Set(bestMap) end)
            end
            if DropdownSelectDifficulty and DropdownSelectDifficulty.Set then
                pcall(function() DropdownSelectDifficulty:Set(bestDiff) end)
            end
            pcall(function()
                OrionLib:MakeNotification({
                    Name = "🎯 Auto Farm Theo Level",
                    Content = "Level: " .. tostring(curLvl) .. " | Sức Mạnh: " .. tostring(curPwr) .. "\n-> Map: " .. tostring(bestMap) .. " (" .. tostring(bestDiff) .. ")",
                    Image = "rbxassetid://4483345998",
                    Time = 4
                })
            end)
        end
        AutoSave()
    end
})

DropdownMapSelection = MainTab:AddDropdown({ Name = T("MapSelection(AutoUpdate!)"),
    Default = Settings.MapSelection,
    Options = { "Auto", "Titan Dimension", "Demon Dimension", "Curse Dimension", "Villain Dimension", "Sword Dimension", "Ghoul Dimension", "Fate Dimension", "Slime Dimension", "Devil Dimension", "Pirate Dimension", "Alien Dimension", "Giant Dimension", "Shadow Dimension", "Esper Dimension", "Soul Dimension" },
    Callback = function(v)
        Settings.MapSelection = v
        AutoSave()
    end
})

DropdownSelectDifficulty = MainTab:AddDropdown({ Name = T("SelectDifficulty"),
    Default = Settings.SelectDifficulty or "Auto",
    Options = { "Auto", "Nightmare", "Hard", "Easy" },
    Callback = function(v)
        Settings.SelectDifficulty = v
        AutoSave()
    end
})

MainTab:AddTextbox({ Name = T("WaitOnLobbyAfterJoin(OnlyNumber)"),
    Default = tostring(Settings.WaitOnLobbyAfterJoin),
    TextDisappear = false,
    Callback = function(v)
        Settings.WaitOnLobbyAfterJoin = tonumber(v) or 10
        AutoSave()
    end
})

MainTab:AddToggle({ Name = T("WaitLobbyOnlyFirstTime"),
    Default = Settings.WaitLobbyOnlyFirstTime,
    Callback = function(v)
        Settings.WaitLobbyOnlyFirstTime = v
        AutoSave()
    end
})

local previousSettingsBeforeAutoPlay = nil
local userManuallyOverrodeReplay = false
local programmaticCounter = 0

local function ProgrammaticSetToggle(toggle, value)
    programmaticCounter = programmaticCounter + 1
    pcall(function()
        if toggle and toggle.Set then
            toggle:Set(value)
        end
    end)
    task.delay(0.15, function()
        programmaticCounter = math.max(0, programmaticCounter - 1)
    end)
end

MainTab:AddToggle({ Name = T("AutoPlay"),
    Default = Settings.AutoPlay,
    Callback = function(v)
        Settings.AutoPlay = v
        if uiBuilding then return end
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
            if Settings.SelectAttackMethod == "Skill" then
                Settings.AutoMelee = false
            else
                Settings.AutoMelee = true
            end
            Settings.KillAura = false
            Settings.AutoSkill = true
            Settings.AutoAssistSkill = true
            Settings.AutoFruitSkill = true
            Settings.AutoReplay = true

            ProgrammaticSetToggle(ToggleAutoMob, true)
            ProgrammaticSetToggle(ToggleAutoMelee, Settings.AutoMelee)
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

MainTab:AddToggle({ Name = T("Hardcore"),
    Default = Settings.Hardcore,
    Callback = function(v)
        Settings.Hardcore = v
        AutoSave()
    end
})

ToggleAutoReplay = MainTab:AddToggle({ Name = T("AutoReplay"),
    Default = Settings.AutoReplay,
    Callback = function(v)
        Settings.AutoReplay = v
        if programmaticCounter == 0 then
            userManuallyOverrodeReplay = not v -- CRIT-1: Chỉ đánh dấu khi user tự tay bấm
        end
        AutoSave()
    end
})

MainTab:AddToggle({ Name = T("FriendOnly"),
    Default = Settings.FriendOnly,
    Callback = function(v)
        Settings.FriendOnly = v
        AutoSave()
    end
})

MainTab:AddSection({ Name = T("Combat & Movement") })

MainTab:AddTextbox({ Name = T("TweenSpeed (>=500: Instant, <500: Smooth)"),
    Default = tostring(Settings.TweenSpeed),
    TextDisappear = false,
    Callback = function(v)
        Settings.TweenSpeed = tonumber(v) or 500
        AutoSave()
    end
})

ToggleAutoMob = MainTab:AddToggle({ Name = T("AutoMob"),
    Default = Settings.AutoMob,
    Callback = function(v)
        Settings.AutoMob = v
        AutoSave()
    end
})

ToggleKillAura = MainTab:AddToggle({ Name = T("Kill Aura"),
    Default = Settings.KillAura,
    Callback = function(v)
        Settings.KillAura = v
        AutoSave()
    end
})

MainTab:AddTextbox({ Name = T("DistanceToSkill(OnlyNumber)"),
    Default = tostring(Settings.DistanceToSkill),
    TextDisappear = false,
    Callback = function(v)
        Settings.DistanceToSkill = tonumber(v) or 30
        AutoSave()
    end
})

ToggleAutoSkill = MainTab:AddToggle({ Name = T("AutoSkill"),
    Default = Settings.AutoSkill,
    Callback = function(v)
        Settings.AutoSkill = v
        AutoSave()
    end
})

ToggleAutoAssistSkill = MainTab:AddToggle({ Name = T("AutoAssistSkill"),
    Default = Settings.AutoAssistSkill,
    Callback = function(v)
        Settings.AutoAssistSkill = v
        AutoSave()
    end
})

ToggleAutoFruitSkill = MainTab:AddToggle({ Name = T("AutoFruitSkill"),
    Default = Settings.AutoFruitSkill,
    Callback = function(v)
        Settings.AutoFruitSkill = v
        AutoSave()
    end
})

MainTab:AddDropdown({ Name = T("SelectAttackMethod"),
    Default = Settings.SelectAttackMethod,
    Options = { "Skill", "Melee", "Click" },
    Callback = function(v)
        Settings.SelectAttackMethod = v
        if uiBuilding then return end
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

ToggleAutoMelee = MainTab:AddToggle({ Name = T("AutoMelee"),
    Default = Settings.AutoMelee,
    Callback = function(v)
        Settings.AutoMelee = v
        AutoSave()
    end
})

-- Khởi tạo đồng bộ khi AutoPlay được bật từ file lưu trước đó (HIGH-5, CRIT-2: lưu cấu hình trước khi ép bật)
if Settings.AutoPlay and not previousSettingsBeforeAutoPlay then
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
    if Settings.SelectAttackMethod == "Skill" then
        Settings.AutoMelee = false
    else
        Settings.AutoMelee = true
    end
    Settings.KillAura = false
    Settings.AutoSkill = true
    Settings.AutoAssistSkill = true
    Settings.AutoFruitSkill = true
    Settings.AutoReplay = true
    if Settings.MapSelection == "Auto" then Settings.AutoSelectMap = true end
    task.spawn(function()
        task.wait(0.5)
        ProgrammaticSetToggle(ToggleAutoMob, true)
        ProgrammaticSetToggle(ToggleAutoMelee, Settings.AutoMelee)
        ProgrammaticSetToggle(ToggleKillAura, false)
        ProgrammaticSetToggle(ToggleAutoSkill, true)
        ProgrammaticSetToggle(ToggleAutoAssistSkill, true)
        ProgrammaticSetToggle(ToggleAutoFruitSkill, true)
        ProgrammaticSetToggle(ToggleAutoReplay, true)
        if Settings.MapSelection == "Auto" then ProgrammaticSetToggle(ToggleAutoSelectMap, true) end
    end)
end

MainTab:AddTextbox({ Name = T("FarmDistance(OnlyNumber)"),
    Default = tostring(Settings.FarmDistance or 7),
    TextDisappear = false,
    Callback = function(v)
        Settings.FarmDistance = tonumber(v) or 7
        AutoSave()
    end
})

MainTab:AddDropdown({ Name = T("FarmPosition"),
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
local MoreTab = Window:MakeTab({ Name = T("More"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MoreTab:AddSection({ Name = T("JoiningCombo") })

MoreTab:AddDropdown({ Name = T("RaidSelection"),
    Default = Settings.RaidSelection,
    Options = { "Auto", "Fluffy Raid", "Beast Raid", "Chainsaw Raid", "King of Curses Raid", "Infinite Shiro Raid", "Combat Giant Raid", "Red Emperor Raid", "Sun God Sora Raid", "Warlord Raid", "Tengu Raid", "Hime Raid", "Dark One Hero Raid" },
    Callback = function(v)
        Settings.RaidSelection = v
        AutoSave()
    end
})

MoreTab:AddDropdown({ Name = T("SelectExtremeDimensionDifficulty"),
    Default = Settings.SelectExtremeDimensionDifficulty,
    Options = { "Extreme", "Nightmare", "Hard" },
    Callback = function(v)
        Settings.SelectExtremeDimensionDifficulty = v
        AutoSave()
    end
})

MoreTab:AddDropdown({ Name = T("ExtremeDimensionMinReward(%)"),
    Default = tostring(Settings.ExtremeDimensionMinReward),
    Options = { "100", "75", "50", "25" },
    Callback = function(v)
        Settings.ExtremeDimensionMinReward = tonumber(v) or 100
        AutoSave()
    end
})

MoreTab:AddTextbox({ Name = T("Cooldown JoinRaid(OnlyNumber)"),
    Default = tostring(Settings.CooldownJoinRaid),
    TextDisappear = false,
    Callback = function(v)
        Settings.CooldownJoinRaid = tonumber(v) or 10
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("AutoRaid"),
    Default = Settings.AutoRaid,
    Callback = function(v)
        Settings.AutoRaid = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("FreeBossRush"),
    Default = Settings.FreeBossRush,
    Callback = function(v)
        Settings.FreeBossRush = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("BossRush"),
    Default = Settings.BossRush,
    Callback = function(v)
        Settings.BossRush = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("AutoSpeedRaid(RandomSelect)"),
    Default = Settings.AutoSpeedRaid,
    Callback = function(v)
        Settings.AutoSpeedRaid = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("AutoRaidChallenge(IfRewardAvailable)"),
    Default = Settings.AutoRaidChallenge,
    Callback = function(v)
        Settings.AutoRaidChallenge = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("ExtremeDimension(MinReward%)"),
    Default = Settings.ExtremeDimension,
    Callback = function(v)
        Settings.ExtremeDimension = v
        AutoSave()
    end
})

MoreTab:AddSection({ Name = T("MoreFunction") })

local function ReturnToLobby()
    AutoSave(true)
    local method = Settings.GoLobbyMethod or "TeleportToLobby"
    if method == "Leave" then
        userIntentionalLeave = true
        pcall(function() game:Shutdown() end)
        task.delay(0.2, function()
            local ok, err = pcall(function() LocalPlayer:Kick("Leaving game via VHT HUB...") end)
            if not ok then
                warn("⚠️ [Leave]: LocalPlayer:Kick bị giới hạn (" .. tostring(err) .. "), chuyển hướng Teleport về sảnh...")
                pcall(function()
                    QueueScriptReload()
                    TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
                end)
            end
        end)
    elseif method == "Reconnect" then
        pcall(function()
            QueueScriptReload()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    else
        pcall(function()
            local remote = FindRemote({"TeleportToLobby", "ReturnLobby"})
            if remote then
                SafeFireRemote(remote)
                task.delay(3, function()
                    if game.PlaceId ~= LOBBY_PLACE_ID then
                        QueueScriptReload()
                        TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
                    end
                end)
            else
                QueueScriptReload()
                TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
            end
        end)
    end
end

MoreTab:AddButton({ Name = T("Return To Lobby"),
    Callback = function()
        ReturnToLobby()
    end
})

MoreTab:AddToggle({ Name = T("AutoDodgeSkill"),
    Default = Settings.AutoDodgeSkill,
    Callback = function(v)
        Settings.AutoDodgeSkill = v
        AutoSave()
    end
})

local originalTransparencies = setmetatable({}, { __mode = "k" })
local originalParticleStates = setmetatable({}, { __mode = "k" })
local autoDeleteMapToken = 0
local autoDeleteMapConnection = nil
local hasAutoDeleteMapRun = false

local function ApplyAutoDeleteMap(v)
    if not v and not hasAutoDeleteMapRun and next(originalTransparencies) == nil and not autoDeleteMapConnection then
        return
    end
    hasAutoDeleteMapRun = true

    autoDeleteMapToken = autoDeleteMapToken + 1
    local currentToken = autoDeleteMapToken

    if autoDeleteMapConnection then
        autoDeleteMapConnection = UntrackConnection(autoDeleteMapConnection)
    end

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
                    if originalParticleStates[obj] == nil then
                        originalParticleStates[obj] = obj.Enabled
                    end
                    obj.Enabled = false
                end
            end)
        end))
    end

    task.spawn(function()
        pcall(function()
            for k in pairs(originalTransparencies) do
                local ok, parent = pcall(function() return k.Parent end)
                if not ok or not parent then
                    originalTransparencies[k] = nil
                end
            end
            for k in pairs(originalParticleStates) do
                local ok, parent = pcall(function() return k.Parent end)
                if not ok or not parent then
                    originalParticleStates[k] = nil
                end
            end

            local descendants = workspace:GetDescendants()
            local count = 0
            for _, obj in ipairs(descendants) do
                if autoDeleteMapToken ~= currentToken then return end
                count = count + 1
                if count % 500 == 0 then task.wait() end
                if obj:IsA("Decal") or obj:IsA("Texture") then
                    if v then
                        if originalTransparencies[obj] == nil then
                            originalTransparencies[obj] = obj.Transparency
                        end
                        obj.Transparency = 1
                    else
                        if originalTransparencies[obj] ~= nil then
                            obj.Transparency = originalTransparencies[obj]
                        end
                    end
                elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                    if v then
                        if originalParticleStates[obj] == nil then
                            originalParticleStates[obj] = obj.Enabled
                        end
                        obj.Enabled = false
                    else
                        if originalParticleStates[obj] ~= nil then
                            obj.Enabled = originalParticleStates[obj]
                        end
                    end
                end
            end
        end)
    end)
end

MoreTab:AddToggle({ Name = T("AutoDeleteMap"),
    Default = Settings.AutoDeleteMap,
    Callback = function(v)
        Settings.AutoDeleteMap = v
        if uiBuilding then return end
        ApplyAutoDeleteMap(v)
        AutoSave()
    end
})

MoreTab:AddToggle({
    Name = T("AutoNextRoom"),
    Default = Settings.AutoNextRoom,
    Callback = function(v)
        Settings.AutoNextRoom = v
        AutoSave()
    end
})

local ToggleAutoRedeem; ToggleAutoRedeem = MoreTab:AddToggle({ Name = T("AutoRedeemAllCode"),
    Default = Settings.AutoRedeemAllCode,
    Callback = function(v)
        Settings.AutoRedeemAllCode = v
        AutoSave()
    end
})

MoreTab:AddTextbox({ Name = T("Custom Codes (Separated by comma)"),
    Default = Settings.CustomRedeemCodes or "UPDATE, DIMENSIONS, SEASON, FREEGEMS, BOOST",
    TextDisappear = false,
    Callback = function(v)
        Settings.CustomRedeemCodes = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("BackToLobbyIfGotExploitsDetected"),
    Default = Settings.BackToLobbyIfGotExploitsDetected,
    Callback = function(v)
        Settings.BackToLobbyIfGotExploitsDetected = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("HideName"),
    Default = Settings.HideName,
    Callback = function(v)
        Settings.HideName = v
        if uiBuilding then return end
        ApplyHideName(v)
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("DashNoCooldown"),
    Default = Settings.DashNoCooldown,
    Callback = function(v)
        Settings.DashNoCooldown = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("AutoWalk(Only Boss)"),
    Default = Settings.AutoWalkOnlyBoss,
    Callback = function(v)
        Settings.AutoWalkOnlyBoss = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("AutoClaimQuestAndReward"),
    Default = Settings.AutoClaimQuestAndReward,
    Callback = function(v)
        Settings.AutoClaimQuestAndReward = v
        AutoSave()
    end
})

MoreTab:AddDropdown({ Name = T("GoLobbyMethod"),
    Default = Settings.GoLobbyMethod,
    Options = { "TeleportToLobby", "Reconnect", "Leave" },
    Callback = function(v)
        Settings.GoLobbyMethod = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("BackToLobbyIfRaidOpen"),
    Default = Settings.BackToLobbyIfRaidOpen,
    Callback = function(v)
        Settings.BackToLobbyIfRaidOpen = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("StopReplayIfRaidOpen"),
    Default = Settings.StopReplayIfRaidOpen,
    Callback = function(v)
        Settings.StopReplayIfRaidOpen = v
        AutoSave()
    end
})

MoreTab:AddToggle({ Name = T("Disable Noclip"),
    Default = Settings.DisableNoclip,
    Callback = function(v)
        Settings.DisableNoclip = v
        if uiBuilding then return end
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

MoreTab:AddToggle({ Name = T("DoNotThingIfHavePlayer"),
    Default = Settings.DoNotThingIfHavePlayer,
    Callback = function(v)
        Settings.DoNotThingIfHavePlayer = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 3: CHARACTER (CHARACTERS & CARDS)
-- ===================================================================
local CharTab = Window:MakeTab({ Name = T("Character"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

CharTab:AddSection({ Name = T("Character & Equipment") })

local hasEquippedCharacter = false
local lastEquippedCardMode = ""

CharTab:AddToggle({ Name = T("AutoEquip Character"),
    Default = Settings.AutoEquipCharacter,
    Callback = function(v)
        Settings.AutoEquipCharacter = v
        if v then hasEquippedCharacter = false end
        AutoSave()
    end
})

local ToggleAutoResetToMain, ToggleAutoResetToFirstAssist

ToggleAutoResetToMain = CharTab:AddToggle({ Name = T("Auto Reset To Main"),
    Default = Settings.AutoResetToMain,
    Callback = function(v)
        Settings.AutoResetToMain = v
        if uiBuilding then return end
        if v then
            Settings.AutoResetToFirstAssist = false
            ProgrammaticSetToggle(ToggleAutoResetToFirstAssist, false)
            if currentActiveSlot ~= 1 then
                pcall(function()
                    local switchRemote = FindRemote({"SwitchCharacter", "ChangeCharacter"})
                    if switchRemote then
                        SafeFireRemote(switchRemote, 1)
                        currentActiveSlot = 1
                    end
                end)
            end
        end
        AutoSave()
    end
})

ToggleAutoResetToFirstAssist = CharTab:AddToggle({ Name = T("Auto Reset To First Assist"),
    Default = Settings.AutoResetToFirstAssist,
    Callback = function(v)
        Settings.AutoResetToFirstAssist = v
        if uiBuilding then return end
        if v then
            Settings.AutoResetToMain = false
            ProgrammaticSetToggle(ToggleAutoResetToMain, false)
            if currentActiveSlot ~= 2 then
                pcall(function()
                    local switchRemote = FindRemote({"SwitchCharacter", "ChangeCharacter"})
                    if switchRemote then
                        SafeFireRemote(switchRemote, 2)
                        currentActiveSlot = 2
                    end
                end)
            end
        end
        AutoSave()
    end
})

CharTab:AddButton({ Name = T("SaveCharacter"),
    Callback = function()
        pcall(function()
            local remote = FindRemote({"SaveCharacter", "SaveEquipment"})
            if remote then SafeFireRemote(remote) end
        end)
    end
})

CharTab:AddSection({ Name = T("SellCard") })

CharTab:AddDropdown({ Name = T("SelectRarity"),
    Default = Settings.SelectRarity,
    Options = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
    Callback = function(v)
        Settings.SelectRarity = v
        AutoSave()
    end
})

CharTab:AddToggle({ Name = T("AutoSellCard"),
    Default = Settings.AutoSellCard,
    Callback = function(v)
        Settings.AutoSellCard = v
        AutoSave()
    end
})

CharTab:AddSection({ Name = T("EquipCard") })

CharTab:AddToggle({ Name = T("EquipBestCard"),
    Default = Settings.EquipBestCard,
    Callback = function(v)
        Settings.EquipBestCard = v
        if v then lastEquippedCardMode = "" end
        AutoSave()
    end
})

CharTab:AddDropdown({ Name = T("EquipBestCardMode"),
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
local SettingTab = Window:MakeTab({ Name = T("Setting"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})


SettingTab:AddSection({ Name = T("LanguageSection") })

SettingTab:AddDropdown({
    Name = T("SelectLanguage"),
    Default = Settings.Language or "Tiếng Việt",
    Options = { "Tiếng Việt", "English" },
    Callback = function(v)
        if v ~= Settings.Language then
            ApplyLanguage(v)
        end
    end
})

SettingTab:AddSection({ Name = T("Setting DodgeSkill") })

SettingTab:AddTextbox({ Name = T("SizeDodgePart (Studs Radius)"),
    Default = tostring(Settings.SizeDodgePart),
    TextDisappear = false,
    Callback = function(v)
        Settings.SizeDodgePart = tonumber(v) or 25
        AutoSave()
    end
})

SettingTab:AddTextbox({ Name = T("SizeDodgePart Y (OnlyNumber)"),
    Default = tostring(Settings.SizeDodgePartY),
    TextDisappear = false,
    Callback = function(v)
        Settings.SizeDodgePartY = tonumber(v) or 100
        AutoSave()
    end
})

SettingTab:AddTextbox({ Name = T("TweenSpeedDodgePart (Sec)"),
    Default = tostring(Settings.TweenSpeedDodgePart),
    TextDisappear = false,
    Callback = function(v)
        Settings.TweenSpeedDodgePart = tonumber(v) or 0.15
        AutoSave()
    end
})

SettingTab:AddTextbox({ Name = T("DodgePartTransparency (OnlyNumber)"),
    Default = tostring(Settings.DodgePartTransparency),
    TextDisappear = false,
    Callback = function(v)
        Settings.DodgePartTransparency = tonumber(v) or 0.9
        AutoSave()
    end
})

SettingTab:AddSection({ Name = T("MoreFunction2") })

SettingTab:AddToggle({ Name = T("Go AFK (If Raid Not Open)"),
    Default = Settings.GoAFKIfRaidNotOpen,
    Callback = function(v)
        Settings.GoAFKIfRaidNotOpen = v
        AutoSave()
    end
})

SettingTab:AddTextbox({ Name = T("SelectWaveToReset"),
    Default = tostring(Settings.SelectWaveToReset),
    TextDisappear = false,
    Callback = function(v)
        Settings.SelectWaveToReset = tonumber(v) or 100
        AutoSave()
    end
})

SettingTab:AddToggle({ Name = T("Reset INF Mode (SelectWave)"),
    Default = Settings.ResetINFMode,
    Callback = function(v)
        Settings.ResetINFMode = v
        AutoSave()
    end
})

SettingTab:AddSection({ Name = T("Setting AutoSkill") })

local dropSkillFirst, dropSkillSecond, dropSkillThird, dropSkillFourth, dropSkillFifth
local function HandleSkillKeyChange(keyName, newVal)
    local skillKeys = { "SkillFirst", "SkillSecond", "SkillThird", "SkillFourth", "SkillFifth" }
    local drops = {
        SkillFirst = dropSkillFirst,
        SkillSecond = dropSkillSecond,
        SkillThird = dropSkillThird,
        SkillFourth = dropSkillFourth,
        SkillFifth = dropSkillFifth
    }
    local oldVal = Settings[keyName]
    Settings[keyName] = newVal

    for _, otherKey in ipairs(skillKeys) do
        if otherKey ~= keyName and Settings[otherKey] == newVal then
            Settings[otherKey] = oldVal
            if drops[otherKey] and drops[otherKey].Set then
                pcall(function() drops[otherKey]:Set(oldVal) end)
            end
            pcall(function()
                OrionLib:MakeNotification({
                    Name = "AutoSkill Setup",
                    Content = "Phím " .. newVal .. " đã bị trùng! Tự động đổi với ô còn lại.",
                    Image = "rbxassetid://4483345998",
                    Time = 3
                })
            end)
            break
        end
    end
    AutoSave()
end

dropSkillFirst = SettingTab:AddDropdown({ Name = T("SkillFirst"),
    Default = tostring(Settings.SkillFirst),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        if uiBuilding then Settings.SkillFirst = v return end
        HandleSkillKeyChange("SkillFirst", v)
    end
})

dropSkillSecond = SettingTab:AddDropdown({ Name = T("SkillSecond"),
    Default = tostring(Settings.SkillSecond),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        if uiBuilding then Settings.SkillSecond = v return end
        HandleSkillKeyChange("SkillSecond", v)
    end
})

dropSkillThird = SettingTab:AddDropdown({ Name = T("SkillThird"),
    Default = tostring(Settings.SkillThird),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        if uiBuilding then Settings.SkillThird = v return end
        HandleSkillKeyChange("SkillThird", v)
    end
})

dropSkillFourth = SettingTab:AddDropdown({ Name = T("SkillFourth"),
    Default = tostring(Settings.SkillFourth),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        if uiBuilding then Settings.SkillFourth = v return end
        HandleSkillKeyChange("SkillFourth", v)
    end
})

dropSkillFifth = SettingTab:AddDropdown({ Name = T("SkillFifth"),
    Default = tostring(Settings.SkillFifth),
    Options = { "1", "2", "3", "4", "5" },
    Callback = function(v)
        if uiBuilding then Settings.SkillFifth = v return end
        HandleSkillKeyChange("SkillFifth", v)
    end
})

-- ===================================================================
-- TAB 5: BUY (AUTO BUY SHOP)
-- ===================================================================
local BuyTab = Window:MakeTab({ Name = T("Buy"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

BuyTab:AddSection({ Name = T("AutoBuy") })

BuyTab:AddDropdown({ Name = T("Select method buy"),
    Default = Settings.SelectMethodBuy,
    Options = { "Raid Token", "Gems", "Gold" },
    Callback = function(v)
        Settings.SelectMethodBuy = v
        AutoSave()
    end
})

BuyTab:AddToggle({ Name = T("BuyRushTicket"),
    Default = Settings.BuyRushTicket,
    Callback = function(v)
        Settings.BuyRushTicket = v
        AutoSave()
    end
})

BuyTab:AddToggle({ Name = T("Buy100RaidToken(BossRushToken)"),
    Default = Settings.Buy100RaidToken,
    Callback = function(v)
        Settings.Buy100RaidToken = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 6: WEBHOOK
-- ===================================================================
local WebhookTab = Window:MakeTab({ Name = T("Webhook"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

WebhookTab:AddSection({ Name = T("Webhook") })

WebhookTab:AddTextbox({ Name = T("Url Webhook"),
    Default = Settings.WebhookURL,
    TextDisappear = false,
    Callback = function(v)
        Settings.WebhookURL = v
        AutoSave()
    end
})

WebhookTab:AddToggle({ Name = T("Send(DimensionDropsResult)"),
    Default = Settings.SendDimensionDrops,
    Callback = function(v)
        Settings.SendDimensionDrops = v
        AutoSave()
    end
})

WebhookTab:AddToggle({ Name = T("Send(RaidDropsResult)"),
    Default = Settings.SendRaidDrops,
    Callback = function(v)
        Settings.SendRaidDrops = v
        AutoSave()
    end
})

WebhookTab:AddToggle({ Name = T("Send(RejoinAlert)"),
    Default = Settings.WebhookOnRejoin,
    Callback = function(v)
        Settings.WebhookOnRejoin = v
        AutoSave()
    end
})

WebhookTab:AddButton({ Name = T("🔔 Test Webhook"),
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

        SendDiscordWebhook("🔔 [TEST] VHT Hub Webhook Connected", "Your Discord Webhook is working correctly!", testFields, 65280)

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
local MiscTab = Window:MakeTab({ Name = T("Misc"),
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MiscTab:AddSection({ Name = T("Section1") })

MiscTab:AddTextbox({ Name = T("Speed"),
    Default = tostring(Settings.Speed),
    TextDisappear = false,
    Callback = function(v)
        Settings.Speed = tonumber(v) or 16
        local hum = GetMyHumanoid()
        if Settings.WalkSpeed and hum then hum.WalkSpeed = Settings.Speed end
        AutoSave()
    end
})

MiscTab:AddTextbox({ Name = T("Jump"),
    Default = tostring(Settings.Jump),
    TextDisappear = false,
    Callback = function(v)
        Settings.Jump = tonumber(v) or 50
        local hum = GetMyHumanoid()
        if Settings.JumpPower and hum then hum.JumpPower = Settings.Jump end
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("WalkSpeed"),
    Default = Settings.WalkSpeed,
    Callback = function(v)
        Settings.WalkSpeed = v
        if uiBuilding then return end
        local hum = GetMyHumanoid()
        if hum then hum.WalkSpeed = v and Settings.Speed or 16 end
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("JumpPower"),
    Default = Settings.JumpPower,
    Callback = function(v)
        Settings.JumpPower = v
        if uiBuilding then return end
        local hum = GetMyHumanoid()
        if hum then hum.JumpPower = v and Settings.Jump or 50 end
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("Ctrl+ClickTP"),
    Default = Settings.CtrlClickTP,
    Callback = function(v)
        Settings.CtrlClickTP = v
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("CloseGuiAfterExecute"),
    Default = Settings.CloseGuiAfterExecute,
    Callback = function(v)
        Settings.CloseGuiAfterExecute = v
        pcall(function()
            local searchContainers = {}
            if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
            pcall(function() table.insert(searchContainers, CoreGui) end)
            pcall(function() table.insert(searchContainers, LocalPlayer:FindFirstChild("PlayerGui")) end)
            for _, cont in ipairs(searchContainers) do
                if cont then
                    for _, g in ipairs(cont:GetChildren()) do
                        if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                            g.Enabled = not v
                        end
                    end
                end
            end
        end)
        AutoSave(true)
    end
})

MiscTab:AddButton({ Name = T("Rejoin"),
    Callback = function()
        pcall(function()
            QueueScriptReload()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    end
})

MiscTab:AddButton({ Name = T("HopServer"),
    Callback = function()
        task.spawn(function()
            local req = httpRequest or (syn and syn.request) or (http and http.request) or request or http_request or (fluxus and fluxus.request)
            if not req then
                pcall(function()
                    OrionLib:MakeNotification({
                        Name = "Hop Server",
                        Content = "Executor không hỗ trợ HTTP Request!",
                        Image = "rbxassetid://4483345998",
                        Time = 4
                    })
                end)
                return
            end
            local ok, res = pcall(function()
                local serversApi = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
                return req({ Url = serversApi, Method = "GET" })
            end)
            if not ok or not res or not res.Body then
                pcall(function()
                    OrionLib:MakeNotification({
                        Name = "Hop Server",
                        Content = T("Hop Server Error"),
                        Image = "rbxassetid://4483345998",
                        Time = 4
                    })
                end)
                return
            end

            local decodeOk, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
            if not decodeOk or not data or type(data.data) ~= "table" then
                pcall(function()
                    OrionLib:MakeNotification({
                        Name = "Hop Server",
                        Content = T("Hop Server Rate Limit"),
                        Image = "rbxassetid://4483345998",
                        Time = 4
                    })
                end)
                return
            end

            local candidates = {}
            for _, s in ipairs(data.data) do
                if type(s) == "table" and s.id and s.id ~= game.JobId then
                    local playing = tonumber(s.playing) or 0
                    local maxPlayers = tonumber(s.maxPlayers) or 0
                    if playing >= 2 and playing < maxPlayers then
                        table.insert(candidates, s.id)
                    end
                end
            end

            if #candidates == 0 then
                for _, s in ipairs(data.data) do
                    if type(s) == "table" and s.id and s.id ~= game.JobId then
                        local playing = tonumber(s.playing) or 0
                        local maxPlayers = tonumber(s.maxPlayers) or 0
                        if playing < maxPlayers then
                            table.insert(candidates, s.id)
                        end
                    end
                end
            end

            if #candidates > 0 then
                local selectedId = candidates[math.random(1, #candidates)]
                QueueScriptReload()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, selectedId, LocalPlayer)
            else
                pcall(function()
                    OrionLib:MakeNotification({
                        Name = "Hop Server",
                        Content = T("Hop Server No Match"),
                        Image = "rbxassetid://4483345998",
                        Time = 4
                    })
                end)
            end
        end)
    end
})

MiscTab:AddButton({ Name = T("FireProximityPrompt"),
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

MiscTab:AddButton({ Name = T("InstantProximityPrompt"),
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

MiscTab:AddSection({ Name = T("Section2") })

-- HỆ THỐNG STAT GUI & CREDIT GUI ĐỒ HỌA TRỰC QUAN (GIỮ NGUYÊN VỊ TRÍ KHI KÉO VÀ TÍNH GIỜ CHUẨN XÁC)
local statGuiInstance = nil
local creditGuiInstance = nil
local statGuiStartTime = nil
local lastStatGuiPos = nil
local lastCreditGuiPos = nil

local function MakeDraggable(guiObject, moveTarget, onPosChanged)
    local dragging = false
    local dragStart = nil
    local startPos = nil

    TrackConnection(guiObject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = moveTarget.Position
        end
    end))

    TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            moveTarget.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            if onPosChanged then
                onPosChanged(moveTarget.Position)
            end
        end
    end))

    TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local function UpdateStatGui(forcePosition)
    if not Settings.StatGui then
        if statGuiInstance then
            statGuiInstance:Destroy()
            statGuiInstance = nil
        end
        statGuiStartTime = nil
        return
    end

    if not statGuiStartTime then
        statGuiStartTime = os.clock()
    end

    if not statGuiInstance then
        pcall(function()
            local old = CoreGui:FindFirstChild("VHT_StatGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("VHT_StatGui"))
            if old then old:Destroy() end
        end)
        local sg = Instance.new("ScreenGui")
        sg.Name = "VHT_StatGui"
        sg.ResetOnSpawn = false
        pcall(function()
            if syn and syn.protect_gui then syn.protect_gui(sg) end
            sg.Parent = CoreGui
        end)
        if not sg.Parent then sg.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, 220, 0, 132)
        frame.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
        frame.BorderColor3 = Color3.fromRGB(0, 170, 255)
        frame.BorderSizePixel = 1
        frame.Active = true

        if lastStatGuiPos then
            frame.Position = lastStatGuiPos
        elseif Settings.StatGuiPosition == "Left" then
            frame.Position = UDim2.new(0, 20, 0, 150)
        else
            frame.Position = UDim2.new(1, -240, 0, 150)
        end
        frame.Parent = sg

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 24)
        title.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
        title.BorderSizePixel = 0
        title.Text = T("⚡ VHT STATS")
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

        MakeDraggable(title, frame, function(pos) lastStatGuiPos = pos end)
        MakeDraggable(frame, frame, function(pos) lastStatGuiPos = pos end)

        statGuiInstance = sg
    elseif forcePosition and statGuiInstance:FindFirstChild("MainFrame") then
        local frame = statGuiInstance.MainFrame
        lastStatGuiPos = nil
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
            local old = CoreGui:FindFirstChild("VHT_CreditGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("VHT_CreditGui"))
            if old then old:Destroy() end
        end)
        local sg = Instance.new("ScreenGui")
        sg.Name = "VHT_CreditGui"
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

        if lastCreditGuiPos then
            frame.Position = lastCreditGuiPos
        elseif Settings.CreditGuiPosition == "Right" then
            frame.Position = UDim2.new(1, -280, 1, -70)
        else
            frame.Position = UDim2.new(0, 20, 1, -70)
        end
        frame.Parent = sg

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0.5, 0)
        title.BackgroundTransparency = 1
        title.Text = T("⚡ VHT Hub Pro")
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

        MakeDraggable(title, frame, function(pos) lastCreditGuiPos = pos end)
        MakeDraggable(frame, frame, function(pos) lastCreditGuiPos = pos end)

        creditGuiInstance = sg
    elseif forcePosition and creditGuiInstance:FindFirstChild("MainFrame") then
        local frame = creditGuiInstance.MainFrame
        lastCreditGuiPos = nil
        if Settings.CreditGuiPosition == "Right" then
            frame.Position = UDim2.new(1, -280, 1, -70)
        else
            frame.Position = UDim2.new(0, 20, 1, -70)
        end
    end
end

MiscTab:AddDropdown({ Name = T("StatGuiPosition"),
    Default = Settings.StatGuiPosition,
    Options = { "Right", "Left" },
    Callback = function(v)
        Settings.StatGuiPosition = v
        lastStatGuiPos = nil
        UpdateStatGui(true)
        AutoSave()
    end
})

MiscTab:AddDropdown({ Name = T("CreditGuiPosition"),
    Default = Settings.CreditGuiPosition,
    Options = { "Left", "Right" },
    Callback = function(v)
        Settings.CreditGuiPosition = v
        lastCreditGuiPos = nil
        UpdateCreditGui(true)
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("StatGui"),
    Default = Settings.StatGui,
    Callback = function(v)
        Settings.StatGui = v
        UpdateStatGui(false)
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("CreditGui"),
    Default = Settings.CreditGui,
    Callback = function(v)
        Settings.CreditGui = v
        UpdateCreditGui(false)
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("RejoinIfGotKick"),
    Default = Settings.RejoinIfGotKick,
    Callback = function(v)
        Settings.RejoinIfGotKick = v
        AutoSave()
    end
})

MiscTab:AddToggle({ Name = T("Whitescreen(Reduce Cpu)"),
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

MiscTab:AddButton({ Name = T("infiniteyield"),
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))()
        end)
    end
})

MiscTab:AddButton({ Name = T("ResetCamera"),
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

MiscTab:AddButton({ Name = T("Copy VHT HUB Discord Link"),
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

    QueueScriptReload()

    task.wait(3)
    AutoSave(true)
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
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

local cachedSkillRemote = nil

local function IsLobby()
    if game.PlaceId == LOBBY_PLACE_ID or game.PlaceId == ALT_LOBBY_PLACE_ID then
        -- Kể cả trùng PlaceId, chỉ coi là trong trận nếu có Folder Dungeon hoặc Enemies có quái thật
        if workspace:FindFirstChild("Dungeon") ~= nil then return false end
        local em = workspace:FindFirstChild("Enemies")
        if em and #em:GetChildren() > 0 then return false end
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg and (pg:FindFirstChild("DungeonUI", true) or pg:FindFirstChild("StageTimer", true)) then return false end
        return true
    end

    -- Khi game.PlaceId khác PlaceId sảnh: 100% là đang trong Dungeon / Match!
    -- Chỉ coi là sảnh nếu có Folder Lobby thực sự chứa LobbySpawns và Elevators (trường hợp PlaceId đổi chưa cập nhật)
    if workspace:FindFirstChild("LobbySpawns") ~= nil and workspace:FindFirstChild("LobbyElevators") ~= nil then
        return true
    end

    return false
end

local function CheckInGame()
    if IsLobby() then return false end
    return true
end

-- VÔ HIỆU HÓA HOÀN TOÀN MỌI MÔ PHỎNG CLICK CHUỘT VẬT LÝ
-- Tuyệt đối không gửi SendMouseButtonEvent hay mouse1click để người chơi thoải mái setup menu và không bao giờ bị giật/kẹt chuột
local function SimulateLeftClick()
    return
end

-- HÀM MÔ PHỎNG BẤM PHÍM SKILL (1, 2, 3, 4, 5) - CHỈ DÙNG PHÍM SỐ, TUYỆT ĐỐI KHÔNG CLICK CHUỘT (CRIT-1)
local keyMap = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five
}

local cachedSkillButtons = {}
local lastSkillButtonScan = 0

local function GetSkillButton(nameKey)
    local now = os.clock()
    if now - lastSkillButtonScan > 2 or not cachedSkillButtons[nameKey] or not cachedSkillButtons[nameKey].Parent then
        lastSkillButtonScan = now
        cachedSkillButtons = {}
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, gui in ipairs(pg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled and not gui.Name:lower():find("orion") and not gui.Name:lower():find("vht") then
                    for _, desc in ipairs(gui:GetDescendants()) do
                        if (desc:IsA("ImageButton") or desc:IsA("TextButton")) and desc.Visible then
                            local dName = desc.Name:lower()
                            for _, k in ipairs({"1", "2", "3", "4", "5"}) do
                                if dName == k or dName == "skill" .. k or dName == "button" .. k or desc:GetAttribute("Skill") == tonumber(k) then
                                    cachedSkillButtons[k] = desc
                                end
                            end
                            if dName == "assist" or dName == "assistskill" or dName == "assistbtn" then
                                cachedSkillButtons["assist"] = desc
                            end
                            if dName == "fruit" or dName == "fruitskill" or dName == "fruitbtn" then
                                cachedSkillButtons["fruit"] = desc
                            end
                        end
                    end
                end
            end
        end
    end
    return cachedSkillButtons[nameKey]
end

local function ClickSkillButton(desc)
    if not desc or not desc.Parent then return end
    if getconnections then
        local actConns = getconnections(desc.Activated)
        if actConns and #actConns > 0 then
            for _, c in pairs(actConns) do pcall(function() c:Fire() end) end
            return
        end
        local clickConns = getconnections(desc.MouseButton1Click)
        if clickConns and #clickConns > 0 then
            for _, c in pairs(clickConns) do pcall(function() c:Fire() end) end
            return
        end
    end
    if firesignal then
        pcall(function() firesignal(desc.Activated) end)
    end
end

local function SimulateSkillKey(numStr)
    if not CheckInGame() or IsLobby() then return end
    if UserInputService:GetFocusedTextBox() then return end
    local kc = keyMap[tostring(numStr)]
    if kc then
        local fired = false
        pcall(function()
            if VirtualInputManager and VirtualInputManager.SendKeyEvent then
                VirtualInputManager:SendKeyEvent(true, kc, false, game)
                task.delay(0.015, function()
                    pcall(function() VirtualInputManager:SendKeyEvent(false, kc, false, game) end)
                end)
                fired = true
            end
        end)
        if not fired then
            pcall(function()
                if keypress and keyrelease then
                    keypress(kc.Value)
                    task.delay(0.015, function()
                        pcall(function() keyrelease(kc.Value) end)
                    end)
                end
            end)
        end
    end
end

-- HÀM KÍCH HOẠT SKILL TOÀN DIỆN SIÊU TỐC (MÔ PHỎNG PHÍM + REMOTE + UI CACHE)
local function CastSkill(skillNum)
    if not CheckInGame() or IsLobby() then return end
    if UserInputService:GetFocusedTextBox() then return end

    local sNum = tonumber(skillNum) or 1
    local sStr = tostring(skillNum)

    -- 1. Ưu tiên 1: Gửi phím bàn phím ảo (1-5) siêu tốc (nhanh nhất & tương thích 100% engine Roblox)
    SimulateSkillKey(skillNum)

    -- 2. Ưu tiên 2: Remote Event / Function của Anime Dimensions (100% ngầm)
    pcall(function()
        local skillRemote = cachedSkillRemote
        if not skillRemote or not skillRemote.Parent then
            cachedSkillRemote = FindRemote({"UseSkill", "SkillRemote", "Skill", "CastSkill", "ActivateSkill", "SkillEvent"})
            skillRemote = cachedSkillRemote
        end
        if skillRemote then
            SafeFireRemote(skillRemote, sNum)
        end
    end)

    -- 3. Ưu tiên 3: Kích hoạt nút UI Skill trong PlayerGui qua cache O(1)
    pcall(function()
        local btn = GetSkillButton(sStr)
        if btn then ClickSkillButton(btn) end
    end)
end

-- KÍCH HOẠT SKILL PHỤ (ASSIST SKILL - PHÍM E + REMOTE + UI CACHE)
local function UseAssistSkill()
    if not CheckInGame() or IsLobby() then return end
    if UserInputService:GetFocusedTextBox() then return end

    -- 1. Phím ảo E
    pcall(function()
        if VirtualInputManager and VirtualInputManager.SendKeyEvent then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.delay(0.015, function()
                pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
            end)
        elseif keypress and keyrelease then
            keypress(Enum.KeyCode.E.Value)
            task.delay(0.015, function()
                pcall(function() keyrelease(Enum.KeyCode.E.Value) end)
            end)
        end
    end)

    -- 2. Remote Assist
    pcall(function()
        local remote = FindRemote({"UseAssistSkill", "AssistSkill", "UseAssist", "Assist", "AssistRemote"})
        if remote then SafeFireRemote(remote) end
    end)

    -- 3. UI Assist Button (O(1) cache)
    pcall(function()
        local btn = GetSkillButton("assist")
        if btn then ClickSkillButton(btn) end
    end)
end

-- KÍCH HOẠT FRUIT SKILL (PHÍM F + REMOTE + UI CACHE)
local function UseFruitSkill()
    if not CheckInGame() or IsLobby() then return end
    if UserInputService:GetFocusedTextBox() then return end

    -- 1. Phím ảo F
    pcall(function()
        if VirtualInputManager and VirtualInputManager.SendKeyEvent then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.delay(0.015, function()
                pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)
            end)
        elseif keypress and keyrelease then
            keypress(Enum.KeyCode.F.Value)
            task.delay(0.015, function()
                pcall(function() keyrelease(Enum.KeyCode.F.Value) end)
            end)
        end
    end)

    -- 2. Remote Fruit
    pcall(function()
        local remote = FindRemote({"UseFruitSkill", "FruitSkill", "UseFruit", "Fruit", "FruitRemote"})
        if remote then SafeFireRemote(remote) end
    end)

    -- 3. UI Fruit Button (O(1) cache)
    pcall(function()
        local btn = GetSkillButton("fruit")
        if btn then ClickSkillButton(btn) end
    end)
end

-- HỆ THỐNG TẤN CÔNG THƯỜNG 100% KHÔNG DÙNG CHUỘT VẬT LÝ (TỰ ĐỘNG DÙNG TOOL & REMOTE)
local cachedAttackRemote = nil
local function PerformAttack(target)
    if not CheckInGame() or IsLobby() then return end
    if UserInputService:GetFocusedTextBox() then return end

    local attackMethod = Settings.SelectAttackMethod or "Skill"
    -- Nếu chọn chế độ Skill: Tuyệt đối không đánh thường, nhường toàn bộ cho Auto Skill
    if attackMethod == "Skill" then return end

    -- 1. Ưu tiên 1: Tự động chém/đánh bằng Tool.Activate() nếu nhân vật đang cầm vũ khí (100% không cần click chuột)
    local char = GetMyChar()
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            pcall(function() tool:Activate() end)
        end
    end

    -- 2. Ưu tiên 2: Tự động gửi Remote tấn công thường của Game (Không chạm vào chuột hay màn hình)
    local attackRemote = cachedAttackRemote
    if not attackRemote or not attackRemote.Parent then
        cachedAttackRemote = FindRemote({"Attack", "BasicAttack", "MeleeAttack", "Slash", "Punch", "LightAttack", "Hit", "Combat", "Damage"})
        attackRemote = cachedAttackRemote
    end
    if attackRemote then
        pcall(function()
            if target and target.root and target.root.Parent then
                -- Ưu tiên gửi root part (BasePart) — an toàn hơn Model instance
                SafeFireRemote(attackRemote, target.root)
            elseif target and target.model and target.model.Parent then
                SafeFireRemote(attackRemote, target.model)
            else
                SafeFireRemote(attackRemote)
            end
        end)
    end
end

-- HÀM KIỂM TRA MÁU AN TOÀN CHỐNG VĂNG RUNTIME LỖI NẾU 'Health' LÀ PART/FOLDER HITBOX
local function CheckIsAlive(model, hum)
    if not model or not model.Parent then return false end

    -- 1. Kiểm tra Humanoid State và Health
    if hum then
        local stateOk, state = pcall(function() return hum:GetState() end)
        if stateOk and state == Enum.HumanoidStateType.Dead then
            return false
        end
        local hOk, h = pcall(function() return hum.Health end)
        if hOk and type(h) == "number" and h > 0 then
            return true
        end
    end

    -- 2. Kiểm tra Attribute Health / HP
    local attrHp = model:GetAttribute("Health") or model:GetAttribute("HP") or model:GetAttribute("hp")
    if type(attrHp) == "number" and attrHp > 0 then
        return true
    end

    -- 3. Kiểm tra ValueBase (IntValue, NumberValue, StringValue)
    local hpObj = model:FindFirstChild("Health") or model:FindFirstChild("HP") or model:FindFirstChild("hp")
    if hpObj then
        if typeof(hpObj) == "Instance" and hpObj:IsA("ValueBase") then
            local ok, val = pcall(function() return tonumber(hpObj.Value) end)
            if ok and val and val > 0 then
                return true
            end
        elseif type(hpObj) == "number" and hpObj > 0 then
            return true
        end
    end

    -- 4. Kiểm tra nhãn hiển thị máu trên đầu quái (BillboardGui như 3789/4372)
    local bb = model:FindFirstChildOfClass("BillboardGui") or model:FindFirstChild("HealthBar", true) or model:FindFirstChild("Status", true)
    if bb then
        for _, lbl in ipairs(bb:GetDescendants()) do
            if lbl:IsA("TextLabel") and lbl.Text:find("%d") then
                local cur = lbl.Text:match("(%d+)[%s/]+")
                if cur and tonumber(cur) and tonumber(cur) > 0 then
                    return true
                end
            end
        end
    end

    -- 5. Fallback: Nếu có Humanoid và MaxHealth > 0 và chưa Dead, coi là còn sống
    if hum then
        local mOk, maxH = pcall(function() return hum.MaxHealth end)
        if mOk and type(maxH) == "number" and maxH > 0 then
            local sOk, isDead = pcall(function() return hum:GetState() == Enum.HumanoidStateType.Dead end)
            if not sOk or not isDead then
                return true
            end
        end
    end

    return false
end

-- HÀM TÌM TẤT CẢ QUÁI / BOSS TOÀN DIỆN (HỖ TRỢ MỌI PHÒNG, WAVES VÀ DUNGEON LỒNG NHAU)
local cachedEnemies = {}
local lastEnemyScan = 0

local function GetAllEnemies(forceRefresh)
    if not CheckInGame() or IsLobby() then return {} end
    local now = os.clock()
    if not forceRefresh and (now - lastEnemyScan < 0.25) then
        if #cachedEnemies > 0 then
            local valid = {}
            for _, item in ipairs(cachedEnemies) do
                if item.model and item.model.Parent and item.root and item.root.Parent then
                    local hum = item.hum or item.model:FindFirstChildOfClass("Humanoid")
                    if CheckIsAlive(item.model, hum) then
                        table.insert(valid, item)
                    end
                end
            end
            if #valid > 0 then
                cachedEnemies = valid
                return cachedEnemies
            end
        end
    end

    lastEnemyScan = now
    local enemies = {}
    local seen = {}
    local myChar = GetMyChar()

    local function Inspect(model)
        if not model or not model:IsA("Model") or model == myChar or seen[model] then return end
        if Players:GetPlayerFromCharacter(model) then return end

        local mName = model.Name:lower()
        if mName:find("npc") or mName:find("quest") or mName:find("shop") or mName:find("portal") or mName:find("dummy") or mName:find("stand") or mName:find("display") or mName:find("trainer") or mName:find("leaderboard") then return end
        if workspace:FindFirstChild("Lobby") and model:IsDescendantOf(workspace.Lobby) then return end

        -- BẮT BUỘC: Phải là NPC / Quái vật còn sống (Health > 0)
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not CheckIsAlive(model, hum) then return end

        local root = model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Head")
        if not root then return end

        -- Loại bỏ quái bị văng xuống vực (Y < -80) để chống kéo người chơi rơi map
        if root.Position.Y < -80 or root.Position.Y > 1000 then return end

        seen[model] = true
        table.insert(enemies, { model = model, root = root, hum = hum })
    end

    -- 1. Quét sâu mọi container quái vật đặc thù của Anime Dimensions Simulator
    local potentialContainers = {
        workspace:FindFirstChild("Enemies"),
        workspace:FindFirstChild("Mobs"),
        workspace:FindFirstChild("Monsters"),
        workspace:FindFirstChild("Entities"),
        workspace:FindFirstChild("Boss"),
        workspace:FindFirstChild("Bosses"),
        workspace:FindFirstChild("Dungeon"),
        workspace:FindFirstChild("Map"),
    }

    for _, container in ipairs(potentialContainers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") then
                    Inspect(child)
                elseif child:IsA("Folder") then
                    for _, sub in ipairs(child:GetChildren()) do
                        if sub:IsA("Model") then
                            Inspect(sub)
                        elseif sub:IsA("Folder") then
                            for _, sub2 in ipairs(sub:GetChildren()) do
                                if sub2:IsA("Model") then
                                    Inspect(sub2)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #enemies > 0 then
        cachedEnemies = enemies
        return enemies
    end

    -- 2. Quét sâu toàn bộ Workspace nếu không tìm thấy trong container chuẩn (hỗ trợ mọi Room/Wave lồng nhau)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            Inspect(obj)
        elseif obj:IsA("Folder") and obj.Name ~= "Terrain" and obj.Name ~= "Camera" and obj.Name ~= "Lobby" and obj.Name ~= "NPCs" and obj.Name ~= "Shops" and obj.Name ~= "Portals" then
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA("Model") then
                    Inspect(child)
                elseif child:IsA("Folder") then
                    for _, sub in ipairs(child:GetChildren()) do
                        if sub:IsA("Model") then
                            Inspect(sub)
                        elseif sub:IsA("Folder") then
                            for _, sub2 in ipairs(sub:GetChildren()) do
                                if sub2:IsA("Model") then
                                    Inspect(sub2)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    cachedEnemies = enemies
    return enemies
end

-- TỰ ĐỘNG CHUYỂN PHÒNG / QUA CỬA / CHECKPOINT KHI HẾT QUÁI TRONG PHÒNG HIỆN TẠI
local lastAdvanceRoomTick = 0
local function AdvanceToNextRoom()
    local now = os.clock()
    if now - lastAdvanceRoomTick < 1.0 then return end
    lastAdvanceRoomTick = now
    if not Settings.AutoNextRoom then return end

    local myRoot = GetMyRoot()
    if not myRoot then return end

    local candidateParts = {}
    local searchRoots = {
        workspace:FindFirstChild("Dungeon"),
        workspace:FindFirstChild("Map"),
        workspace
    }

    for _, container in ipairs(searchRoots) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("BasePart") then
                    local oName = obj.Name:lower()
                    if oName:find("door") or oName:find("gate") or oName:find("checkpoint") or oName:find("next") or oName:find("barrier") or oName:find("passage") then
                        if not oName:find("lobby") and not oName:find("leave") and not oName:find("spawn") then
                            table.insert(candidateParts, obj)
                        end
                    end
                elseif obj:IsA("Model") or obj:IsA("Folder") then
                    local oName = obj.Name:lower()
                    if oName:find("door") or oName:find("gate") or oName:find("checkpoint") or oName:find("next") or oName:find("barrier") or oName:find("portal") then
                        if not oName:find("lobby") and not oName:find("leave") and not oName:find("spawn") then
                            local part = obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
                            if part then table.insert(candidateParts, part) end
                        end
                    end
                    for _, sub in ipairs(obj:GetChildren()) do
                        if sub:IsA("BasePart") then
                            local sName = sub.Name:lower()
                            if sName:find("door") or sName:find("gate") or sName:find("checkpoint") or sName:find("touch") or sName:find("barrier") then
                                table.insert(candidateParts, sub)
                            end
                        end
                    end
                end
            end
        end
    end

    local bestPart = nil
    local bestDist = math.huge
    for _, part in ipairs(candidateParts) do
        local dist = (myRoot.Position - part.Position).Magnitude
        if dist > 8 and dist < bestDist then
            bestDist = dist
            bestPart = part
        end
    end

    if bestPart then
        pcall(function()
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.CFrame = bestPart.CFrame
            if firetouchinterest then
                firetouchinterest(myRoot, bestPart, 0)
                task.wait(0.05)
                firetouchinterest(myRoot, bestPart, 1)
            end
            for _, p in ipairs(bestPart.Parent:GetDescendants()) do
                if p:IsA("ProximityPrompt") and fireproximityprompt then
                    fireproximityprompt(p)
                end
            end
        end)
    end
end

-- HÀM LẤY MỤC TIÊU ƯU TIÊN GẦN NHẤT HOẶC BOSS (CÓ CHỐNG KẸT TARGET VÀ BLACKLIST QUÁI LỖI)
local stuckTargetModel = nil
local stuckTargetStartTime = 0
local targetBlacklist = {}

local function GetTarget()
    local enemies = GetAllEnemies()
    if #enemies == 0 then return nil end

    local myRoot = GetMyRoot()
    if not myRoot then return nil end

    local now = os.clock()

    -- Lọc bỏ mục tiêu đang bị Blacklist tạm thời do bị kẹt > 12s
    local filteredEnemies = {}
    for _, item in ipairs(enemies) do
        if item.model and (not targetBlacklist[item.model] or now > targetBlacklist[item.model]) then
            table.insert(filteredEnemies, item)
        end
    end
    if #filteredEnemies == 0 then
        filteredEnemies = enemies
    end

    -- 1. Ưu tiên Boss nếu được bật
    if Settings.AutoWalkOnlyBoss then
        for _, item in ipairs(filteredEnemies) do
            if item.model and item.model.Parent and item.root and item.root.Parent then
                local hum = item.hum or item.model:FindFirstChildOfClass("Humanoid")
                if CheckIsAlive(item.model, hum) then
                    local name = item.model.Name:lower()
                    local maxHp = hum and hum.MaxHealth or 0
                    if name:find("boss") or item.model:FindFirstChild("BossLabel") or item.model:FindFirstChild("Boss") or maxHp > 50000 or item.model:GetAttribute("IsBoss") then
                        return item
                    end
                end
            end
        end
    end

    -- 2. Tìm quái gần nhất còn sống thực sự
    local closest = nil
    local minDist = math.huge
    for _, item in ipairs(filteredEnemies) do
        if item.model and item.model.Parent and item.root and item.root.Parent then
            local hum = item.hum or item.model:FindFirstChildOfClass("Humanoid")
            if CheckIsAlive(item.model, hum) then
                local dist = (myRoot.Position - item.root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    closest = item
                end
            end
        end
    end

    -- Chống kẹt trên 1 quái duy nhất quá lâu (> 12 giây không hạ được)
    if closest then
        if stuckTargetModel == closest.model then
            if now - stuckTargetStartTime > 12 then
                targetBlacklist[closest.model] = now + 5
                stuckTargetModel = nil
                stuckTargetStartTime = 0
            end
        else
            stuckTargetModel = closest.model
            stuckTargetStartTime = now
        end
    else
        stuckTargetModel = nil
        stuckTargetStartTime = 0
    end

    return closest
end

-- VÒNG LẶP NOCLIP LIÊN TỤC (TỐI ƯU ZERO-ALLOCATION CHỐNG TỤT FPS VÀ TRÀN RÁC BỘ NHỚ) (Bug 4)
TrackConnection(RunService.Stepped:Connect(function()
    if not Settings.DisableNoclip and CheckInGame() and not IsLobby() then
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
local lastTargetModel = nil
local isDodging = false
_G.VHT_IsDodging = false

task.spawn(function()
    while task.wait(0.03) do
        if _G.VHT_SessionID ~= currentSessionID then
            if activeFarmTween then activeFarmTween:Cancel(); activeFarmTween = nil end
            local myRoot = GetMyRoot()
            if myRoot then
                local bv = myRoot:FindFirstChild("FarmBV")
                if bv then bv:Destroy() end
            end
            break
        end

        if not CheckInGame() or IsLobby() then
            if activeFarmTween then activeFarmTween:Cancel(); activeFarmTween = nil end
            local myRoot = GetMyRoot()
            if myRoot then
                local bv = myRoot:FindFirstChild("FarmBV")
                if bv then bv:Destroy() end
            end
            continue
        end

        local hasOtherPlayers = Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1
        if not hasOtherPlayers and (Settings.AutoMob or Settings.AutoPlay or Settings.AutoJoinMap) then
            local char = GetMyChar()
            local myRoot = GetMyRoot()
            local myHum = GetMyHumanoid()

            if char and myRoot and (not myHum or myHum.Health > 0) then
                if isDodging or _G.VHT_IsDodging then
                    -- Đang trong trạng thái né chiêu: tạm dừng kéo nhân vật đến quái, giữ nguyên BodyVelocity chống rơi
                    local bv = myRoot:FindFirstChild("FarmBV")
                    if not bv then
                        bv = Instance.new("BodyVelocity")
                        bv.Name = "FarmBV"
                        bv.MaxForce = Vector3.new(100000, 100000, 100000)
                        bv.Velocity = Vector3.zero
                        bv.Parent = myRoot
                    else
                        bv.Velocity = Vector3.zero
                    end
                    continue
                end
                local target = GetTarget()
                if target and target.root then
                    local targetCFrame = target.root.CFrame
                    local farmDist = tonumber(Settings.FarmDistance) or 7

                    local targetCF
                    if Settings.FarmPosition == "Behind" then
                        targetCF = targetCFrame * CFrame.new(0, 0, farmDist)
                    else
                        targetCF = targetCFrame * CFrame.new(0, farmDist, 0) * CFrame.Angles(math.rad(-90), 0, 0)
                    end

                    -- Khi đổi quái mới: hủy ngay tween cũ để lập tức dịch chuyển sang quái mới
                    if lastTargetModel ~= target.model then
                        lastTargetModel = target.model
                        if activeFarmTween then
                            activeFarmTween:Cancel()
                            activeFarmTween = nil
                        end
                    end

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
                            myRoot.AssemblyLinearVelocity = Vector3.zero
                            if char.PrimaryPart then
                                pcall(function() char:PivotTo(targetCF) end)
                            end
                            myRoot.CFrame = targetCF
                        end
                    end)

                    local bv = myRoot:FindFirstChild("FarmBV")
                    if not bv then
                        pcall(function() myRoot.AssemblyLinearVelocity = Vector3.zero; myRoot.AssemblyAngularVelocity = Vector3.zero end)
                        pcall(function() myRoot.Velocity = Vector3.zero; myRoot.RotVelocity = Vector3.zero end)
                        bv = Instance.new("BodyVelocity")
                        bv.Name = "FarmBV"
                        bv.MaxForce = Vector3.new(100000, 100000, 100000)
                        bv.Velocity = Vector3.new(0, 0, 0)
                        bv.Parent = myRoot
                    else
                        bv.Velocity = Vector3.new(0, 0, 0)
                    end

                    local attackMethod = Settings.SelectAttackMethod or "Skill"
                    local canMelee = (attackMethod ~= "Skill") and (Settings.AutoMelee or attackMethod == "Melee" or attackMethod == "Click")
                    if canMelee then
                        PerformAttack(target)
                    end
                else
                    if activeFarmTween then
                        activeFarmTween:Cancel()
                        activeFarmTween = nil
                    end
                    local bv = myRoot:FindFirstChild("FarmBV")
                    if bv then bv:Destroy() end

                    -- Tự động tiến vào phòng tiếp theo khi quái phòng hiện tại đã chết hết
                    AdvanceToNextRoom()
                end
            end
        else
            if activeFarmTween then
                activeFarmTween:Cancel()
                activeFarmTween = nil
            end
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
        if _G.VHT_SessionID ~= currentSessionID then break end
        if not CheckInGame() or IsLobby() then continue end
        local hasOtherPlayers = Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1
        if not hasOtherPlayers and Settings.KillAura then
            local attackMethod = Settings.SelectAttackMethod or "Click"
            local enemies = GetAllEnemies()
            if #enemies > 0 then
                if attackMethod ~= "Skill" then
                    PerformAttack(enemies[1])
                elseif Settings.AutoSkill then
                    -- AttackMethod là Skill và AutoSkill bật -> Kích hoạt 1 skill ngẫu nhiên với nhịp 0.2s siêu nhanh
                    local now = os.clock()
                    if now - lastKillAuraSkillTime >= 0.2 then
                        lastKillAuraSkillTime = now
                        local skills = { Settings.SkillFirst, Settings.SkillSecond, Settings.SkillThird, Settings.SkillFourth, Settings.SkillFifth }
                        local chosenSkill = skills[math.random(1, #skills)] or 1
                        CastSkill(chosenSkill)
                    end
                end
            end
        end
    end
end)

-- 5. VÒNG LẶP AUTO SKILL (MÔ PHỎNG PHÍM 1-5 & THỨ TỰ ƯU TIÊN + REMOTES + KHOẢNG CÁCH DISTANCETOSKILL)
task.spawn(function()
    while task.wait(0.08) do
        if _G.VHT_SessionID ~= currentSessionID then break end
        if not CheckInGame() or IsLobby() then continue end
        local hasOther = Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1
        if hasOther then continue end
        if not (Settings.AutoSkill or Settings.AutoPlay or Settings.AutoJoinMap) then continue end

        local myHum = GetMyHumanoid()
        local myRoot = GetMyRoot()

        if myHum and myHum.Health > 0 and myRoot then
            local target = GetTarget()
            local inRange = false
            if target and target.root then
                local dist = (myRoot.Position - target.root.Position).Magnitude
                if dist <= (tonumber(Settings.DistanceToSkill) or 30) then
                    inRange = true
                end
            end

            if inRange then
                -- Thứ tự chuẩn: SkillFirst (5) -> SkillSecond (4) -> SkillThird (1) -> SkillFourth (2) -> SkillFifth (3) -> Assist -> Fruit
                local skillOrder = {
                    Settings.SkillFirst or "5",
                    Settings.SkillSecond or "4",
                    Settings.SkillThird or "1",
                    Settings.SkillFourth or "2",
                    Settings.SkillFifth or "3"
                }

                for _, skillNum in ipairs(skillOrder) do
                    CastSkill(skillNum)
                    task.wait(0.015)
                end

                -- Kế tiếp: Kích hoạt Skill Phụ (Assist Skill)
                if Settings.AutoAssistSkill or Settings.AutoPlay then
                    UseAssistSkill()
                    task.wait(0.015)
                end

                -- Kế tiếp: Kích hoạt Fruit Skill
                if Settings.AutoFruitSkill or Settings.AutoPlay then
                    UseFruitSkill()
                    task.wait(0.015)
                end
            end
        end
    end
end)


-- 6. VÒNG LẶP AUTO DODGE SKILL (DÙNG TRỰC TIẾP RADIUS STUDS VÀ CHECK NÉ NGƯỜI CHƠI)
task.spawn(function()
    while task.wait(math.max(tonumber(Settings.TweenSpeedDodgePart) or 0.15, 0.05)) do
        if _G.VHT_SessionID ~= currentSessionID then break end
        if not CheckInGame() or IsLobby() then continue end
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then
            continue
        end
        local myHum = GetMyHumanoid()
        local myRoot = GetMyRoot()
        if Settings.AutoDodgeSkill and myHum and myHum.Health > 0 and myRoot then
            local dodgeRadius = tonumber(Settings.SizeDodgePart) or 25
            local candidates = {}
            for _, obj in pairs(workspace:GetChildren()) do
                table.insert(candidates, obj)
            end
            local fx = workspace:FindFirstChild("Effects")
            if fx then
                for _, obj in pairs(fx:GetChildren()) do table.insert(candidates, obj) end
            end
            local warnFolder = workspace:FindFirstChild("Warnings")
            if warnFolder then
                for _, obj in pairs(warnFolder:GetChildren()) do table.insert(candidates, obj) end
            end
            for _, obj in pairs(candidates) do
                if obj:IsA("BasePart") and (obj.Name:find("Warning") or (obj.Color == Color3.fromRGB(255, 0, 0) and obj.Transparency < (Settings.DodgePartTransparency or 0.9))) then
                    local dist = (myRoot.Position - obj.Position).Magnitude
                    if dist < dodgeRadius then
                        if not isDodging then
                            isDodging = true
                            _G.VHT_IsDodging = true
                            pcall(function()
                                local prevCF = myRoot.CFrame
                                local dodgeHeight = tonumber(Settings.SizeDodgePartY) or 100
                                -- Tính độ cao an toàn cố định từ vị trí hiện tại, tránh cộng dồn liên tiếp lên trời
                                local safeY = prevCF.Position.Y + dodgeHeight
                                myRoot.CFrame = CFrame.new(myRoot.Position.X, safeY, myRoot.Position.Z)

                                -- Giữ nguyên lực nâng BodyVelocity chống rơi tự do khi đang né trên không
                                local bv = myRoot:FindFirstChild("FarmBV")
                                if not bv then
                                    bv = Instance.new("BodyVelocity")
                                    bv.Name = "FarmBV"
                                    bv.MaxForce = Vector3.new(100000, 100000, 100000)
                                    bv.Velocity = Vector3.zero
                                    bv.Parent = myRoot
                                else
                                    bv.Velocity = Vector3.zero
                                end

                                task.wait(0.5)

                                if not (Settings.AutoMob or Settings.AutoPlay) and myRoot and myRoot.Parent then
                                    myRoot.CFrame = prevCF
                                end
                            end)
                            isDodging = false
                            _G.VHT_IsDodging = false
                        end
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
local lastInfResetTick = 0
local hasResetThisInfMatch = false
local waveLabelCache = nil
local lastWaveScanTick = 0
local progressedThisMatch = false
local progressedAtTime = 0

task.spawn(function()
    while task.wait(1.5) do
        if _G.VHT_SessionID ~= currentSessionID then break end

        -- Timeout reset: nếu đã click Leave >30s mà chưa rời được → retry
        if progressedThisMatch and progressedAtTime > 0 and (os.clock() - progressedAtTime > 30) then
            progressedThisMatch = false
            progressedAtTime = 0
        end

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

            if Settings.GoAFKIfRaidNotOpen then
                local myRoot = GetMyRoot()
                if myRoot then
                    pcall(function()
                        if #GetAllEnemies() == 0 then
                            local afkSpot = workspace:FindFirstChild("AFKZone") or workspace:FindFirstChild("SpawnLocation")
                            if afkSpot then myRoot.CFrame = afkSpot.CFrame * CFrame.new(0, 5, 0) end
                        end
                    end)
                end
            end
        end

        -- Infinite Mode Wave Reset Check (B3, Chống tự sát lặp vô hạn)
        if Settings.ResetINFMode then
            pcall(function()
                local foundText = nil
                if waveLabelCache and waveLabelCache.Parent then
                    foundText = waveLabelCache.Text
                else
                    waveLabelCache = nil
                    local nowTick = os.clock()
                    if nowTick - lastWaveScanTick >= 10 then
                        lastWaveScanTick = nowTick
                        local pg = LocalPlayer:FindFirstChild("PlayerGui")
                        if pg then
                            for _, obj in ipairs(pg:GetDescendants()) do
                                if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and (obj.Name == "Wave" or obj.Name == "WaveLabel") then
                                    if obj.Text and obj.Text:match("%d+") then
                                        waveLabelCache = obj
                                        foundText = obj.Text
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                local threshold = Settings.SelectWaveToReset or 100
                local currentWave = foundText and tonumber(foundText:match("%d+"))
                if currentWave and currentWave < threshold then
                    hasResetThisInfMatch = false
                end
                local now = os.clock()
                if currentWave and currentWave >= threshold and not hasResetThisInfMatch and (now - lastInfResetTick >= 15) then
                    local myHum = GetMyHumanoid()
                    if myHum and myHum.Health > 0 then
                        hasResetThisInfMatch = true
                        lastInfResetTick = now
                        myHum.Health = 0
                    end
                end
            end)
        end

        -- Auto Replay (B4 & B1) - Có tự động kiểm tra lên cấp để đổi map
        if IsLobby() then
            progressedThisMatch = false
        end

        if CheckInGame() and not IsLobby() and (Settings.AutoReplay or Settings.AutoPlay or Settings.AutoJoinMap) and not (isRaidOpen and Settings.StopReplayIfRaidOpen) then
            local bestMap = GetBestMapName()
            if _G.VHT_CurrentDimensionMap and _G.VHT_CurrentDimensionMap ~= "" and _G.VHT_CurrentDimensionMap:lower() == bestMap:lower() then
                progressedThisMatch = false
            end

            local shouldProgressToNewMap = false
            if (Settings.AutoSelectMap or (Settings.MapSelection == "Auto")) and not progressedThisMatch then
                if _G.VHT_CurrentDimensionMap and _G.VHT_CurrentDimensionMap ~= "" and _G.VHT_CurrentDimensionMap:lower() ~= bestMap:lower() then
                    shouldProgressToNewMap = true
                end
            end

            local matchEnded = false
            local replayBtnToClick = nil
            pcall(function()
                local now = os.clock()
                if not _G.VHT_ReplayCandidates or (now - (_G.VHT_LastReplayScan or 0) > 5) then
                    _G.VHT_LastReplayScan = now
                    _G.VHT_ReplayCandidates = {}
                    local pg = LocalPlayer:FindFirstChild("PlayerGui")
                    if pg then
                        for _, gui in ipairs(pg:GetDescendants()) do
                            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                                local btnText = (gui:IsA("TextButton") and gui.Text:lower()) or ""
                                local btnName = gui.Name:lower()
                                local isUnrelated = btnName:find("tutorial") or btnText:find("tutorial")
                                    or btnName:find("quest") or btnText:find("quest")
                                    or btnName:find("daily") or btnText:find("daily")
                                    or btnName:find("practice") or btnText:find("practice")
                                if (btnName:find("replay") or btnText:find("replay") or btnName:find("retry") or btnText:find("retry")) and not isUnrelated then
                                    table.insert(_G.VHT_ReplayCandidates, gui)
                                end
                            end
                        end
                    end
                end

                for i = #_G.VHT_ReplayCandidates, 1, -1 do
                    local gui = _G.VHT_ReplayCandidates[i]
                    if not gui or not gui.Parent then
                        table.remove(_G.VHT_ReplayCandidates, i)
                    elseif IsGuiElementReallyVisible(gui) then
                        matchEnded = true
                        replayBtnToClick = gui
                        break
                    end
                end
            end)

            if matchEnded then
                local leftToLobby = false
                if shouldProgressToNewMap then
                    -- Đã mở khóa map cao hơn và match đã kết thúc an toàn! Tìm và bấm nút Lobby / Home để về sảnh nhận map mới
                    pcall(function()
                        local pg = LocalPlayer:FindFirstChild("PlayerGui")
                        if pg then
                            local primaryLeaveBtn = nil
                            local secondaryLeaveBtn = nil

                            for _, gui in ipairs(pg:GetDescendants()) do
                                if (gui:IsA("TextButton") or gui:IsA("ImageButton")) and IsGuiElementReallyVisible(gui) then
                                    local btnText = (gui:IsA("TextButton") and gui.Text:lower():match("^%s*(.-)%s*$")) or ""
                                    local btnName = gui.Name:lower():match("^%s*(.-)%s*$") or ""

                                    local inUnrelatedMenu = false
                                    local cur = gui
                                    while cur and cur ~= workspace and cur ~= game do
                                        local cName = cur.Name:lower()
                                        if cName:find("quest") or cName:find("shop") or cName:find("setting") or cName:find("daily") or cName:find("tutorial") then
                                            inUnrelatedMenu = true
                                            break
                                        end
                                        cur = cur.Parent
                                    end

                                    if not inUnrelatedMenu then
                                        if btnText == "lobby" or btnName == "lobby" or btnText == "home" or btnName == "home" then
                                            primaryLeaveBtn = gui
                                            break
                                        elseif btnText == "leave" or btnName == "leave" or btnText == "exit" or btnName == "exit" then
                                            if not secondaryLeaveBtn then
                                                secondaryLeaveBtn = gui
                                            end
                                        end
                                    end
                                end
                            end

                            local targetLeaveBtn = primaryLeaveBtn or secondaryLeaveBtn
                            if targetLeaveBtn then
                                progressedThisMatch = true
                                progressedAtTime = os.clock()
                                leftToLobby = true
                                if getconnections then
                                    local actConns = getconnections(targetLeaveBtn.Activated)
                                    if actConns and #actConns > 0 then for _, c in pairs(actConns) do c:Fire() end end
                                    local clickConns = getconnections(targetLeaveBtn.MouseButton1Click)
                                    if clickConns and #clickConns > 0 then for _, c in pairs(clickConns) do c:Fire() end end
                                end
                                if firesignal then
                                    pcall(function() firesignal(targetLeaveBtn.Activated) end)
                                    pcall(function() firesignal(targetLeaveBtn.MouseButton1Click) end)
                                end
                            end
                        end
                    end)
                end

                if not leftToLobby and not progressedThisMatch then
                    if replayBtnToClick then
                        if getconnections then
                            local actConns = getconnections(replayBtnToClick.Activated)
                            if actConns and #actConns > 0 then
                                for _, conn in pairs(actConns) do conn:Fire() end
                            else
                                local clickConns = getconnections(replayBtnToClick.MouseButton1Click)
                                if clickConns and #clickConns > 0 then
                                    for _, conn in pairs(clickConns) do conn:Fire() end
                                end
                            end
                        end
                        if firesignal then
                            pcall(function() firesignal(replayBtnToClick.Activated) end)
                            pcall(function() firesignal(replayBtnToClick.MouseButton1Click) end)
                        end
                    end

                    pcall(function()
                        local replayRemote = FindRemote({"ReplayVote", "VoteReplay", "Replay"})
                        if replayRemote then 
                            SafeFireRemote(replayRemote, true)
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
    end
end)

-- 8. VÒNG LẶP AUTO BUY (VÉ RAID / TOKEN / METHOD) (B8, B1)
local buyTimestamps = {}
local buyConsecutiveErrors = 0
task.spawn(function()
    while task.wait(6) do
        if _G.VHT_SessionID ~= currentSessionID then break end
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end
        if not (Settings.BuyRushTicket or Settings.Buy100RaidToken) then continue end

        -- Chỉ thực hiện vòng lặp mua khi xác nhận người chơi đang ở sảnh chờ, tự động reset lỗi khi ở sảnh
        if CheckInGame() then
            buyConsecutiveErrors = 0
            continue
        end

        if buyConsecutiveErrors >= 3 then continue end

        local now = os.clock()
        for i = #buyTimestamps, 1, -1 do
            if now - buyTimestamps[i] > 60 then
                table.remove(buyTimestamps, i)
            end
        end
        if #buyTimestamps >= 10 then continue end

        local canAfford = true
        pcall(function()
            local searchFolders = { "leaderstats", "Data", "PlayerData", "Stats" }
            for _, folderName in ipairs(searchFolders) do
                local f = LocalPlayer:FindFirstChild(folderName)
                if f then
                    local methodLower = (Settings.SelectMethodBuy or "Raid Token"):lower():gsub(" ", "")
                    for _, val in ipairs(f:GetChildren()) do
                        if val:IsA("ValueBase") then
                            local vName = val.Name:lower():gsub(" ", "")
                            if vName:find(methodLower, 1, true) or methodLower:find(vName, 1, true) then
                                if tonumber(val.Value) and tonumber(val.Value) <= 0 then
                                    canAfford = false
                                    break
                                end
                            end
                        end
                    end
                end
                if not canAfford then break end
            end
        end)
        if not canAfford then continue end

        if Settings.BuyRushTicket then
            local buyRemote = FindRemote({"BuyRaidTicket", "BuyShopItem"})
            if buyRemote then
                local ok = SafeFireRemote(buyRemote, "RushTicket", 1, Settings.SelectMethodBuy)
                if ok then
                    table.insert(buyTimestamps, now)
                    buyConsecutiveErrors = 0
                else
                    buyConsecutiveErrors = buyConsecutiveErrors + 1
                end
            end
        end

        if Settings.Buy100RaidToken then
            local buyRemote = FindRemote({"BuyDioKey", "BuyShopItem"})
            if buyRemote then
                local ok = SafeFireRemote(buyRemote, "100RaidToken", 1, Settings.SelectMethodBuy)
                if ok then
                    table.insert(buyTimestamps, now)
                    buyConsecutiveErrors = 0
                else
                    buyConsecutiveErrors = buyConsecutiveErrors + 1
                end
            end
        end

        if buyConsecutiveErrors >= 3 then
            warn("⚠️ [AutoBuy]: Gặp lỗi 3 lần liên tiếp, tạm dừng mua để đảm bảo an toàn tài khoản!")
        end
    end
end)

-- 9. VÒNG LẶP AUTO BÁN THẺ RÁC THEO ĐỘ HIẾM (AUTO SELL CARD - KIỂM TRA TỒN TẠI TRÁNH SPAM)
local function FindCardsFolder()
    local lp = LocalPlayer
    for _, name in ipairs({"Data","PlayerData","Inventory"}) do
        local f = lp:FindFirstChild(name)
        if f then
            local c = f:FindFirstChild("Cards")
            if c then return c end
        end
    end
    local direct = lp:FindFirstChild("Cards")
    if direct and not direct:IsA("GuiObject") then return direct end
    return nil
end

task.spawn(function()
    while task.wait(10) do
        if _G.VHT_SessionID ~= currentSessionID then break end
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end
        if Settings.AutoSellCard then
            pcall(function()
                local hasCardToSell = false
                local targetRarity = (Settings.SelectRarity or "Common"):lower()
                local cardsFolder = FindCardsFolder()
                if cardsFolder then
                    for _, card in ipairs(cardsFolder:GetChildren()) do
                        local rarityVal = card:FindFirstChild("Rarity") or card:FindFirstChild("Tier")
                        if rarityVal then
                            local rVal = nil
                            if rarityVal:IsA("ValueBase") then
                                rVal = rarityVal.Value
                            else
                                rVal = rarityVal:GetAttribute("Value")
                            end
                            if rVal ~= nil and tostring(rVal):lower():find(targetRarity) then
                                hasCardToSell = true
                                break
                            end
                        elseif card.Name:lower():find(targetRarity) then
                            hasCardToSell = true
                            break
                        end
                    end
                end

                if hasCardToSell then
                    local sellRemote = FindRemote({"SellCards", "SellCard", "SellItem"})
                    if sellRemote then
                        SafeFireRemote(sellRemote, Settings.SelectRarity or "Common")
                    end
                end
            end)
        end
    end
end)

-- 10. VÒNG LẶP AUTO CLAIM QUESTS & REWARDS (HỖ TRỢ CUSTOM CODES TÙY CHỈNH)
task.spawn(function()
    while task.wait(5) do
        if _G.VHT_SessionID ~= currentSessionID then break end
        if Settings.DoNotThingIfHavePlayer and #Players:GetPlayers() > 1 then continue end
        if Settings.AutoClaimQuestAndReward then
            pcall(function()
                local claimQuests = FindRemote({"ClaimQuests", "ClaimQuest"})
                if claimQuests then SafeFireRemote(claimQuests) end
                local claimDaily = FindRemote({"ClaimDailyRewards", "ClaimDaily"})
                if claimDaily then SafeFireRemote(claimDaily) end
            end)
        end
        if Settings.AutoRedeemAllCode then
            local redeemedAny = false
            local codeRemote = FindRemote({"RedeemCode", "Code"})
            if codeRemote then
                pcall(function()
                    local codeString = Settings.CustomRedeemCodes or "UPDATE, DIMENSIONS, SEASON, FREEGEMS, BOOST"
                    for code in string.gmatch(codeString, "([^,%s]+)") do
                        local ok = SafeFireRemote(codeRemote, code)
                        if ok then
                            redeemedAny = true
                        end
                        task.wait(0.5)
                    end
                end)
                if redeemedAny then
                    Settings.AutoRedeemAllCode = false
                    ProgrammaticSetToggle(ToggleAutoRedeem, false)
                    AutoSave()
                end
            else
                if not _G.VHT_NotifiedMissingCodeRemote then
                    _G.VHT_NotifiedMissingCodeRemote = true
                    pcall(function()
                        OrionLib:MakeNotification({
                            Name = "Auto Redeem Code",
                            Content = "Không tìm thấy Remote Redeem Code trong game!",
                            Image = "rbxassetid://4483345998",
                            Time = 4
                        })
                    end)
                end
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
    { name = "Villain Dimension", minLevel = 46, keywords = { "villain", "academia" } },
    { name = "Sword Dimension", minLevel = 61, keywords = { "sword", "sao", "kirito" } },
    { name = "Ghoul Dimension", minLevel = 76, keywords = { "ghoul", "kaneki" } },
    { name = "Fate Dimension", minLevel = 91, keywords = { "fate" } },
    { name = "Slime Dimension", minLevel = 106, keywords = { "slime", "rimuru", "tempest" } },
    { name = "Devil Dimension", minLevel = 121, keywords = { "devil", "clover", "chainsaw" } },
    { name = "Pirate Dimension", minLevel = 136, keywords = { "pirate", "luffy" } },
    { name = "Alien Dimension", minLevel = 151, keywords = { "alien", "dragon" } },
    { name = "Giant Dimension", minLevel = 166, keywords = { "giant" } },
    { name = "Shadow Dimension", minLevel = 181, keywords = { "shadow" } },
    { name = "Esper Dimension", minLevel = 196, keywords = { "esper", "psychic" } },
    { name = "Soul Dimension", minLevel = 211, keywords = { "soul", "bleach", "shinigami" } }
}

local function HasInteract(part)
    if not part then return false end
    if part:FindFirstChildWhichIsA("TouchTransmitter") or part:FindFirstChild("TouchInterest") then
        return true
    end
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("ProximityPrompt") then return true end
    end
    if part.Parent then
        if part.Parent:FindFirstChildWhichIsA("TouchTransmitter") or part.Parent:FindFirstChild("TouchInterest") then
            return true
        end
        for _, child in ipairs(part.Parent:GetChildren()) do
            if child:IsA("ProximityPrompt") then return true end
        end
    end
    return false
end

function GetPlayerLevel()
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

-- HÀM ĐO ĐẠC SỨC MẠNH NHÂN VẬT (COMBAT POWER / STATS / DAMAGE / CARDS)
local lastPowerCacheTime = 0
local cachedPowerValue = 0
function GetPlayerPower()
    local nowCache = os.clock()
    if cachedPowerValue > 0 and (nowCache - lastPowerCacheTime < 2) then
        return cachedPowerValue
    end
    local power = 0
    local level = GetPlayerLevel()
    pcall(function()
        -- 1. Tìm giá trị Power / CombatPower / Attack / Damage / BP trong player stats
        local searchFolders = { "leaderstats", "Data", "Stats", "PlayerData", "PlayerStats", "StatsFolder" }
        local statNames = { "Power", "CombatPower", "TotalPower", "Attack", "Damage", "BP", "Strength", "Atk" }
        for _, folderName in ipairs(searchFolders) do
            local f = LocalPlayer:FindFirstChild(folderName)
            if f then
                for _, sName in ipairs(statNames) do
                    local v = f:FindFirstChild(sName)
                    if v and (v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("StringValue")) then
                        local val = tonumber(v.Value)
                        if val and val > power then power = val end
                    end
                end
            end
        end

        -- 2. Tìm trong Character Attributes hoặc Humanoid
        local char = GetMyChar()
        if char then
            for _, attr in ipairs(statNames) do
                local val = tonumber(char:GetAttribute(attr))
                if val and val > power then power = val end
            end
        end

        -- 3. Quét PlayerGui tìm nhãn Text hiển thị Power / Sức Mạnh / ATK / Damage
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, lbl in ipairs(pg:GetDescendants()) do
                if lbl:IsA("TextLabel") and lbl.Visible then
                    local txt = lbl.Text:lower()
                    if txt:find("power") or txt:find("sức mạnh") or txt:find("combat") or txt:find("atk") or txt:find("dps") then
                        local clean = lbl.Text:gsub(",", ""):gsub("k", "000"):gsub("m", "000000")
                        local num = tonumber(clean:match("%d+%.?%d*"))
                        if num and num > power then power = num end
                    end
                end
            end
        end

        -- 4. Tính toán sức mạnh hỗ trợ từ Cards (Thẻ bài)
        local cardsFolder = FindCardsFolder()
        if cardsFolder then
            local cardBonus = 0
            for _, card in ipairs(cardsFolder:GetChildren()) do
                local isEquipped = card:FindFirstChild("Equipped") or card:FindFirstChild("IsEquipped")
                if isEquipped and (isEquipped.Value == true or isEquipped.Value == 1) then
                    local r = card:FindFirstChild("Rarity") or card:FindFirstChild("Tier")
                    local rVal = r and tostring(r.Value):lower() or ""
                    local mult = 1
                    if rVal:find("mythic") then mult = 5
                    elseif rVal:find("legendary") then mult = 3
                    elseif rVal:find("epic") then mult = 2
                    elseif rVal:find("rare") then mult = 1.5 end

                    local cLvlVal = card:FindFirstChild("Level") or card:FindFirstChild("CardLevel")
                    local cLvl = cLvlVal and tonumber(cLvlVal.Value) or 1
                    cardBonus = cardBonus + (cLvl * 25 * mult)
                end
            end
            if cardBonus > 0 then
                power = math.max(power, power + cardBonus)
            end
        end
    end)

    if power <= 0 then
        power = level * 100
    end
    -- Cập nhật cache (chỉ cache khi power > 0)
    if power > 0 then
        lastPowerCacheTime = nowCache
        cachedPowerValue = power
    end
    return power
end

-- HÀM TỰ ĐỘNG CHỌN ĐỘ KHÓ PHÙ HỢP NHẤT THEO CẤP ĐỘ VÀ SỨC MẠNH
function GetBestDifficulty(mapName)
    if not Settings.AutoSelectMap and Settings.SelectDifficulty and Settings.SelectDifficulty ~= "Auto" and Settings.SelectDifficulty ~= "" then
        return Settings.SelectDifficulty
    end

    local currentLevel = GetPlayerLevel()
    local currentPower = GetPlayerPower()

    local mapMinLevel = 1
    for _, dim in ipairs(dimensionLevels) do
        if dim.name:lower() == (mapName or ""):lower() then
            mapMinLevel = dim.minLevel or 1
            break
        end
    end

    local reqHard = mapMinLevel + 5
    local reqNightmare = mapMinLevel + 10

    -- Ngưỡng sức mạnh an toàn theo từng độ khó:
    -- Easy: Cấp độ mở map (mapMinLevel)
    -- Hard: Cấp độ mapMinLevel + 5 và Sức mạnh >= reqHard * 80
    -- Nightmare: Cấp độ mapMinLevel + 10 và Sức mạnh >= reqNightmare * 90
    local powerReqHard = reqHard * 80
    local powerReqNightmare = reqNightmare * 90

    if currentLevel >= reqNightmare and currentPower >= powerReqNightmare then
        return "Nightmare"
    elseif currentLevel >= reqHard and currentPower >= powerReqHard then
        return "Hard"
    else
        return "Easy"
    end
end

-- HÀM TỰ ĐỘNG CHỌN MAP THÔNG MINH THEO CẢ CẤP ĐỘ VÀ SỨC MẠNH
function GetBestMapName()
    if not Settings.AutoSelectMap and Settings.MapSelection and Settings.MapSelection ~= "Auto" and Settings.MapSelection ~= "" then
        return Settings.MapSelection
    end

    local currentLevel = GetPlayerLevel()
    local currentPower = GetPlayerPower()
    local bestMap = "Titan Dimension"
    local highestUnlockedIndex = 1

    for i, dim in ipairs(dimensionLevels) do
        if currentLevel >= dim.minLevel then
            highestUnlockedIndex = i
            bestMap = dim.name
        end
    end

    -- THUẬT TOÁN AN TOÀN SỨC MẠNH:
    -- Nếu vừa lên cấp mở map mới (level chỉ vừa chạm minLevel hoặc minLevel + 1)
    -- nhưng chỉ số sức mạnh nhân vật quá yếu (chưa đủ card/trang bị, power < minLevel * 75)
    -- hệ thống sẽ tự động chọn map trước đó (nơi có thể đi Nightmare mượt mà)
    -- để tiếp tục farm EXP và Card xịn, tránh việc vào map mới bị quái hạ gục liên tục!
    if highestUnlockedIndex > 1 then
        local currentDim = dimensionLevels[highestUnlockedIndex]
        local prevDim = dimensionLevels[highestUnlockedIndex - 1]
        local safePowerThreshold = currentDim.minLevel * 75

        if currentLevel < currentDim.minLevel + 2 and currentPower < safePowerThreshold then
            bestMap = prevDim.name
        end
    end

    return bestMap
end

local portalCache = {}

local function GetPortalInteractivePart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    local candidate = obj:FindFirstChild("Hitbox")
        or obj:FindFirstChild("Portal")
        or obj:FindFirstChild("Touch")
        or obj:FindFirstChild("Teleport")
        or obj:FindFirstChild("Enter")
        or obj:FindFirstChild("Gate")
        or obj.PrimaryPart
    if candidate and candidate:IsA("BasePart") then return candidate end
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("BasePart") and HasInteract(child) then
            return child
        end
    end
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("BasePart") and not child.Name:lower():find("deco") then
            return child
        end
    end
    return nil
end

local function IsExcludedFromDimension(obj)
    if not obj then return true end
    local cur = obj
    while cur and cur ~= workspace and cur ~= game do
        local n = cur.Name:lower()
        if n:find("inf", 1, true) or n:find("infinite", 1, true)
            or n:find("raid", 1, true) or n:find("boss", 1, true)
            or n:find("speed", 1, true) or n:find("challenge", 1, true) then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function FindPortalPart(mapName)
    local targetClean = mapName:lower():gsub(" dimension", ""):gsub(" ", "")
    local targetFull = mapName:lower():gsub(" ", "")
    if portalCache[targetClean] and portalCache[targetClean].Parent then
        return portalCache[targetClean]
    end

    local searchContainers = {
        workspace:FindFirstChild("Portals"),
        workspace:FindFirstChild("Dimensions"),
        workspace:FindFirstChild("Elevators"),
        workspace:FindFirstChild("LobbyPortals"),
        workspace:FindFirstChild("LobbyElevators"),
        workspace:FindFirstChild("Lobby"),
        workspace
    }

    -- Pass 1: Tìm Model / Folder / Part có tên trùng với targetClean hoặc targetFull (TUYỆT ĐỐI LOẠI BỎ INFINITE/RAID)
    for _, container in ipairs(searchContainers) do
        if container and not IsExcludedFromDimension(container) then
            for _, obj in ipairs(container:GetChildren()) do
                if not IsExcludedFromDimension(obj) then
                    local oName = obj.Name:lower():gsub(" ", "")
                    if oName == targetClean or oName == targetFull or oName == targetClean .. "portal" or oName == targetFull .. "portal" then
                        local part = GetPortalInteractivePart(obj)
                        if part and not IsExcludedFromDimension(part) then
                            portalCache[targetClean] = part
                            return part
                        end
                    end
                end
            end
        end
    end

    -- Pass 2: Quét toàn bộ Descendants tìm obj có tên chứa từ khóa
    for _, container in ipairs(searchContainers) do
        if container and not IsExcludedFromDimension(container) then
            for _, obj in ipairs(container:GetDescendants()) do
                if not IsExcludedFromDimension(obj) then
                    local oName = obj.Name:lower():gsub(" ", "")
                    if oName:find(targetClean, 1, true) or oName:find(targetFull, 1, true) then
                        local part = GetPortalInteractivePart(obj)
                        if part and not IsExcludedFromDimension(part) then
                            portalCache[targetClean] = part
                            return part
                        end
                    end
                end
            end
        end
    end

    -- Pass 3: Tìm theo từ khóa anime phụ (dimensionLevels)
    local keywords = {}
    for _, dim in ipairs(dimensionLevels) do
        if dim.name:lower() == mapName:lower() then
            keywords = dim.keywords or {}
            break
        end
    end
    for _, kw in ipairs(keywords) do
        for _, container in ipairs(searchContainers) do
            if container and not IsExcludedFromDimension(container) then
                for _, obj in ipairs(container:GetDescendants()) do
                    if not IsExcludedFromDimension(obj) then
                        local oName = obj.Name:lower():gsub(" ", "")
                        if oName:find(kw, 1, true) then
                            local part = GetPortalInteractivePart(obj)
                            if part and not IsExcludedFromDimension(part) then
                                portalCache[targetClean] = part
                                return part
                            end
                        end
                    end
                end
            end
        end
    end

    -- Pass 4: Fallback - Tìm thang máy thường (Elevator) KHÔNG PHẢI Infinite Mode
    local lobbyElevators = workspace:FindFirstChild("LobbyElevators") or workspace:FindFirstChild("Elevators") or workspace:FindFirstChild("Portals")
    if lobbyElevators then
        for _, child in ipairs(lobbyElevators:GetChildren()) do
            if not IsExcludedFromDimension(child) then
                local p = GetPortalInteractivePart(child)
                if p and not IsExcludedFromDimension(p) then
                    portalCache[targetClean] = p
                    return p
                end
            end
        end
    end

    for _, container in ipairs(searchContainers) do
        if container and not IsExcludedFromDimension(container) then
            for _, obj in ipairs(container:GetDescendants()) do
                if not IsExcludedFromDimension(obj) and (obj:IsA("BasePart") or obj:IsA("Model")) then
                    local oName = obj.Name:lower()
                    if (oName:find("portal") or oName:find("elevator") or oName:find("enter") or oName:find("dungeon"))
                        and not (oName:find("inf") or oName:find("raid") or oName:find("boss")) then
                        local p = GetPortalInteractivePart(obj)
                        if p and not IsExcludedFromDimension(p) then
                            portalCache[targetClean] = p
                            return p
                        end
                    end
                end
            end
        end
    end

    return nil
end

local isJoining = false
local joinStartTime = 0
local hasWaitedLobby = true
local raidJoinFails = 0
task.spawn(function()
    while task.wait(1.5) do
        if isJoining and (os.clock() - joinStartTime > 15) then
            isJoining = false
        end
        if _G.VHT_SessionID ~= currentSessionID then break end
        local isLobby = IsLobby()

        if isLobby then
            if not hasWaitedLobby then
                local waitSec = tonumber(Settings.WaitOnLobbyAfterJoin) or 10
                if waitSec > 0 then
                    task.wait(waitSec)
                end
                hasWaitedLobby = true
            end

            local hasMapSelection = (Settings.MapSelection and Settings.MapSelection ~= "" and Settings.MapSelection ~= "Auto")
            local shouldJoin = Settings.AutoJoinMap
                or Settings.AutoPlay
                or Settings.AutoSelectMap
                or hasMapSelection
                or Settings.AutoRaid or Settings.AutoSpeedRaid
                or Settings.BossRush or Settings.FreeBossRush
                or Settings.AutoRaidChallenge or Settings.ExtremeDimension

            if shouldJoin and not isJoining then
                isJoining = true
                joinStartTime = os.clock()

                -- 1. Ưu tiên Boss Rush / Free Boss Rush (ĐỘC LẬP - KHÔNG ĐƯỢC CHẠY DIMENSION) (B1)
                if Settings.BossRush or Settings.FreeBossRush then
                    local initialJob = game.JobId
                    pcall(function()
                        local brRemote = FindRemote({"StartBossRush", "JoinBossRush", "BossRush"})
                        if brRemote then SafeFireRemote(brRemote, Settings.FreeBossRush) end
                    end)
                    for _ = 1, 10 do
                        task.wait(0.5)
                        if game.JobId ~= initialJob or CheckInGame() then break end
                    end
                    isJoining = false

                -- 2. Ưu tiên Raid Challenge (ĐỘC LẬP) (B1)
                elseif Settings.AutoRaidChallenge then
                    local initialJob = game.JobId
                    pcall(function()
                        local rcRemote = FindRemote({"StartRaidChallenge", "JoinRaidChallenge", "RaidChallenge"})
                        if rcRemote then SafeFireRemote(rcRemote) end
                    end)
                    for _ = 1, 10 do
                        task.wait(0.5)
                        if game.JobId ~= initialJob or CheckInGame() then break end
                    end
                    isJoining = false

                -- 3. Ưu tiên Extreme Dimension (ĐỘC LẬP) (B1)
                elseif Settings.ExtremeDimension then
                    local initialJob = game.JobId
                    pcall(function()
                        local edRemote = FindRemote({"StartExtremeDimension", "JoinExtremeDimension", "ExtremeDimension"})
                        if edRemote then
                            SafeFireRemote(edRemote, Settings.SelectExtremeDimensionDifficulty or "Extreme", Settings.ExtremeDimensionMinReward or 100)
                        end
                    end)
                    for _ = 1, 10 do
                        task.wait(0.5)
                        if game.JobId ~= initialJob or CheckInGame() then break end
                    end
                    isJoining = false

                -- 4. Auto Raid hoặc Auto Speed Raid (CÓ RANDOM KHI CHỌN AUTO) (B1)
                elseif Settings.AutoRaid or Settings.AutoSpeedRaid then
                    local initialJob = game.JobId
                    pcall(function()
                        local raidTarget = Settings.RaidSelection or "Auto"
                        if Settings.AutoSpeedRaid and (raidTarget == "Auto" or raidTarget == "") then
                            local raidList = { "Fluffy Raid", "Beast Raid", "Chainsaw Raid", "King of Curses Raid", "Infinite Shiro Raid", "Combat Giant Raid", "Red Emperor Raid", "Sun God Sora Raid", "Warlord Raid", "Tengu Raid", "Hime Raid", "Dark One Hero Raid" }
                            raidTarget = raidList[math.random(1, #raidList)]
                        end
                        local raidRemote = FindRemote({"JoinRaid", "EnterRaid", "RaidQueue"})
                        if raidRemote then
                            SafeFireRemote(raidRemote, raidTarget, Settings.SelectExtremeDimensionDifficulty or "Extreme")
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

                -- 5. Auto Dimension Map (CHẠY KHI BẬT AUTOJOINMAP, AUTOPLAY, AUTOSELECTMAP HOẶC CHỌN MAP)
                elseif Settings.AutoJoinMap or Settings.AutoPlay or Settings.AutoSelectMap or hasMapSelection then
                    local targetMap = GetBestMapName()
                    local targetDifficulty = GetBestDifficulty(targetMap)
                    local now = os.clock()

                    if not CheckInGame() and (targetMap ~= _G.VHT_LastDimMap or targetDifficulty ~= _G.VHT_LastDimDiff or (now - (_G.VHT_LastDimJoinTime or 0) >= 3)) then
                        _G.VHT_LastDimJoinTime = now
                        _G.VHT_LastDimMap = targetMap
                        _G.VHT_LastDimDiff = targetDifficulty
                        _G.VHT_CurrentDimensionMap = targetMap

                        -- 1. Gửi tất cả các Remote tạo phòng / tham gia phòng Dimension với độ khó tối ưu
                        pcall(function()
                            local roomRemote = FindRemote({"CreateRoom", "JoinRoom", "StartDungeon", "EnterDimension", "Elevator", "JoinDimension", "CreateDimension", "StartMatch", "EnterDungeon", "PlayDungeon", "QueueDimension", "SelectDimension"})
                            if roomRemote then
                                SafeFireRemote(roomRemote, targetMap, targetDifficulty, Settings.FriendOnly, Settings.Hardcore)
                                SafeFireRemote(roomRemote, targetMap, targetDifficulty)
                                SafeFireRemote(roomRemote, targetMap)
                            end
                        end)

                        -- 2. Dịch chuyển và Touch vào Cổng Portal / Bục Elevators
                        pcall(function()
                            local portal = FindPortalPart(targetMap)
                            local myRoot = GetMyRoot()
                            if portal and myRoot then
                                local portalPart = portal:IsA("BasePart") and portal or (portal:IsA("Model") and (portal.PrimaryPart or portal:FindFirstChildWhichIsA("BasePart", true)))
                                local portalCF = portalPart and portalPart.CFrame or (portal:IsA("Model") and portal:GetPivot())
                                if portalCF then
                                    myRoot.CFrame = portalCF * CFrame.new(0, 3, 0)
                                    if firetouchinterest and portalPart then
                                        pcall(function()
                                            firetouchinterest(myRoot, portalPart, 0)
                                            task.wait(0.05)
                                            firetouchinterest(myRoot, portalPart, 1)
                                        end)
                                    end
                                end
                                for _, p in pairs(portal:GetDescendants()) do
                                    if p:IsA("ProximityPrompt") and fireproximityprompt then
                                        pcall(function() fireproximityprompt(p) end)
                                    end
                                end
                                if portal.Parent then
                                    for _, p in pairs(portal.Parent:GetDescendants()) do
                                        if p:IsA("ProximityPrompt") and fireproximityprompt then
                                            pcall(function() fireproximityprompt(p) end)
                                        end
                                    end
                                end
                            end
                        end)

                        -- 3. Tự động chọn tab độ khó (Nightmare / Hard / Easy) và click các nút Start / Create / Solo trên GUI
                        pcall(function()
                            task.wait(0.3)
                            local pg = LocalPlayer:FindFirstChild("PlayerGui")
                            if not pg then return end

                            local function ClickButtonOnce(btn)
                                if not btn or not btn.Parent then return end
                                local clicked = false
                                if getconnections then
                                    local actConns = getconnections(btn.Activated)
                                    if actConns and #actConns > 0 then
                                        for _, conn in pairs(actConns) do pcall(function() conn:Fire() end) end
                                        clicked = true
                                    end
                                    local clickConns = getconnections(btn.MouseButton1Click)
                                    if clickConns and #clickConns > 0 then
                                        for _, conn in pairs(clickConns) do pcall(function() conn:Fire() end) end
                                        clicked = true
                                    end
                                end
                                if not clicked and firesignal then
                                    pcall(function() firesignal(btn.Activated) end)
                                    pcall(function() firesignal(btn.MouseButton1Click) end)
                                end
                            end

                            for _, gui in ipairs(pg:GetChildren()) do
                                if gui:IsA("ScreenGui") and gui.Enabled then
                                    local gName = gui.Name:lower()
                                    -- Bỏ qua GUI của Hub và thanh điều hướng chính (HUD / Main / Lobby) và BỎ QUA GUI CỦA CHẾ ĐỘ INFINITE
                                    local isBlockedGui = gName:find("orion", 1, true) or gName:find("vht", 1, true) or gName:find("slh", 1, true)
                                        or gName:find("infinite", 1, true) or (gName:find("inf", 1, true) and not gName:find("info", 1, true))
                                    if not isBlockedGui then
                                        for _, btn in ipairs(gui:GetDescendants()) do
                                            if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible and IsGuiElementReallyVisible(btn) then
                                                local bName = btn.Name:lower()
                                                local bText = (btn:IsA("TextButton") and btn.Text:lower()) or ""

                                                -- TUYỆT ĐỐI KHÔNG CLICK NÚT "PLAY" TRÊN HUD SẢNH (Khắc phục triệt để lỗi tự bấm làm mất menu map)
                                                local isLobbyPlayButton = bName == "play" or bName == "playbutton" or bName == "playbtn"
                                                    or bText == "play" or bText == "chơi"
                                                    or (bName:find("play", 1, true) and (gName:find("main") or gName:find("hud") or gName:find("lobby") or gName:find("bar")))
                                                if isLobbyPlayButton then
                                                    continue
                                                end

                                                -- TUYỆT ĐỐI KHÔNG CLICK VÀO CÁC NÚT INFINITE MODE HOẶC CÁC NÚT MUA SẮM
                                                local isDangerous = bName:find("buy", 1, true) or bText:find("buy", 1, true)
                                                    or bName:find("purchase", 1, true) or bText:find("purchase", 1, true)
                                                    or bName:find("robux", 1, true) or bText:find("robux", 1, true)
                                                    or bName:find("shop", 1, true) or bText:find("shop", 1, true)
                                                    or bName:find("gift", 1, true) or bText:find("gift", 1, true)
                                                    or bName:find("close", 1, true) or bText == "x" or bText == "close"
                                                    or bName:find("infinite", 1, true) or bText:find("infinite", 1, true)
                                                    or bText == "inf" or bName == "inf"
                                                if isDangerous then
                                                    continue
                                                end

                                                -- 3a. Ưu tiên click nút chọn Độ Khó tối ưu trên giao diện phòng
                                                local diffLower = (targetDifficulty or "Easy"):lower()
                                                if bText == diffLower or bName == diffLower or bText:find(diffLower, 1, true) or bName:find(diffLower, 1, true) then
                                                    ClickButtonOnce(btn)
                                                end

                                                -- 3b. Tự động click các nút Bắt đầu trận đấu (Start / Create / Solo / Ready / Confirm)
                                                -- TUYỆT ĐỐI KHÔNG chứa "play" để tránh xung đột với nút Play mở map của người chơi
                                                local isStartMatch = bText:find("start", 1, true) or bText:find("create", 1, true)
                                                    or bText:find("solo", 1, true) or bText:find("ready", 1, true)
                                                    or bText:find("confirm", 1, true)
                                                    or bName:find("start", 1, true) or bName:find("create", 1, true)
                                                    or bName:find("solo", 1, true) or bName:find("ready", 1, true)
                                                    or bName:find("confirm", 1, true)

                                                if isStartMatch then
                                                    ClickButtonOnce(btn)
                                                end

                                                -- 3c. Chọn tab Dimension / Story nếu giao diện có chia tab chế độ
                                                local isDimTab = (bText == "dimension" or bName == "dimension" or bText == "dimensions" or bName == "dimensions" or bText == "story" or bName == "story")
                                                if isDimTab then
                                                    ClickButtonOnce(btn)
                                                end

                                                -- 3d. Click chọn card Map nếu danh sách Dimension đang mở
                                                local mapClean = targetMap:lower():gsub(" dimension", ""):gsub(" ", "")
                                                if mapClean ~= "" then
                                                    local bClean = bText:gsub(" ", "")
                                                    local bnClean = bName:gsub(" ", "")
                                                    if not isStartMatch and not (bText == diffLower or bName == diffLower) then
                                                        if bClean == mapClean or bnClean == mapClean then
                                                            ClickButtonOnce(btn)
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end)
                    end

                    task.wait(2)
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
    if charVal and charVal:IsA("ValueBase") then return tostring(charVal.Value) end
    local attr = char:GetAttribute("Character") or char:GetAttribute("CharacterName")
    if attr then return tostring(attr) end
    local config = char:FindFirstChild("Configuration")
    if config then
        local nameVal = config:FindFirstChild("Name") or config:FindFirstChild("CharacterName")
        if nameVal and nameVal:IsA("ValueBase") then return tostring(nameVal.Value) end
    end
    local lpData = LocalPlayer:FindFirstChild("Data") or LocalPlayer:FindFirstChild("PlayerData")
    if lpData then
        local eq = lpData:FindFirstChild("EquippedCharacter") or lpData:FindFirstChild("CurrentCharacter")
        if eq and eq:IsA("ValueBase") then return tostring(eq.Value) end
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
        if slotVal and slotVal:IsA("ValueBase") then return tonumber(slotVal.Value) end
    end
    local attr = LocalPlayer:GetAttribute("CurrentSlot") or LocalPlayer:GetAttribute("Slot") or LocalPlayer:GetAttribute("ActiveSlot")
    if attr then return tonumber(attr) end
    local char = GetMyChar()
    if char then
        local cAttr = char:GetAttribute("CurrentSlot") or char:GetAttribute("Slot") or char:GetAttribute("ActiveSlot")
        if cAttr then return tonumber(cAttr) end
        local cVal = char:FindFirstChild("CurrentSlot") or char:FindFirstChild("Slot")
        if cVal and cVal:IsA("ValueBase") then return tonumber(cVal.Value) end
    end
    return nil
end

task.spawn(function()
    while task.wait(15) do
        if _G.VHT_SessionID ~= currentSessionID then break end
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
                local equipRemote = FindRemote({"EquipBestCharacter", "EquipCharacter", "AutoEquip"})
                if equipRemote then
                    local ok = SafeFireRemote(equipRemote)
                    if ok then hasEquippedCharacter = true end
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
                local switchRemote = FindRemote({"SwitchCharacter", "ChangeCharacter"})
                if switchRemote then
                    SafeFireRemote(switchRemote, 1)
                    currentActiveSlot = 1
                end
            end)
        elseif Settings.AutoResetToFirstAssist and currentActiveSlot ~= 2 then
            pcall(function()
                local switchRemote = FindRemote({"SwitchCharacter", "ChangeCharacter"})
                if switchRemote then
                    SafeFireRemote(switchRemote, 2)
                    currentActiveSlot = 2
                end
            end)
        end

        -- Chỉ fire equip card nếu mode hiện tại chưa được equip (HIGH-6: loại bỏ timer 60s gây spam re-equip liên tục) (B1)
        if Settings.EquipBestCard and lastEquippedCardMode ~= (Settings.EquipBestCardMode or "Damage/Crit") then
            pcall(function()
                local cardRemote = FindRemote({"EquipBestCards", "EquipBestCard", "EquipCards"})
                if cardRemote then
                    local targetMode = Settings.EquipBestCardMode or "Damage/Crit"
                    SafeFireRemote(cardRemote, targetMode)
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
        if _G.VHT_SessionID ~= currentSessionID then break end
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
                    pcall(function()
                        ReturnToLobby()
                        task.wait(exploitCooldown)
                        if game.PlaceId == initialPlace then
                            exploitCooldown = math.min(exploitCooldown * 2, 300)
                        else
                            exploitCooldown = 45
                        end
                    end)
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
        if _G.VHT_SessionID ~= currentSessionID then break end
        if Settings.StatGui and statGuiInstance and statGuiInstance:FindFirstChild("MainFrame") then
            local label = statGuiInstance.MainFrame:FindFirstChild("Content")
            if label then
                local elapsed = math.floor(os.clock() - (statGuiStartTime or os.clock()))
                local m = math.floor(elapsed / 60)
                local s = elapsed % 60
                local curMap = (Settings.MapSelection and Settings.MapSelection ~= "Auto" and Settings.MapSelection) or GetBestMapName()
                local curDiff = (Settings.SelectDifficulty and Settings.SelectDifficulty ~= "Auto" and Settings.SelectDifficulty) or GetBestDifficulty(curMap)
                local curPower = GetPlayerPower()
                local fpsDisplay = Settings.WhiteScreen and "Reduced (3D Off)" or string.format("%d", fps)
                label.Text = string.format(
                    "User: %s\nLevel: %s | Power: %s\nMap: %s\nDiff: %s\nFPS: %s | Time: %02d:%02d",
                    LocalPlayer.Name,
                    tostring(GetPlayerLevel()),
                    tostring(math.floor(curPower)),
                    curMap,
                    curDiff,
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
            local searchContainers = {}
            if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
            pcall(function() table.insert(searchContainers, CoreGui) end)
            pcall(function() table.insert(searchContainers, LocalPlayer:FindFirstChild("PlayerGui")) end)
            for _, cont in ipairs(searchContainers) do
                if cont then
                    for _, g in ipairs(cont:GetChildren()) do
                        if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                            g.Enabled = false
                        end
                    end
                end
            end
        end)
    end)
end

uiBuilding = false
if Settings.AutoDeleteMap then task.spawn(function() ApplyAutoDeleteMap(true) end) end
OrionLib:Init()

-- ===================================================================
-- ĐẢM BẢO GIAO DIỆN ORION LUÔN HIỂN THỊ NGAY LẬP TỨC TRÊN MỌI THIẾT BỊ (B10)
-- ===================================================================
local function EnsureOrionVisible()
    local searchContainers = {}
    if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
    pcall(function() table.insert(searchContainers, CoreGui) end)
    pcall(function() table.insert(searchContainers, LocalPlayer:FindFirstChild("PlayerGui")) end)
    for _, container in ipairs(searchContainers) do
        if container then
            for _, g in ipairs(container:GetChildren()) do
                if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                    g.Enabled = true
                    for _, child in ipairs(g:GetChildren()) do
                        if child:IsA("GuiObject") and child.Name ~= "NotificationHolder" then
                            child.Visible = true
                        end
                    end
                end
            end
        end
    end
end

if not Settings.CloseGuiAfterExecute then
    EnsureOrionVisible()
    task.delay(0.5, EnsureOrionVisible)
    task.delay(1.5, EnsureOrionVisible)
    task.delay(3, EnsureOrionVisible)
end

-- ===================================================================
-- NÚT TOGGLE MENU NỔI VHT HUB (B10, B11)
-- ===================================================================
pcall(function()
    local old1 = CoreGui:FindFirstChild("SLH_MenuToggleGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("SLH_MenuToggleGui"))
    if old1 then old1:Destroy() end
    local old2 = CoreGui:FindFirstChild("VHT_MenuToggleGui") or (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("VHT_MenuToggleGui"))
    if old2 then old2:Destroy() end

    local toggleGui = Instance.new("ScreenGui")
    toggleGui.Name = "VHT_MenuToggleGui"
    toggleGui.ResetOnSpawn = false
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(toggleGui) end
        toggleGui.Parent = CoreGui
    end)
    if not toggleGui.Parent then toggleGui.Parent = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5) end

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "VHT_ToggleBtn"
    toggleBtn.Size = UDim2.new(0, 52, 0, 26)
    toggleBtn.Position = UDim2.new(0, 12, 0.45, -13)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "VHT"
    toggleBtn.TextColor3 = Color3.fromRGB(0, 255, 220)
    toggleBtn.TextSize = 12
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.AutoButtonColor = true
    toggleBtn.Active = true
    toggleBtn.Parent = toggleGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = toggleBtn

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 180, 255)
    stroke.Thickness = 1.2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = toggleBtn

    local isGuiVisible = not Settings.CloseGuiAfterExecute
    local lastToggleTick = 0

    local function GetOrionEnabledState()
        local searchContainers = {}
        if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
        pcall(function() table.insert(searchContainers, CoreGui) end)
        pcall(function() table.insert(searchContainers, LocalPlayer:FindFirstChild("PlayerGui")) end)
        for _, c in ipairs(searchContainers) do
            if c then
                for _, g in ipairs(c:GetChildren()) do
                    if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                        for _, child in ipairs(g:GetChildren()) do
                            if child:IsA("GuiObject") and child.Name ~= "NotificationHolder" then
                                return g.Enabled and child.Visible
                            end
                        end
                        return g.Enabled
                    end
                end
            end
        end
        return isGuiVisible
    end

    local function ToggleMenu()
        local now = os.clock()
        if now - lastToggleTick < 0.12 then return end
        lastToggleTick = now

        local actualEnabled = GetOrionEnabledState()
        isGuiVisible = not actualEnabled
        toggleBtn.TextColor3 = isGuiVisible and Color3.fromRGB(0, 255, 220) or Color3.fromRGB(150, 150, 150)
        stroke.Color = isGuiVisible and Color3.fromRGB(0, 180, 255) or Color3.fromRGB(60, 70, 85)
        toggleBtn.BackgroundColor3 = isGuiVisible and Color3.fromRGB(16, 20, 28) or Color3.fromRGB(14, 16, 22)

        local searchContainers = {}
        if gethui then pcall(function() table.insert(searchContainers, gethui()) end) end
        pcall(function() table.insert(searchContainers, CoreGui) end)
        pcall(function() table.insert(searchContainers, LocalPlayer:FindFirstChild("PlayerGui")) end)
        for _, c in ipairs(searchContainers) do
            if c then
                for _, g in ipairs(c:GetChildren()) do
                    if (g.Name == "Orion" or g.Name:find("Orion")) and g:IsA("ScreenGui") then
                        g.Enabled = isGuiVisible
                        for _, child in ipairs(g:GetChildren()) do
                            if child:IsA("GuiObject") and child.Name ~= "NotificationHolder" then
                                child.Visible = isGuiVisible
                            end
                        end
                    end
                end
            end
        end
    end

    local dragging = false
    local dragStart = nil
    local startPos = nil
    local hasMoved = false

    TrackConnection(toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = toggleBtn.Position
            hasMoved = false
        end
    end))

    TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
                hasMoved = true
                toggleBtn.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end
    end))

    TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                if not hasMoved then
                    ToggleMenu()
                end
            end
        end
    end))

    TrackConnection(toggleBtn.Activated:Connect(function()
        if not hasMoved then
            ToggleMenu()
        end
    end))

    TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
            ToggleMenu()
        end
    end))
end)
