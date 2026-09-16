local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- โหลด MacLib UI
local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()

local Window = MacLib:Window({
    Title                  = "Pwc",
    Subtitle               = "Ride A Pet  | V 1.0",
    Size                   = UDim2.fromOffset(800, 600),
    DragStyle              = 1,
    DisabledWindowControls = {},
    ShowUserInfo           = true,
    Keybind                = Enum.KeyCode.RightControl,
    AcrylicBlur            = true,
})

Window:Notify({
    Title       = "Pwc",
    Description = "Ride A Pet Script Loaded!",
    Lifetime    = 5
})

local TabGroup = Window:TabGroup()
local Main = TabGroup:Tab({
    Name  = "MAIN",
    Image = "rbxassetid://6031280882",
})

local MainSection = Main:Section({ Side = "Left", Name = "ESP & Detection" })
local TeleportSection = Main:Section({ Side = "Right", Name = "Teleport Settings" })

-- ==========================================
-- SHARED DATA & CONFIGURATIONS
-- ==========================================
local RenderedEggs = Workspace:WaitForChild("RenderedEggs", 10)

-- ESP Settings
local SelectedEggsSet = {} 
local ESPCache = {}        
local EggESP_Enabled = false 
local ESP_Color = Color3.fromRGB(255, 215, 0)
local ESP_Alpha = 0.4

-- Teleport Settings
local TeleportConfig = {
    Enabled      = false,
    YOffset      = 4,     -- ปรับความสูงลอยเหนือไข่ขึ้นเล็กน้อยเพื่อป้องกันตัวปักพื้น
    StepDistance = 15,    
    StepDelay    = 0.03,  
    SpawnName    = "Spawn",
    TargetEgg    = nil
}
local IsTeleporting = false

-- ==========================================
-- HELPER & EGG DETECTION FUNCTIONS
-- ==========================================

local function GetAllEggs()
    local Eggs = {}
    local Seen = {}

    if not RenderedEggs then
        warn("[ERROR] ไม่พบ RenderedEggs ใน Workspace")
        return Eggs
    end

    for _, Egg in pairs(RenderedEggs:GetChildren()) do
        if (Egg:IsA("BasePart") or Egg:IsA("Model")) and not Seen[Egg.Name] then
            Seen[Egg.Name] = true
            table.insert(Eggs, Egg.Name)
        end
    end

    return Eggs
end

local function GetObjectCFrame(object)
    if not object then return nil end
    if object:IsA("Model") then
        return object:GetPivot()
    elseif object:IsA("BasePart") then
        return object.CFrame
    else
        local part = object:FindFirstChildWhichIsA("BasePart", true)
        return part and part.CFrame or nil
    end
end

-- ==========================================
-- FIX: STEP TELEPORT SYSTEM (KEEP CHARACTER UPRIGHT)
-- ==========================================

local function SmoothTeleportTo(targetCFrame)
    if not targetCFrame or IsTeleporting then return end

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not hrp then return end

    IsTeleporting = true

    local startPosition  = hrp.Position
    local targetPosition = targetCFrame.Position + Vector3.new(0, TeleportConfig.YOffset, 0)

    -- คำนวณเฉพาะทิศทางแนวนอน (ไม่เอาเอียง/คว่ำหัว) เพื่อให้ตัวละครตั้งตรงตลอดเวลา
    local lookDir = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
    if lookDir.Magnitude == 0 then lookDir = Vector3.new(0, 0, -1) end
    local uprightRotation = CFrame.lookAt(Vector3.zero, lookDir)

    local distance = (targetPosition - startPosition).Magnitude
    local steps    = math.max(1, math.ceil(distance / TeleportConfig.StepDistance))

    for i = 1, steps do
        if not hrp.Parent then break end

        local alpha    = i / steps
        local position = startPosition:Lerp(targetPosition, alpha)
        
        -- วางตำแหน่งใหม่โดยบังคับให้ตัวละครยืนตรง
        hrp.CFrame = CFrame.new(position) * uprightRotation

        if i < steps then
            task.wait(TeleportConfig.StepDelay)
        end
    end

    -- ล้างแรงเหวี่ยงค้างและปลุกตัวละครให้ยืนขึ้นหากติดสถานะล้ม
    hrp.AssemblyLinearVelocity = Vector3.zero
    if humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end

    IsTeleporting = false
