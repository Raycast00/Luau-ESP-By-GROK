-- ESP Library by Grok (простая и расширяемая)
local ESP = {}
ESP.__index = ESP

local Drawing = Drawing
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer

ESP.Enabled = false
ESP.Objects = {}        -- все ESP объекты
ESP.Connections = {}

local function createDrawing(class)
    local obj = Drawing.new(class)
    obj.Visible = false
    return obj
end

-- Основной класс для одного ESP объекта
local ESPObject = {}
ESPObject.__index = ESPObject

function ESPObject.new(obj)
    local self = setmetatable({}, ESPObject)
    
    self.Object = obj                    -- Part / Model / Player
    self.Drawings = {}                   -- все Drawing объекты
    self.GlowDrawings = {}               -- для glow эффекта
    self.HologramEnabled = false
    self.GlowEnabled = false
    self.BlackOutline = true
    
    -- Настройки
    self.Settings = {
        Enabled = true,
        Box = false,
        BoxColor = Color3.fromRGB(255, 255, 255),
        BoxThickness = 2,
        Name = false,
        NameColor = Color3.fromRGB(255, 255, 255),
        Distance = false,
        DistanceColor = Color3.fromRGB(255, 255, 255),
        HealthBar = false,
        HealthBarGradient = true,
        HealthText = false,
        Tracer = false,
        TracerColor = Color3.fromRGB(255, 0, 0),
        Skeleton = false,
        SkeletonColor = Color3.fromRGB(255, 255, 255),
        Tool = false,
        ToolColor = Color3.fromRGB(0, 255, 0),
        Chams = false,           -- используем Highlight
    }
    
    self:CreateDrawings()
    table.insert(ESP.Objects, self)
    return self
end

function ESPObject:CreateDrawings()
    -- Box
    self.Drawings.Box = createDrawing("Square")
    self.Drawings.Box.Thickness = 2
    self.Drawings.Box.Filled = false
    
    -- Outline для бокса
    self.Drawings.BoxOutline = createDrawing("Square")
    self.Drawings.BoxOutline.Thickness = 4
    self.Drawings.BoxOutline.Color = Color3.new(0,0,0)
    self.Drawings.BoxOutline.Filled = false
    
    -- Name
    self.Drawings.Name = createDrawing("Text")
    self.Drawings.Name.Size = 13
    self.Drawings.Name.Center = true
    self.Drawings.Name.Outline = true
    
    -- Distance
    self.Drawings.Distance = createDrawing("Text")
    self.Drawings.Distance.Size = 12
    self.Drawings.Distance.Center = true
    self.Drawings.Distance.Outline = true
    
    -- Health Bar
    self.Drawings.HealthBarBG = createDrawing("Square")
    self.Drawings.HealthBar = createDrawing("Square")
    
    -- Health Text
    self.Drawings.HealthText = createDrawing("Text")
    self.Drawings.HealthText.Size = 12
    self.Drawings.HealthText.Center = true
    self.Drawings.HealthText.Outline = true
    
    -- Tracer
    self.Drawings.Tracer = createDrawing("Line")
    self.Drawings.Tracer.Thickness = 1.5
    
    -- Skeleton (пока упрощённо)
    self.Drawings.Skeleton = {}
    for i = 1, 10 do
        self.Drawings.Skeleton[i] = createDrawing("Line")
    end
end

