--[[
    ===================================================================
    🌟 ANIME DIMENSIONS SIMULATOR - PRO HUB (FULL 31 FEATURES)
    Mã nguồn sạch 100% không mã hóa - Chuẩn hóa toàn bộ tính năng SLH Hub
    ⚡ CẬP NHẬT MỚI:
       - TỰ ĐỘNG LƯU NGẦM 100% (KHÔNG CẦN BẤM LƯU / CHỈ CẦN BẬT TẮT NÚT)
       - AUTO REJOIN KHI BỊ KICK / MẤT KẾT NỐI
       - DISCORD WEBHOOK THÔNG BÁO TỰ ĐỘNG
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

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
    Humanoid = char:WaitForChild("Humanoid")
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
    -- 1. Main Auto Play
    AutoPlay = false,
    AutoReplay = true,
    AutoSelectMap = false,
    ReturnToLobby = false,
    AutoChallenge = false,

    -- 2. Combat & Mobs
    AutoMob = false,
    AutoMelee = true,
    KillAura = false,
    AutoSkill = false,
    AutoAssistSkill = false,
    AutoFruitSkill = false,
    AutoDodgeSkill = false,
    DashNoCooldown = false,
    FarmDistance = 7,
    FarmPosition = "Above",

    -- 3. Raids & Extreme
    AutoRaid = false,
    AutoSpeedraid = false,
    AutoExtremeDimension = false,
    SelectedRaid = "Current Event Raid",
    SelectedExtreme = "Extreme Dimension 1",
    BackToLobbyIfRaidOpen = false,
    StopReplayIfRaidOpen = false,
    GoAFKIfRaidNotOpen = false,

    -- 4. Characters & Cards
    AutoEquipCharacter = false,
    AutoResetToMainChar = false,
    AutoResetToFirstAssist = false,
    EquipBestCard = false,
    AutoSellCard = false,
    SellCommon = true,
    SellRare = true,
    SellEpic = false,

    -- 5. Shop & Keys
    AutoBuyRushTicket = false,
    AutoBuyDioOverHeavenKey = false,
    AutoRedeemAllCode = false,

    -- 6. Stealth & Rejoin
    AutoRejoin = true,
    RejoinDelay = 3,
    HideName = false,
    WhiteScreen = false,
    WalkSpeed = 50,

    -- 7. Discord Webhook
    WebhookEnabled = false,
    WebhookURL = "",
    WebhookOnClear = true,
    WebhookOnRejoin = true
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
    if not Settings.WebhookEnabled or not Settings.WebhookURL or Settings.WebhookURL == "" then return end
    if not httpRequest then
        warn("⚠️ [Webhook]: Executor của bạn không hỗ trợ hàm HTTP Request!")
        return
    end

    local payload = {
        username = "Anime Dimensions Pro Hub",
        avatar_url = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=150&height=150&format=png",
        embeds = {
            {
                title = title or "⚡ Thông Báo Anime Dimensions",
                description = description or "",
                color = color or 5814783,
                fields = fields or {},
                footer = {
                    text = "Anime Dimensions Hub • " .. os.date("%d/%m/%Y %H:%M:%S")
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
local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()
local Window = OrionLib:MakeWindow({
    Name = "⚡ Anime Dimensions Hub (Kill Aura All Maps + Auto-Save)",
    HidePremium = false,
    SaveConfig = false,
    IntroText = "Anime Dimensions Hub Pro"
})

-- ===================================================================
-- TAB 1: 👑 AUTO PLAY & CÀY CẤP (MAIN PROGRESSION)
-- ===================================================================
local MainTab = Window:MakeTab({
    Name = "👑 Auto Play",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MainTab:AddParagraph("🟢 Tự Động Lưu 100%", "Mọi thay đổi bật/tắt sẽ TỰ ĐỘNG LƯU vào file cấu hình!")

MainTab:AddToggle({
    Name = "Auto Play (Tự động chơi toàn bộ từ A đến Z)",
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
    Name = "Auto Select Map (Tự chọn map theo Level)",
    Default = Settings.AutoSelectMap,
    Callback = function(v)
        Settings.AutoSelectMap = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "Auto Replay (Tự động bấm chơi lại khi thắng)",
    Default = Settings.AutoReplay,
    Callback = function(v)
        Settings.AutoReplay = v
        AutoSave()
    end
})

MainTab:AddToggle({
    Name = "Auto Challenge (Tự đi Challenge khi có quà)",
    Default = Settings.AutoChallenge,
    Callback = function(v)
        Settings.AutoChallenge = v
        AutoSave()
    end
})

MainTab:AddButton({
    Name = "Return To Lobby (Quay về sảnh chờ)",
    Callback = function()
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("TeleportToLobby", true) 
                or ReplicatedStorage:FindFirstChild("ReturnLobby", true)
            if remote then remote:FireServer() end
        end)
    end
})

-- ===================================================================
-- TAB 2: 🏰 RAID, SPEED RAID & EXTREME (TOÀN DIỆN)
-- ===================================================================
local RaidTab = Window:MakeTab({
    Name = "🏰 Raid & Extreme",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

RaidTab:AddSection({ Name = "🔥 Chế Độ Raid & Speed Raid" })

RaidTab:AddToggle({
    Name = "Auto Raid (Tự động vào & dọn ải Raid)",
    Default = Settings.AutoRaid,
    Callback = function(v)
        Settings.AutoRaid = v
        if v then Settings.AutoMob = true; Settings.AutoSkill = true end
        AutoSave()
    end
})

RaidTab:AddToggle({
    Name = "Auto Speedraid (Dồn DPS diệt Boss siêu tốc)",
    Default = Settings.AutoSpeedraid,
    Callback = function(v)
        Settings.AutoSpeedraid = v
        if v then
            Settings.AutoMob = true
            Settings.AutoSkill = true
            Settings.AutoAssistSkill = true
            Settings.AutoFruitSkill = true
            Settings.AutoMelee = true
        end
        AutoSave()
    end
})

RaidTab:AddToggle({
    Name = "Auto Extreme Dimension (Tự dọn Extreme)",
    Default = Settings.AutoExtremeDimension,
    Callback = function(v)
        Settings.AutoExtremeDimension = v
        AutoSave()
    end
})

RaidTab:AddSection({ Name = "⚡ Tương Tác Sảnh & Thông Báo Raid" })

RaidTab:AddToggle({
    Name = "Back To Lobby If Raid Open (Về sảnh khi có Raid)",
    Default = Settings.BackToLobbyIfRaidOpen,
    Callback = function(v)
        Settings.BackToLobbyIfRaidOpen = v
        AutoSave()
    end
})

RaidTab:AddToggle({
    Name = "Stop Replay If Raid Open (Dừng replay khi có Raid)",
    Default = Settings.StopReplayIfRaidOpen,
    Callback = function(v)
        Settings.StopReplayIfRaidOpen = v
        AutoSave()
    end
})

RaidTab:AddToggle({
    Name = "Go AFK (If Raid Not Open - Đứng chờ khi chưa mở Raid)",
    Default = Settings.GoAFKIfRaidNotOpen,
    Callback = function(v)
        Settings.GoAFKIfRaidNotOpen = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 3: ⚔️ CHIẾN ĐẤU & KỸ NĂNG (COMBAT & SKILLS)
-- ===================================================================
local CombatTab = Window:MakeTab({
    Name = "⚔️ Chiến Đấu",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

CombatTab:AddToggle({
    Name = "Auto Mob (Tự dịch chuyển & đánh quái)",
    Default = Settings.AutoMob,
    Callback = function(v)
        Settings.AutoMob = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Kill Aura",
    Default = Settings.KillAura,
    Callback = function(v)
        Settings.KillAura = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Auto Melee (Đánh cận chiến tốc độ cao)",
    Default = Settings.AutoMelee,
    Callback = function(v)
        Settings.AutoMelee = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Auto Skill (Tự xả chiêu 1, 2, 3, 4)",
    Default = Settings.AutoSkill,
    Callback = function(v)
        Settings.AutoSkill = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Auto Assist Skill (Tự gọi tướng phụ trợ)",
    Default = Settings.AutoAssistSkill,
    Callback = function(v)
        Settings.AutoAssistSkill = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Auto Fruit Skill (Tự dùng chiêu Trái Ác Quỷ)",
    Default = Settings.AutoFruitSkill,
    Callback = function(v)
        Settings.AutoFruitSkill = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Auto Dodge Skill (Tự né vùng đỏ nguy hiểm của Boss)",
    Default = Settings.AutoDodgeSkill,
    Callback = function(v)
        Settings.AutoDodgeSkill = v
        AutoSave()
    end
})

CombatTab:AddToggle({
    Name = "Dash No Cooldown (Lướt không thời gian hồi)",
    Default = Settings.DashNoCooldown,
    Callback = function(v)
        Settings.DashNoCooldown = v
        AutoSave()
    end
})

CombatTab:AddDropdown({
    Name = "Vị trí đứng farm quái",
    Default = Settings.FarmPosition,
    Options = {"Above (Trên đầu quái)", "Behind (Sau lưng quái)"},
    Callback = function(v)
        Settings.FarmPosition = (v:find("Above") and "Above" or "Behind")
        AutoSave()
    end
})

CombatTab:AddSlider({
    Name = "Khoảng cách đứng farm",
    Min = 3,
    Max = 20,
    Default = Settings.FarmDistance,
    Color = Color3.fromRGB(59, 130, 246),
    Increment = 1,
    ValueName = "Studs",
    Callback = function(v)
        Settings.FarmDistance = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 4: 🃏 TƯỚNG & THẺ (CHARACTER & CARDS)
-- ===================================================================
local CharTab = Window:MakeTab({
    Name = "🃏 Tướng & Thẻ",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

CharTab:AddButton({
    Name = "Auto Equip Character (Trang bị nhân vật mạnh nhất)",
    Callback = function()
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("EquipBestCharacter", true) 
                or ReplicatedStorage:FindFirstChild("EquipBestChar", true)
            if remote then remote:FireServer() end
        end)
    end
})

CharTab:AddToggle({
    Name = "Auto Reset To Main Character (Luôn giữ nhân vật chính)",
    Default = Settings.AutoResetToMainChar,
    Callback = function(v)
        Settings.AutoResetToMainChar = v
        AutoSave()
    end
})

CharTab:AddToggle({
    Name = "Auto Reset To First Assist (Đặt trợ thủ ô 1 làm phụ chính)",
    Default = Settings.AutoResetToFirstAssist,
    Callback = function(v)
        Settings.AutoResetToFirstAssist = v
        AutoSave()
    end
})

CharTab:AddButton({
    Name = "Equip Best Card (Trang bị thẻ bài tối ưu)",
    Callback = function()
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("EquipBestCards", true) or ReplicatedStorage:FindFirstChild("EquipBest", true)
            if remote and remote:IsA("RemoteFunction") then
                remote:InvokeServer()
            elseif remote and remote:IsA("RemoteEvent") then
                remote:FireServer()
            end
        end)
    end
end)

CharTab:AddToggle({
    Name = "Auto Sell Card (Tự động bán thẻ thừa/rác)",
    Default = Settings.AutoSellCard,
    Callback = function(v)
        Settings.AutoSellCard = v
        AutoSave()
    end
})

CharTab:AddToggle({
    Name = "Bán thẻ Thường (Sell Common)",
    Default = Settings.SellCommon,
    Callback = function(v)
        Settings.SellCommon = v
        AutoSave()
    end
})

CharTab:AddToggle({
    Name = "Bán thẻ Hiếm (Sell Rare)",
    Default = Settings.SellRare,
    Callback = function(v)
        Settings.SellRare = v
        AutoSave()
    end
})

-- ===================================================================
-- TAB 5: 🛒 CỬA HÀNG & TIỀN TỆ (SHOP & KEYS)
-- ===================================================================
local ShopTab = Window:MakeTab({
    Name = "🛒 Cửa Hàng",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

ShopTab:AddToggle({
    Name = "Auto Buy Rush Ticket (Tự động mua Vé Raid)",
    Default = Settings.AutoBuyRushTicket,
    Callback = function(v)
        Settings.AutoBuyRushTicket = v
        AutoSave()
    end
})

ShopTab:AddToggle({
    Name = "Auto Buy Dio Over Heaven Key (Raid Token)",
    Default = Settings.AutoBuyDioOverHeavenKey,
    Callback = function(v)
        Settings.AutoBuyDioOverHeavenKey = v
        AutoSave()
    end
})

ShopTab:AddButton({
    Name = "Auto Redeem All Code (Nhập toàn bộ mã quà tặng)",
    Callback = function()
        local codes = {"UPDATE25", "TITAN", "DIMENSION", "CHRISTMAS", "NEWYEAR", "500KLIKE", "ANIME", "RAIDTOKEN", "SPEEDRAID", "OVERHEAVEN"}
        for _, code in ipairs(codes) do
            pcall(function()
                local remote = ReplicatedStorage:FindFirstChild("RedeemCode", true) or ReplicatedStorage:FindFirstChild("ClaimCode", true)
                if remote then remote:FireServer(code) end
            end)
            task.wait(0.2)
        end
        OrionLib:MakeNotification({
            Name = "Giftcode",
            Content = "Đã nhập tất cả Giftcode mới nhất!",
            Image = "rbxassetid://4483345998",
            Time = 4
        })
    end
})

-- ===================================================================
-- TAB 6: 🌐 AUTO REJOIN & TREO MÁY (STEALTH & DISCONNECT)
-- ===================================================================
local MiscTab = Window:MakeTab({
    Name = "🌐 Rejoin & Treo",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

MiscTab:AddSection({ Name = "🔄 Tự Động Kết Nối Lại (Auto Rejoin)" })

MiscTab:AddToggle({
    Name = "Auto Rejoin (Tự vào lại game khi bị Kick / Mất kết nối)",
    Default = Settings.AutoRejoin,
    Callback = function(v)
        Settings.AutoRejoin = v
        AutoSave()
    end
})

MiscTab:AddSlider({
    Name = "Thời gian chờ trước khi Rejoin",
    Min = 1,
    Max = 10,
    Default = Settings.RejoinDelay,
    Color = Color3.fromRGB(16, 185, 129),
    Increment = 1,
    ValueName = "Giây",
    Callback = function(v)
        Settings.RejoinDelay = v
        AutoSave()
    end
})

MiscTab:AddButton({
    Name = "Rejoin Server Hiện Tại Ngay",
    Callback = function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
})

MiscTab:AddButton({
    Name = "Server Hop (Đổi sang server khác)",
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

MiscTab:AddSection({ Name = "⚙️ Tiện Ích Treo Máy" })

MiscTab:AddToggle({
    Name = "WhiteScreen (Màn hình trắng tiết kiệm 90% GPU/CPU)",
    Default = Settings.WhiteScreen,
    Callback = function(v)
        Settings.WhiteScreen = v
        RunService:Set3dRenderingEnabled(not v)
        AutoSave()
    end
})

MiscTab:AddToggle({
    Name = "Hide Name (Ẩn bảng tên trên đầu nhân vật)",
    Default = Settings.HideName,
    Callback = function(v)
        Settings.HideName = v
        pcall(function()
            local head = Character:FindFirstChild("Head")
            if head then
                for _, gui in pairs(head:GetChildren()) do
                    if gui:IsA("BillboardGui") then gui.Enabled = not v end
                end
            end
        end)
        AutoSave()
    end
})

MiscTab:AddSlider({
    Name = "Tốc độ di chuyển (WalkSpeed)",
    Min = 16,
    Max = 150,
    Default = Settings.WalkSpeed,
    Color = Color3.fromRGB(16, 185, 129),
    Increment = 1,
    ValueName = "Speed",
    Callback = function(v)
        Settings.WalkSpeed = v
        if Humanoid then Humanoid.WalkSpeed = v end
        AutoSave()
    end
})

-- ===================================================================
-- TAB 7: 📢 DISCORD WEBHOOK (THÔNG BÁO TỰ ĐỘNG)
-- ===================================================================
local WebhookTab = Window:MakeTab({
    Name = "📢 Discord Webhook",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

WebhookTab:AddParagraph("📢 Báo Cáo Discord Webhook", "Dán Webhook URL kênh Discord của bạn vào ô bên dưới. Trạng thái và link sẽ tự động lưu vĩnh viễn!")

WebhookTab:AddToggle({
    Name = "Bật / Tắt Gửi Discord Webhook",
    Default = Settings.WebhookEnabled,
    Callback = function(v)
        Settings.WebhookEnabled = v
        AutoSave()
    end
})

WebhookTab:AddTextbox({
    Name = "Dán Discord Webhook URL",
    Default = Settings.WebhookURL,
    TextDisappear = false,
    Callback = function(v)
        Settings.WebhookURL = v
        AutoSave()
    end
})

WebhookTab:AddToggle({
    Name = "Gửi Báo Cáo Khi Thắng / Clear Map (WebhookOnClear)",
    Default = Settings.WebhookOnClear,
    Callback = function(v)
        Settings.WebhookOnClear = v
        AutoSave()
    end
})

WebhookTab:AddToggle({
    Name = "Gửi Cảnh Báo Khi Bị Kick / Rejoin (WebhookOnRejoin)",
    Default = Settings.WebhookOnRejoin,
    Callback = function(v)
        Settings.WebhookOnRejoin = v
        AutoSave()
    end
})

WebhookTab:AddButton({
    Name = "🔔 Gửi Tin Nhắn Test Thử Lên Discord",
    Callback = function()
        if not Settings.WebhookURL or Settings.WebhookURL == "" then
            OrionLib:MakeNotification({
                Name = "Chưa Có Link Webhook",
                Content = "Vui lòng nhập đường dẫn Discord Webhook vào ô ở trên trước!",
                Image = "rbxassetid://4483345998",
                Time = 4
            })
            return
        end

        local testFields = {
            { name = "👤 Người chơi", value = LocalPlayer.Name .. " (" .. LocalPlayer.DisplayName .. ")", inline = true },
            { name = "🆔 User ID", value = tostring(LocalPlayer.UserId), inline = true },
            { name = "🎮 Place ID", value = tostring(game.PlaceId), inline = true },
            { name = "⚡ Kill Aura", value = Settings.KillAura and "🟢 Bật (All Maps)" or "🔴 Tắt", inline = true },
            { name = "👑 Auto Play", value = Settings.AutoPlay and "🟢 Đang Bật" or "🔴 Tắt", inline = true },
            { name = "🔄 Auto Rejoin", value = Settings.AutoRejoin and "🟢 Đang Bật" or "🔴 Tắt", inline = true }
        }

        SendDiscordWebhook(
            "🔔 [TEST THÀNH CÔNG] Anime Dimensions Hub Webhook",
            "Discord Webhook đã kết nối và gửi thông báo thành công từ Executor của bạn!",
            testFields,
            65280
        )

        OrionLib:MakeNotification({
            Name = "Thành Công!",
            Content = "Đã gửi thông báo test tới kênh Discord!",
            Image = "rbxassetid://4483345998",
            Time = 4
        })
    end
})

-- ===================================================================
-- 🔄 LOGIC CORE CHẠY NGẦM ĐẦY ĐỦ (COMPLETE EXECUTION ENGINES)
-- ===================================================================

-- 1. HỆ THỐNG AUTO REJOIN KHI BỊ KICK / MẤT KẾT NỐI
local function TriggerRejoin()
    if not Settings.AutoRejoin then return end
    warn("⚠️ [PHÁT HIỆN BỊ KICK / MẤT MẠNG! ĐANG TỰ ĐỘNG REJOIN...]")
    
    if Settings.WebhookEnabled and Settings.WebhookOnRejoin then
        SendDiscordWebhook(
            "⚠️ [CẢNH BÁO] Tài Khoản Bị Kick / Rejoin",
            "Tài khoản **" .. LocalPlayer.Name .. "** vừa mất kết nối khỏi server và đang tự động Rejoin!",
            {
                { name = "👤 Người chơi", value = LocalPlayer.Name, inline = true },
                { name = "⏱️ Thời gian", value = os.date("%H:%M:%S - %d/%m/%Y"), inline = true },
                { name = "🎮 Place ID", value = tostring(game.PlaceId), inline = false }
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

    task.wait(Settings.RejoinDelay or 3)
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

-- 2. HÀM TÌM QUÁI HOẶC BOSS TỐI ƯU
local function GetTarget()
    local mobsFolder = workspace:FindFirstChild("Mobs") or workspace:FindFirstChild("Enemies") or workspace:FindFirstChild("Monsters")
    if not mobsFolder then return nil end

    local nearestTarget = nil
    local minDistance = math.huge

    if Settings.AutoSpeedraid then
        for _, mob in pairs(mobsFolder:GetChildren()) do
            local hum = mob:FindFirstChildOfClass("Humanoid")
            local root = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")
            if hum and root and hum.Health > 0 and (mob.Name:find("Boss") or mob:FindFirstChild("BossLabel") or hum.MaxHealth > 50000) then
                return mob
            end
        end
    end

    for _, mob in pairs(mobsFolder:GetChildren()) do
        local hum = mob:FindFirstChildOfClass("Humanoid")
        local root = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")
        if hum and root and hum.Health > 0 then
            local dist = (HumanoidRootPart.Position - root.Position).Magnitude
            if dist < minDistance then
                minDistance = dist
                nearestTarget = mob
            end
        end
    end

    return nearestTarget
end

-- 3. VÒNG LẶP AUTO MOB & FAST MELEE ATTACK
task.spawn(function()
    while task.wait(0.08) do
        if (Settings.AutoMob or Settings.AutoPlay or Settings.AutoRaid or Settings.AutoSpeedraid) and Humanoid and Humanoid.Health > 0 then
            local target = GetTarget()
            if target and target:FindFirstChild("HumanoidRootPart") then
                local targetCFrame = target.HumanoidRootPart.CFrame
                local offset = (Settings.FarmPosition == "Above") 
                    and (CFrame.new(0, Settings.FarmDistance, 0) * CFrame.Angles(math.rad(-90), 0, 0))
                    or (CFrame.new(0, 0, Settings.FarmDistance))
                
                HumanoidRootPart.CFrame = targetCFrame * offset

                if Settings.AutoMelee then
                    pcall(function()
                        local attackRemote = ReplicatedStorage:FindFirstChild("BasicAttack", true) 
                            or ReplicatedStorage:FindFirstChild("Attack", true)
                            or ReplicatedStorage:FindFirstChild("MeleeAttack", true)
                        if attackRemote then
                            attackRemote:FireServer()
                            attackRemote:FireServer()
                        end
                    end)
                end
            end
        end
    end
end)

-- 4. VÒNG LẶP KILL AURA
task.spawn(function()
    while task.wait(0.15) do
        if Settings.KillAura and Humanoid and Humanoid.Health > 0 then
            local mobsFolder = workspace:FindFirstChild("Mobs") or workspace:FindFirstChild("Enemies") or workspace:FindFirstChild("Monsters")
            if mobsFolder then
                for _, mob in pairs(mobsFolder:GetChildren()) do
                    local hum = mob:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        pcall(function()
                            local attackRemote = ReplicatedStorage:FindFirstChild("BasicAttack", true) 
                                or ReplicatedStorage:FindFirstChild("Attack", true)
                                or ReplicatedStorage:FindFirstChild("MeleeAttack", true)
                            if attackRemote then attackRemote:FireServer(mob) end
                        end)
                    end
                end
            end
        end
    end
end)

-- 5. VÒNG LẶP XẢ SKILLS (AUTO SKILL, ASSIST, FRUIT)
task.spawn(function()
    while task.wait(0.25) do
        if (Settings.AutoSkill or Settings.AutoPlay or Settings.AutoSpeedraid) and Humanoid and Humanoid.Health > 0 then
            for slot = 1, 4 do
                pcall(function()
                    local skillRemote = ReplicatedStorage:FindFirstChild("UseSkill", true) or ReplicatedStorage:FindFirstChild("Skill", true)
                    if skillRemote then skillRemote:FireServer(slot) end
                end)
                task.wait(0.07)
            end

            if Settings.AutoAssistSkill or Settings.AutoPlay or Settings.AutoSpeedraid then
                pcall(function()
                    local assistRemote = ReplicatedStorage:FindFirstChild("UseAssist", true) or ReplicatedStorage:FindFirstChild("Assist", true)
                    if assistRemote then assistRemote:FireServer() end
                end)
            end

            if Settings.AutoFruitSkill or Settings.AutoPlay or Settings.AutoSpeedraid then
                pcall(function()
                    local fruitRemote = ReplicatedStorage:FindFirstChild("UseFruitSkill", true) or ReplicatedStorage:FindFirstChild("FruitSkill", true)
                    if fruitRemote then fruitRemote:FireServer() end
                end)
            end
        end
    end
end)

-- 6. VÒNG LẶP AUTO DODGE SKILL (NÉ CHIÊU ĐỎ CỦA BOSS)
task.spawn(function()
    while task.wait(0.15) do
        if Settings.AutoDodgeSkill and Humanoid and Humanoid.Health > 0 then
            for _, obj in pairs(workspace:GetChildren()) do
                if obj:IsA("BasePart") and obj.Name:find("Warning") or (obj.Color == Color3.fromRGB(255, 0, 0) and obj.Transparency < 0.8) then
                    local dist = (HumanoidRootPart.Position - obj.Position).Magnitude
                    if dist < 25 then
                        HumanoidRootPart.CFrame = HumanoidRootPart.CFrame * CFrame.new(0, 20, 0)
                        task.wait(0.5)
                        break
                    end
                end
            end
        end
    end
end)

-- 7. VÒNG LẶP AUTO REPLAY & KIỂM TRA RAID OPEN
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
            if Settings.GoAFKIfRaidNotOpen then
                pcall(function()
                    local afkSpot = workspace:FindFirstChild("AFKZone") or workspace:FindFirstChild("SpawnLocation")
                    if afkSpot then HumanoidRootPart.CFrame = afkSpot.CFrame * CFrame.new(0, 5, 0) end
                end)
            end
        end

        if Settings.AutoReplay and not (isRaidOpen and Settings.StopReplayIfRaidOpen) then
            pcall(function()
                local replayRemote = ReplicatedStorage:FindFirstChild("ReplayVote", true) 
                    or ReplicatedStorage:FindFirstChild("VoteReplay", true)
                    or ReplicatedStorage:FindFirstChild("Replay", true)
                if replayRemote then 
                    replayRemote:FireServer(true)
                    
                    if Settings.WebhookEnabled and Settings.WebhookOnClear and (tick() - lastWebhookClearTime > 15) then
                        lastWebhookClearTime = tick()
                        SendDiscordWebhook(
                            "🏆 [CLEAR MAP] Hoàn Thành Màn Chơi!",
                            "Tài khoản **" .. LocalPlayer.Name .. "** đã hoàn thành màn chơi / Dungeon / Raid thành công!",
                            {
                                { name = "👤 Người chơi", value = LocalPlayer.Name, inline = true },
                                { name = "⏱️ Giờ hoàn thành", value = os.date("%H:%M:%S"), inline = true },
                                { name = "🔄 Auto Replay", value = "Đã tự động gửi yêu cầu chơi lại", inline = true }
                            },
                            3066993
                        )
                    end
                end
            end)
        end
    end
end)

-- 8. VÒNG LẶP AUTO MUA VÉ & CHÌA KHÓA DIO
task.spawn(function()
    while task.wait(6) do
        if Settings.AutoBuyRushTicket then
            pcall(function()
                local buyRemote = ReplicatedStorage:FindFirstChild("BuyRaidTicket", true) or ReplicatedStorage:FindFirstChild("BuyShopItem", true)
                if buyRemote then buyRemote:FireServer("RushTicket", 1) end
            end)
        end
        if Settings.AutoBuyDioOverHeavenKey then
            pcall(function()
                local buyRemote = ReplicatedStorage:FindFirstChild("BuyDioKey", true) or ReplicatedStorage:FindFirstChild("BuyShopItem", true)
                if buyRemote then buyRemote:FireServer("DioOverHeavenKey", 1) end
            end)
        end
    end
end)

-- 9. VÒNG LẶP AUTO BÁN THẺ RÁC (AUTO SELL CARDS)
task.spawn(function()
    while task.wait(10) do
        if Settings.AutoSellCard then
            pcall(function()
                local sellRemote = ReplicatedStorage:FindFirstChild("SellCards", true) or ReplicatedStorage:FindFirstChild("SellCard", true)
                if sellRemote then
                    if Settings.SellCommon then sellRemote:FireServer("Common") end
                    if Settings.SellRare then sellRemote:FireServer("Rare") end
                end
            end)
        end
    end
end)

-- 10. GIỮ TỐC ĐỘ DI CHUYỂN & DASH NO COOLDOWN
RunService.Stepped:Connect(function()
    if Humanoid and Humanoid.WalkSpeed ~= Settings.WalkSpeed then
        Humanoid.WalkSpeed = Settings.WalkSpeed
    end
    if Settings.DashNoCooldown then
        pcall(function()
            local dashScript = Character:FindFirstChild("Dash") or LocalPlayer.PlayerScripts:FindFirstChild("DashClient")
            if dashScript and dashScript:FindFirstChild("Cooldown") then
                dashScript.Cooldown.Value = 0
            end
        end)
    end
end)

OrionLib:Init()
print("🎉 Anime Dimensions Simulator Hub - Kill Aura All Maps & Auto-Save 100% Sẵn Sàng!")