end

local function TeleportToTargetEgg()
    if not TeleportConfig.Enabled then return end
    if not TeleportConfig.TargetEgg or TeleportConfig.TargetEgg == "" then
        Window:Notify({ Title = "Teleport", Description = "กรุณาเลือกไข่เป้าหมายก่อน", Lifetime = 3 })
        return
    end

    if not RenderedEggs then return end
    local targetObj = RenderedEggs:FindFirstChild(TeleportConfig.TargetEgg)

    if targetObj then
        local eggCFrame = GetObjectCFrame(targetObj)
        if eggCFrame then
            SmoothTeleportTo(eggCFrame)
        end
    else
        Window:Notify({ Title = "Teleport", Description = "ไม่พบไข่ '" .. TeleportConfig.TargetEgg .. "' ในแมพ", Lifetime = 3 })
    end
end

local function TeleportToSpawn()
    if not TeleportConfig.Enabled then return end
    local spawnObj = Workspace:FindFirstChild(TeleportConfig.SpawnName)
    local spawnCFrame = GetObjectCFrame(spawnObj)

    if spawnCFrame then
        SmoothTeleportTo(spawnCFrame)
    else
        Window:Notify({ Title = "Teleport", Description = "ไม่พบจุด Spawn ใน Workspace", Lifetime = 3 })
    end
end

-- ==========================================
-- ESP SYSTEM
-- ==========================================

local function RemoveEggESP(egg)
    if ESPCache[egg] then
        if ESPCache[egg].Highlight then ESPCache[egg].Highlight:Destroy() end
        if ESPCache[egg].Billboard then ESPCache[egg].Billboard:Destroy() end
        if ESPCache[egg].Connection then ESPCache[egg].Connection:Disconnect() end
        ESPCache[egg] = nil
    end
end