function ESPObject:Update()
    if not self.Settings.Enabled or not self.Object then 
        self:Hide()
        return 
    end

    local rootPart = self.Object:FindFirstChild("HumanoidRootPart") or self.Object:FindFirstChildWhichIsA("BasePart")
    if not rootPart then self:Hide() return end

    local hum = self.Object:FindFirstChild("Humanoid")
    local health = hum and hum.Health or 100
    local maxHealth = hum and hum.MaxHealth or 100
    local healthRatio = math.clamp(health / maxHealth, 0, 1)

    local pos, onScreen = Camera:WorldToViewportPoint(rootPart.Position)
    if not onScreen then self:Hide() return end

    local size = (Camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 3, 0)).Y - 
                  Camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, -3, 0)).Y) / 2

    local x = pos.X
    local y = pos.Y - size / 2
    local w = size * 1.8
    local h = size * 2

    -- Box + Outline
    if self.Settings.Box then
        self.Drawings.Box.Visible = true
        self.Drawings.Box.Position = Vector2.new(x - w/2, y)
        self.Drawings.Box.Size = Vector2.new(w, h)
        self.Drawings.Box.Color = self.Settings.BoxColor
        self.Drawings.Box.Thickness = self.Settings.BoxThickness

        if self.BlackOutline then
            self.Drawings.BoxOutline.Visible = true
            self.Drawings.BoxOutline.Position = Vector2.new(x - w/2 - 2, y - 2)
            self.Drawings.BoxOutline.Size = Vector2.new(w + 4, h + 4)
        end
    else
        self.Drawings.Box.Visible = false
        self.Drawings.BoxOutline.Visible = false
    end

    -- Name
    if self.Settings.Name then
        self.Drawings.Name.Visible = true
        self.Drawings.Name.Text = self.Object.Name or "Object"
        self.Drawings.Name.Position = Vector2.new(x, y - 18)
        self.Drawings.Name.Color = self.Settings.NameColor
    else
        self.Drawings.Name.Visible = false
    end

    -- Distance
    if self.Settings.Distance then
        local dist = math.floor((LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and 
                      (rootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude) or 0)
        self.Drawings.Distance.Visible = true
        self.Drawings.Distance.Text = dist .. "m"
        self.Drawings.Distance.Position = Vector2.new(x, y + h + 5)
        self.Drawings.Distance.Color = self.Settings.DistanceColor
    else
        self.Drawings.Distance.Visible = false
    end

    -- Health Bar
    if self.Settings.HealthBar then
        local barWidth = 4
        local barHeight = h

        self.Drawings.HealthBarBG.Visible = true
        self.Drawings.HealthBarBG.Position = Vector2.new(x - w/2 - 8, y)
        self.Drawings.HealthBarBG.Size = Vector2.new(barWidth, barHeight)
        self.Drawings.HealthBarBG.Color = Color3.new(0,0,0)

        self.Drawings.HealthBar.Visible = true
        self.Drawings.HealthBar.Position = Vector2.new(x - w/2 - 8, y + barHeight * (1 - healthRatio))
        self.Drawings.HealthBar.Size = Vector2.new(barWidth, barHeight * healthRatio)
        
        if self.Settings.HealthBarGradient then
            self.Drawings.HealthBar.Color = Color3.fromHSV(healthRatio * 0.3, 1, 1)  -- зелёный → красный
        else
            self.Drawings.HealthBar.Color = Color3.fromRGB(0, 255, 0)
        end
    else
        self.Drawings.HealthBarBG.Visible = false
        self.Drawings.HealthBar.Visible = false
    end

    -- Health Text
    if self.Settings.HealthText then
        self.Drawings.HealthText.Visible = true
        self.Drawings.HealthText.Text = math.floor(health) .. "/" .. math.floor(maxHealth)
        self.Drawings.HealthText.Position = Vector2.new(x - w/2 - 20, y + h/2)
        self.Drawings.HealthText.Color = Color3.fromHSV(healthRatio * 0.3, 1, 1)
    else
        self.Drawings.HealthText.Visible = false
    end

    -- Tracer
    if self.Settings.Tracer then
        self.Drawings.Tracer.Visible = true
        self.Drawings.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        self.Drawings.Tracer.To = Vector2.new(x, y + h)
        self.Drawings.Tracer.Color = self.Settings.TracerColor
    else
        self.Drawings.Tracer.Visible = false
    end
end

function ESPObject:Hide()
    for _, drawing in pairs(self.Drawings) do
        if typeof(drawing) == "table" then
            for _, line in pairs(drawing) do line.Visible = false end
        else
            drawing.Visible = false
        end
    end
end

function ESPObject:Destroy()
    for _, drawing in pairs(self.Drawings) do
        if typeof(drawing) == "table" then
            for _, v in pairs(drawing) do v:Remove() end
        else
            drawing:Remove()
        end
    end
end

-- ===================== ГЛОБАЛЬНЫЕ ФУНКЦИИ =====================

function ESP:Add(object)
    if not object then return nil end
    return ESPObject.new(object)
end

function ESP:Remove(object)
    for i, espObj in ipairs(ESP.Objects) do
        if espObj.Object == object then
            espObj:Destroy()
            table.remove(ESP.Objects, i)
            break
        end
    end
end

function ESP:Enable()
    if ESP.Enabled then return end
    ESP.Enabled = true

    ESP.Connections.Update = RunService.RenderStepped:Connect(function()
        for _, obj in ipairs(ESP.Objects) do
            obj:Update()
        end
    end)
end

function ESP:Disable()
    ESP.Enabled = false
    if ESP.Connections.Update then
        ESP.Connections.Update:Disconnect()
        ESP.Connections.Update = nil
    end
    for _, obj in ipairs(ESP.Objects) do
        obj:Hide()
    end
end

-- Для кастомных объектов (например, дропы, NPC и т.д.)
function ESP:AddCustom(partOrModel, settings)
    local obj = ESP:Add(partOrModel)
    if settings then
        for k, v in pairs(settings) do
            if obj.Settings[k] ~= nil then
                obj.Settings[k] = v
            end
        end
    end
    return obj
end

return ESP