local function CreateEggESP(egg)
    if ESPCache[egg] then return end

    local targetPart = egg:IsA("BasePart") and egg or (egg:IsA("Model") and (egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")))
    if not targetPart then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "EggESPHighlight"
    highlight.Adornee = egg
    highlight.FillColor = ESP_Color
    highlight.FillTransparency = ESP_Alpha
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = egg

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EggESPName"
    billboard.Adornee = targetPart
    billboard.Size = UDim2.new(0, 150, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    textLabel.TextStrokeTransparency = 0
    textLabel.TextSize = 13
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.Parent = billboard
    billboard.Parent = egg

    local connection = RunService.RenderStepped:Connect(function()
        if not egg or not egg.Parent then
            RemoveEggESP(egg)
            return
        end

        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local myHrp = LocalPlayer.Character.HumanoidRootPart
            local distance = math.floor((myHrp.Position - targetPart.Position).Magnitude)
            textLabel.Text = string.format("%s\n[%d m]", egg.Name, distance)
        end
    end)

    ESPCache[egg] = {
        Highlight = highlight,
        Billboard = billboard,
        Connection = connection
    }
end

local function UpdateEggESP(egg)
    if EggESP_Enabled and SelectedEggsSet[egg.Name] then
        CreateEggESP(egg)
    else
        RemoveEggESP(egg)
    end
end

local function RefreshAllEggESP()
    if not RenderedEggs then return end
    for _, egg in ipairs(RenderedEggs:GetChildren()) do
        UpdateEggESP(egg)
    end
end

if RenderedEggs then
    RenderedEggs.ChildAdded:Connect(function(egg)
        task.wait(0.1)
        UpdateEggESP(egg)
    end)

    RenderedEggs.ChildRemoved:Connect(function(egg)
        RemoveEggESP(egg)
    end)
end

-- ==========================================
-- MACLIB UI COMPONENTS
-- ==========================================

MainSection:Toggle({
    Name     = "Enable Egg ESP",
    Default  = false,
    Callback = function(Value)
        EggESP_Enabled = Value
        RefreshAllEggESP()
        Window:Notify({
            Title       = "Egg ESP",
            Description = (Value and "Enabled " or "Disabled ") .. "Egg ESP",
            Lifetime    = 3
        })
    end
}, "ToggleEggESP")

MainSection:Colorpicker({
    Name     = "ESP Color",
    Default  = Color3.fromRGB(255, 215, 0),
    Alpha    = 0.4,
    Callback = function(color, alpha)
        ESP_Color = color
        ESP_Alpha = alpha or 0.4

        for _, data in pairs(ESPCache) do
            if data.Highlight then
                data.Highlight.FillColor = ESP_Color
                data.Highlight.FillTransparency = ESP_Alpha
            end
        end
    end,
}, "ESPColorPicker")

local EggDropdown = MainSection:Dropdown({
    Name     = "Select Eggs (ESP Filter)",
    Search   = true,
    Multi    = true,
    Required = false,
    Options  = {"White Egg", "Brown Egg", "Cracked Egg", "Easter Egg", "Stone Egg", "Leaf Egg", "Mushroom Egg", "Flower Egg", "Slime Egg", "Ice Egg", "Glass Egg", "Golden Egg", "Crystal Egg", "Skull Egg", "Dominus Egg", "Flaming Egg", "Sinister Egg", "Soul Egg", "Aurora Egg", "Galaxy Egg", "Blackhole Egg", "Cherub Egg"},
    Default  = {},
    Callback = function(Value)
        if type(Value) ~= "table" then return end 

        table.clear(SelectedEggsSet)
        local SelectedNames = {}
        for Name, State in pairs(Value) do
            if State then
                SelectedEggsSet[Name] = true
                table.insert(SelectedNames, Name)
            end
        end

        RefreshAllEggESP()
    end,
}, "SelectEggsDropdown")

-- --- TELEPORT SECTION ---

TeleportSection:Toggle({
    Name     = "Enable Teleport",
    Default  = TeleportConfig.Disable,
    Callback = function(Value)
        TeleportConfig.Enabled = Value
    end
}, "ToggleTeleport")

TeleportSection:Dropdown({
    Name     = "Target Teleport Egg",
    Search   = true,
    Multi    = false,
    Required = false,
    Options  = {"White Egg", "Brown Egg", "Cracked Egg", "Easter Egg", "Stone Egg", "Leaf Egg", "Mushroom Egg", "Flower Egg", "Slime Egg", "Ice Egg", "Glass Egg", "Golden Egg", "Crystal Egg", "Skull Egg", "Dominus Egg", "Flaming Egg", "Sinister Egg", "Soul Egg", "Aurora Egg", "Galaxy Egg", "Blackhole Egg", "Cherub Egg"},
    Default  = "",
    Callback = function(Value)
        TeleportConfig.TargetEgg = Value
    end,
}, "TeleportTargetDropdown")

TeleportSection:Keybind({
    Name     = "Teleport To Egg KeyBind",
    Default  = Enum.KeyCode.T,
    Callback = function()
        TeleportToTargetEgg()
    end
}, "KeybindTpEgg")

TeleportSection:Keybind({
    Name     = "Teleport To Spawn KeyBind",
    Default  = Enum.KeyCode.R,
    Callback = function()
        TeleportToSpawn()
    end
}, "KeybindTpSpawn")

TeleportSection:Slider({
    Name     = "Speed (Studs)",
    Default  = 30,
    Min      = 5,
    Max      = 50,
    Minimum  = 5,
    Maximum  = 50,
    min      = 5,
    max      = 50,
    Rounding = 0,
    Float    = 1,
    Callback = function(Value)
        TeleportConfig.StepDistance = Value
    end
}, "SliderStepDist")

TeleportSection:Slider({
    Name     = "Teleport Delay (Sec)",
    Default  = 0.03,
    Min      = 0.01,
    Max      = 0.2,
    Minimum  = 0.01,
    Maximum  = 0.2,
    min      = 0.01,
    max      = 0.2,
    Rounding = 2,
    Float    = 0.01,
    Callback = function(Value)
        TeleportConfig.StepDelay = Value
    end
}, "SliderStepDelay")

TeleportSection:Slider({
    Name     = "Height Offset (Y)",
    Default  = 6,
    Min      = 0,
    Max      = 15,
    Minimum  = 0,
    Maximum  = 15,
    min      = 0,
    max      = 15,
    Rounding = 0,
    Float    = 1,
    Callback = function(Value)
        TeleportConfig.YOffset = Value
    end
}, "SliderYOffset")