--[[
    ESP Library
    Supports: 2D/3D Box, Name, Distance, Tracer, Skeleton, Chams, Health Bar, Health Text
    Features: Glow, Hologram, Outline, Custom Colors, Gradients
    Usage:
        local ESP = loadstring(...)() or require(...)
        
        local obj = ESP:Add(player_or_part, {
            -- options here
        })
        obj:Remove()
        ESP:Load()
        ESP:Unload()
]]

local ESP = {}
ESP.__index = ESP

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera

-- Local player
local lp = Players.LocalPlayer

-- Internal storage
local objects = {}
local connections = {}

-- Utility
local function new_drawing(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props or {}) do
        d[k] = v
    end
    return d
end

local function resolve_color(flag_value, fallback)
    if type(flag_value) == "table" and flag_value.Color then
        return flag_value.Color
    elseif typeof(flag_value) == "Color3" then
        return flag_value
    end
    return fallback or Color3.new(1, 1, 1)
end

local function world_to_viewport(pos)
    local screen, on_screen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screen.X, screen.Y), screen.Z, on_screen
end

local function get_bounding_box(character)
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    local on_screen = false
    local avg_depth = 0
    local count = 0

    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local size = part.Size
            local cf = part.CFrame

            local corners = {
                cf * CFrame.new( size.X/2,  size.Y/2,  size.Z/2),
                cf * CFrame.new(-size.X/2,  size.Y/2,  size.Z/2),
                cf * CFrame.new( size.X/2, -size.Y/2,  size.Z/2),
                cf * CFrame.new(-size.X/2, -size.Y/2,  size.Z/2),
                cf * CFrame.new( size.X/2,  size.Y/2, -size.Z/2),
                cf * CFrame.new(-size.X/2,  size.Y/2, -size.Z/2),
                cf * CFrame.new( size.X/2, -size.Y/2, -size.Z/2),
                cf * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
            }

            for _, corner in pairs(corners) do
                local screen, depth, visible = world_to_viewport(corner.Position)
                if visible and depth > 0 then
                    on_screen = true
                    min_x = math.min(min_x, screen.X)
                    min_y = math.min(min_y, screen.Y)
                    max_x = math.max(max_x, screen.X)
                    max_y = math.max(max_y, screen.Y)
                    avg_depth = avg_depth + depth
                    count = count + 1
                end
            end
        end
    end

    if count > 0 then
        avg_depth = avg_depth / count
    end

    return on_screen, min_x, min_y, max_x, max_y, avg_depth
end

-- Skeleton bones
local BONES_R6 = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}

local BONES_R15 = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
}

-- ESP Object class
local ESPObject = {}
ESPObject.__index = ESPObject

function ESPObject.new(target, options)
    local self = setmetatable({}, ESPObject)

    self.target = target
    self.options = options or {}
    self.drawings = {}
    self.glow_gui = nil
    self.glow_instances = {}
    self.enabled = true
    self.hologram_tick = 0

    self:_init_drawings()

    return self
end

function ESPObject:_init_drawings()
    local o = self.options

    -- 2D Box
    if o.box_2d then
        -- outline
        self.drawings.box_2d_outline = new_drawing("Square", {
            Visible = false, Filled = false,
            Color = Color3.fromRGB(0, 0, 0),
            Thickness = (o.box_thickness or 1) + 2,
            ZIndex = 1,
        })
        -- main
        self.drawings.box_2d = new_drawing("Square", {
            Visible = false, Filled = false,
            Color = o.box_color or Color3.new(1, 1, 1),
            Thickness = o.box_thickness or 1,
            ZIndex = 2,
        })
    end

    -- 3D Box (8 corners, 12 edges)
    if o.box_3d then
        self.drawings.box_3d_lines = {}
        self.drawings.box_3d_outlines = {}
        for i = 1, 12 do
            self.drawings.box_3d_outlines[i] = new_drawing("Line", {
                Visible = false,
                Color = Color3.fromRGB(0, 0, 0),
                Thickness = (o.box_thickness or 1) + 2,
                ZIndex = 1,
            })
            self.drawings.box_3d_lines[i] = new_drawing("Line", {
                Visible = false,
                Color = o.box_color or Color3.new(1, 1, 1),
                Thickness = o.box_thickness or 1,
                ZIndex = 2,
            })
        end
    end

    -- Name
    if o.name then
        self.drawings.name_outline = new_drawing("Text", {
            Visible = false, Center = true,
            Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0),
            Size = o.text_size or 13,
            Font = o.text_font or Drawing.Fonts.System,
            Color = Color3.fromRGB(0, 0, 0),
            ZIndex = 1,
        })
        self.drawings.name = new_drawing("Text", {
            Visible = false, Center = true,
            Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0),
            Size = o.text_size or 13,
            Font = o.text_font or Drawing.Fonts.System,
            Color = o.name_color or Color3.new(1, 1, 1),
            ZIndex = 2,
        })
    end

    -- Distance
    if o.distance then
        self.drawings.distance = new_drawing("Text", {
            Visible = false, Center = true,
            Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0),
            Size = o.text_size or 13,
            Font = o.text_font or Drawing.Fonts.System,
            Color = o.distance_color or Color3.new(1, 1, 1),
            ZIndex = 2,
        })
    end

    -- Tracer
    if o.tracer then
        self.drawings.tracer_outline = new_drawing("Line", {
            Visible = false,
            Color = Color3.fromRGB(0, 0, 0),
            Thickness = (o.tracer_thickness or 1) + 2,
            ZIndex = 1,
        })
        self.drawings.tracer = new_drawing("Line", {
            Visible = false,
            Color = o.tracer_color or Color3.new(1, 1, 1),
            Thickness = o.tracer_thickness or 1,
            ZIndex = 2,
        })
    end

    -- Skeleton
    if o.skeleton then
        self.drawings.skeleton_lines = {}
        self.drawings.skeleton_outlines = {}
        -- max 15 bones
        for i = 1, 15 do
            self.drawings.skeleton_outlines[i] = new_drawing("Line", {
                Visible = false,
                Color = Color3.fromRGB(0, 0, 0),
                Thickness = (o.skeleton_thickness or 1) + 2,
                ZIndex = 1,
            })
            self.drawings.skeleton_lines[i] = new_drawing("Line", {
                Visible = false,
                Color = o.skeleton_color or Color3.new(1, 1, 1),
                Thickness = o.skeleton_thickness or 1,
                ZIndex = 2,
            })
        end
    end

    -- Health Bar
    if o.health_bar then
        -- background
        self.drawings.health_bg = new_drawing("Square", {
            Visible = false, Filled = true,
            Color = Color3.fromRGB(0, 0, 0),
            ZIndex = 1,
        })
        -- fill
        self.drawings.health_fill = new_drawing("Square", {
            Visible = false, Filled = true,
            Color = o.health_color_high or Color3.fromRGB(0, 255, 0),
            ZIndex = 2,
        })
        -- outline
        self.drawings.health_outline = new_drawing("Square", {
            Visible = false, Filled = false,
            Color = Color3.fromRGB(0, 0, 0),
            Thickness = 1,
            ZIndex = 3,
        })
    end

    -- Health Text
    if o.health_text then
        self.drawings.health_text = new_drawing("Text", {
            Visible = false, Center = true,
            Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0),
            Size = o.text_size or 13,
            Font = o.text_font or Drawing.Fonts.System,
            Color = o.health_text_color or Color3.new(1, 1, 1),
            ZIndex = 2,
        })
    end

    -- Tool ESP
    if o.tool then
        self.drawings.tool_text = new_drawing("Text", {
            Visible = false, Center = true,
            Outline = true, OutlineColor = Color3.fromRGB(0, 0, 0),
            Size = o.text_size or 13,
            Font = o.text_font or Drawing.Fonts.System,
            Color = o.tool_color or Color3.new(1, 1, 1),
            ZIndex = 2,
        })
    end

    -- Chams (highlight via SelectionBox)
    if o.chams then
        local sg = Instance.new("SelectionBox")
        sg.Color3 = o.chams_color or Color3.new(1, 0, 0)
        sg.LineThickness = o.chams_thickness or 0.05
        sg.SurfaceTransparency = o.chams_transparency or 0.5
        sg.SurfaceColor3 = o.chams_color or Color3.new(1, 0, 0)
        sg.Parent = Camera
        self.drawings.chams = sg
    end

    -- Glow (ScreenGui ImageLabel)
    if o.glow then
        local gui = Instance.new("ScreenGui")
        gui.Parent = game:GetService("CoreGui")
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local img = Instance.new("ImageLabel")
        img.Parent = gui
        img.BackgroundTransparency = 1
        img.Image = "rbxassetid://18245826428"
        img.ScaleType = Enum.ScaleType.Slice
        img.SliceCenter = Rect.new(Vector2.new(21, 21), Vector2.new(79, 79))
        img.ImageTransparency = o.glow_transparency or 0.5
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.Visible = false

        self.glow_gui = gui
        self.glow_img = img
    end
end

function ESPObject:_get_character()
    local target = self.target
    -- если target это Player
    if typeof(target) == "Instance" and target:IsA("Player") then
        return target.Character
    end
    -- если target это модель/часть
    if typeof(target) == "Instance" and target:IsA("Model") then
        return target
    end
    return nil
end

function ESPObject:_get_humanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

function ESPObject:_get_root(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function ESPObject:_hide_all()
    for _, d in pairs(self.drawings) do
        if typeof(d) == "Instance" then
            if d:IsA("SelectionBox") then
                d.Adornee = nil
            end
        elseif type(d) == "table" then
            for _, line in pairs(d) do
                if line and line.Visible ~= nil then
                    line.Visible = false
                end
            end
        else
            if d and d.Visible ~= nil then
                d.Visible = false
            end
        end
    end
    if self.glow_img then
        self.glow_img.Visible = false
    end
end

function ESPObject:_lerp_color(c1, c2, t)
    return c1:Lerp(c2, t)
end

function ESPObject:Update()
    if not self.enabled then
        self:_hide_all()
        return
    end

    local o = self.options
    local char = self:_get_character()

    if not char then
        self:_hide_all()
        return
    end

    local root = self:_get_root(char)
    if not root then
        self:_hide_all()
        return
    end

    local humanoid = self:_get_humanoid(char)
    local root_pos = root.Position
    local screen_pos, depth, on_screen = world_to_viewport(root_pos)

    if not on_screen or depth <= 0 then
        self:_hide_all()
        return
    end

    -- distance
    local lp_char = lp.Character
    local lp_root = lp_char and lp_char:FindFirstChild("HumanoidRootPart")
    local dist = lp_root and math.floor((root_pos - lp_root.Position).Magnitude) or 0

    -- hologram effect
    local hologram_color = nil
    if o.hologram then
        self.hologram_tick = self.hologram_tick + 0.05
        local t = (math.sin(self.hologram_tick * 2) + 1) / 2
        local c1 = resolve_color(o.hologram_color1, Color3.fromRGB(0, 255, 255))
        local c2 = resolve_color(o.hologram_color2, Color3.fromRGB(255, 0, 255))
        hologram_color = c1:Lerp(c2, t)
    end

    -- resolve colors
    local box_color = hologram_color or resolve_color(o.box_color, Color3.new(1, 1, 1))
    local name_color = hologram_color or resolve_color(o.name_color, Color3.new(1, 1, 1))
    local dist_color = hologram_color or resolve_color(o.distance_color, Color3.new(1, 1, 1))
    local tracer_color = hologram_color or resolve_color(o.tracer_color, Color3.new(1, 1, 1))
    local skeleton_color = hologram_color or resolve_color(o.skeleton_color, Color3.new(1, 1, 1))

    -- bounding box
    local on_bb, min_x, min_y, max_x, max_y = get_bounding_box(char)
    local bb_x = min_x
    local bb_y = min_y
    local bb_w = max_x - min_x
    local bb_h = max_y - min_y

    -- 2D Box
    if o.box_2d and on_bb then
        local pad = 2
        self.drawings.box_2d_outline.Position = Vector2.new(bb_x - pad, bb_y - pad)
        self.drawings.box_2d_outline.Size = Vector2.new(bb_w + pad*2, bb_h + pad*2)
        self.drawings.box_2d_outline.Visible = true
        self.drawings.box_2d_outline.Thickness = (o.box_thickness or 1) + 2

        self.drawings.box_2d.Position = Vector2.new(bb_x, bb_y)
        self.drawings.box_2d.Size = Vector2.new(bb_w, bb_h)
        self.drawings.box_2d.Color = box_color
        self.drawings.box_2d.Thickness = o.box_thickness or 1
        self.drawings.box_2d.Visible = true
    elseif o.box_2d then
        self.drawings.box_2d_outline.Visible = false
        self.drawings.box_2d.Visible = false
    end

    -- 3D Box
    if o.box_3d then
        local head = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso")
        local torso = char:FindFirstChild("HumanoidRootPart")

        if head and torso then
            local size = torso.Size
            local cf = torso.CFrame
            local half = Vector3.new(size.X / 2 + 0.2, (head.Position.Y - torso.Position.Y + head.Size.Y / 2 + size.Y / 2) / 2 + 0.1, size.Z / 2 + 0.2)
            local center_cf = CFrame.new(torso.Position + Vector3.new(0, half.Y - size.Y/2, 0))

            local corners_3d = {
                center_cf * CFrame.new( half.X,  half.Y,  half.Z),
                center_cf * CFrame.new(-half.X,  half.Y,  half.Z),
                center_cf * CFrame.new( half.X, -half.Y,  half.Z),
                center_cf * CFrame.new(-half.X, -half.Y,  half.Z),
                center_cf * CFrame.new( half.X,  half.Y, -half.Z),
                center_cf * CFrame.new(-half.X,  half.Y, -half.Z),
                center_cf * CFrame.new( half.X, -half.Y, -half.Z),
                center_cf * CFrame.new(-half.X, -half.Y, -half.Z),
            }

            local edges = {
                {1,2},{3,4},{5,6},{7,8}, -- horizontal
                {1,3},{2,4},{5,7},{6,8}, -- vertical
                {1,5},{2,6},{3,7},{4,8}, -- depth
            }

            local all_on_screen = true
            local screen_corners = {}
            for i, cf_corner in pairs(corners_3d) do
                local s, d, vis = world_to_viewport(cf_corner.Position)
                screen_corners[i] = s
                if not vis or d <= 0 then all_on_screen = false end
            end

            for i, edge in pairs(edges) do
                local a = screen_corners[edge[1]]
                local b = screen_corners[edge[2]]

                self.drawings.box_3d_outlines[i].From = a
                self.drawings.box_3d_outlines[i].To = b
                self.drawings.box_3d_outlines[i].Thickness = (o.box_thickness or 1) + 2
                self.drawings.box_3d_outlines[i].Visible = all_on_screen

                self.drawings.box_3d_lines[i].From = a
                self.drawings.box_3d_lines[i].To = b
                self.drawings.box_3d_lines[i].Color = box_color
                self.drawings.box_3d_lines[i].Thickness = o.box_thickness or 1
                self.drawings.box_3d_lines[i].Visible = all_on_screen
            end
        end
    end

    -- Name
    if o.name then
        local display = o.name_text
        if not display then
            local player = Players:GetPlayerFromCharacter(char)
            display = player and player.DisplayName or char.Name
        end

        local pos = Vector2.new(screen_pos.X, bb_y - 16)

        self.drawings.name.Text = display
        self.drawings.name.Position = pos
        self.drawings.name.Color = name_color
        self.drawings.name.Size = o.text_size or 13
        self.drawings.name.Font = o.text_font or Drawing.Fonts.System
        self.drawings.name.Visible = true
    elseif self.drawings.name then
        self.drawings.name.Visible = false
    end

    -- Distance
    if o.distance then
        local pos = Vector2.new(screen_pos.X, bb_y + bb_h + 2)

        self.drawings.distance.Text = dist .. "m"
        self.drawings.distance.Position = pos
        self.drawings.distance.Color = dist_color
        self.drawings.distance.Size = o.text_size or 13
        self.drawings.distance.Font = o.text_font or Drawing.Fonts.System
        self.drawings.distance.Visible = on_bb
    elseif self.drawings.distance then
        self.drawings.distance.Visible = false
    end

    -- Tracer
    if o.tracer then
        local viewport = Camera.ViewportSize
        local origin_map = {
            bottom = Vector2.new(viewport.X / 2, viewport.Y),
            top = Vector2.new(viewport.X / 2, 0),
            center = Vector2.new(viewport.X / 2, viewport.Y / 2),
        }
        local origin = origin_map[o.tracer_origin or "bottom"]

        self.drawings.tracer_outline.From = origin
        self.drawings.tracer_outline.To = screen_pos
        self.drawings.tracer_outline.Thickness = (o.tracer_thickness or 1) + 2
        self.drawings.tracer_outline.Visible = true

        self.drawings.tracer.From = origin
        self.drawings.tracer.To = screen_pos
        self.drawings.tracer.Color = tracer_color
        self.drawings.tracer.Thickness = o.tracer_thickness or 1
        self.drawings.tracer.Visible = true
    elseif self.drawings.tracer then
        self.drawings.tracer_outline.Visible = false
        self.drawings.tracer.Visible = false
    end

    -- Skeleton
    if o.skeleton then
        local is_r15 = char:FindFirstChild("UpperTorso") ~= nil
        local bones = is_r15 and BONES_R15 or BONES_R6
        local thickness = o.skeleton_thickness or 1

        for i, bone in pairs(bones) do
            local part_a = char:FindFirstChild(bone[1])
            local part_b = char:FindFirstChild(bone[2])

            if part_a and part_b then
                local sa, da, va = world_to_viewport(part_a.Position)
                local sb, db, vb = world_to_viewport(part_b.Position)

                if va and vb and da > 0 and db > 0 then
                    if self.drawings.skeleton_outlines[i] then
                        self.drawings.skeleton_outlines[i].From = sa
                        self.drawings.skeleton_outlines[i].To = sb
                        self.drawings.skeleton_outlines[i].Thickness = thickness + 2
                        self.drawings.skeleton_outlines[i].Visible = true
                    end
                    if self.drawings.skeleton_lines[i] then
                        self.drawings.skeleton_lines[i].From = sa
                        self.drawings.skeleton_lines[i].To = sb
                        self.drawings.skeleton_lines[i].Color = skeleton_color
                        self.drawings.skeleton_lines[i].Thickness = thickness
                        self.drawings.skeleton_lines[i].Visible = true
                    end
                else
                    if self.drawings.skeleton_outlines[i] then self.drawings.skeleton_outlines[i].Visible = false end
                    if self.drawings.skeleton_lines[i] then self.drawings.skeleton_lines[i].Visible = false end
                end
            else
                if self.drawings.skeleton_outlines[i] then self.drawings.skeleton_outlines[i].Visible = false end
                if self.drawings.skeleton_lines[i] then self.drawings.skeleton_lines[i].Visible = false end
            end
        end
    end

    -- Health Bar
    if o.health_bar and humanoid then
        local hp = humanoid.Health
        local max_hp = humanoid.MaxHealth
        local pct = max_hp > 0 and math.clamp(hp / max_hp, 0, 1) or 0

        local bar_w = 4
        local bar_x = bb_x - bar_w - 3
        local bar_y = bb_y
        local bar_h = bb_h

        -- gradient color
        local low = resolve_color(o.health_color_low, Color3.fromRGB(255, 0, 0))
        local high = resolve_color(o.health_color_high, Color3.fromRGB(0, 255, 0))
        local health_color = low:Lerp(high, pct)

        self.drawings.health_bg.Position = Vector2.new(bar_x, bar_y)
        self.drawings.health_bg.Size = Vector2.new(bar_w, bar_h)
        self.drawings.health_bg.Color = Color3.fromRGB(0, 0, 0)
        self.drawings.health_bg.Visible = on_bb

        self.drawings.health_fill.Position = Vector2.new(bar_x + 1, bar_y + bar_h * (1 - pct))
        self.drawings.health_fill.Size = Vector2.new(bar_w - 2, bar_h * pct - 1)
        self.drawings.health_fill.Color = health_color
        self.drawings.health_fill.Visible = on_bb

        self.drawings.health_outline.Position = Vector2.new(bar_x - 1, bar_y - 1)
        self.drawings.health_outline.Size = Vector2.new(bar_w + 2, bar_h + 2)
        self.drawings.health_outline.Visible = on_bb
    elseif o.health_bar then
        if self.drawings.health_bg then self.drawings.health_bg.Visible = false end
        if self.drawings.health_fill then self.drawings.health_fill.Visible = false end
        if self.drawings.health_outline then self.drawings.health_outline.Visible = false end
    end

    -- Health Text
    if o.health_text and humanoid then
        local hp = math.floor(humanoid.Health)
        local pos = Vector2.new(bb_x - 10, bb_y + bb_h / 2)

        local ht_color = hologram_color or resolve_color(o.health_text_color, Color3.new(1, 1, 1))

        self.drawings.health_text.Text = tostring(hp)
        self.drawings.health_text.Position = pos
        self.drawings.health_text.Color = ht_color
        self.drawings.health_text.Size = o.text_size or 13
        self.drawings.health_text.Font = o.text_font or Drawing.Fonts.System
        self.drawings.health_text.Visible = on_bb
    elseif o.health_text then
        if self.drawings.health_text then self.drawings.health_text.Visible = false end
    end

    -- Tool ESP
    if o.tool then
        local player = Players:GetPlayerFromCharacter(char)
        local tool_name = ""
        if player then
            local tool = char:FindFirstChildOfClass("Tool")
            tool_name = tool and tool.Name or "None"
        end

        local pos = Vector2.new(screen_pos.X, bb_y + bb_h + 14)
        local tc = hologram_color or resolve_color(o.tool_color, Color3.new(1, 1, 1))

        self.drawings.tool_text.Text = tool_name
        self.drawings.tool_text.Position = pos
        self.drawings.tool_text.Color = tc
        self.drawings.tool_text.Size = o.text_size or 13
        self.drawings.tool_text.Font = o.text_font or Drawing.Fonts.System
        self.drawings.tool_text.Visible = on_bb and tool_name ~= ""
    elseif self.drawings.tool_text then
        self.drawings.tool_text.Visible = false
    end

    -- Chams
    if o.chams and self.drawings.chams then
        self.drawings.chams.Adornee = char
        local chams_color = hologram_color or resolve_color(o.chams_color, Color3.new(1, 0, 0))
        self.drawings.chams.Color3 = chams_color
        self.drawings.chams.SurfaceColor3 = chams_color
    end

    -- Glow
    if o.glow and self.glow_img and on_bb then
        local gc = hologram_color or resolve_color(o.glow_color, box_color)
        self.glow_img.ImageColor3 = gc
        self.glow_img.ImageTransparency = o.glow_transparency or 0.5
        self.glow_img.Size = UDim2.new(0, bb_w + 60, 0, bb_h + 60)
        self.glow_img.Position = UDim2.new(0, bb_x + bb_w/2, 0, bb_y + bb_h/2)
        self.glow_img.Visible = true
    elseif self.glow_img then
        self.glow_img.Visible = false
    end
end

function ESPObject:SetOption(key, value)
    self.options[key] = value
end

function ESPObject:SetEnabled(bool)
    self.enabled = bool
    if not bool then
        self:_hide_all()
    end
end

function ESPObject:Remove()
    self:_hide_all()

    for _, d in pairs(self.drawings) do
        if typeof(d) == "Instance" then
            d:Destroy()
        elseif type(d) == "table" then
            for _, line in pairs(d) do
                if line and line.Remove then
                    pcall(function() line:Remove() end)
                end
            end
        else
            if d and d.Remove then
                pcall(function() d:Remove() end)
            end
        end
    end

    if self.glow_gui then
        self.glow_gui:Destroy()
    end

    self.drawings = {}
    self.enabled = false
end

-- Main ESP module
function ESP:Add(target, options)
    local obj = ESPObject.new(target, options)
    table.insert(objects, obj)
    return obj
end

function ESP:Remove(obj)
    obj:Remove()
    for i, v in pairs(objects) do
        if v == obj then
            table.remove(objects, i)
            break
        end
    end
end

function ESP:Load()
    local conn = RunService.RenderStepped:Connect(function()
        Camera = workspace.CurrentCamera
        for _, obj in pairs(objects) do
            pcall(function()
                obj:Update()
            end)
        end
    end)
    table.insert(connections, conn)
end

function ESP:Unload()
    for _, conn in pairs(connections) do
        conn:Disconnect()
    end
    connections = {}

    for _, obj in pairs(objects) do
        obj:Remove()
    end
    objects = {}
end

return ESP

--[[
========================================
USAGE EXAMPLE:
========================================

local ESP = loadstring(...)()  -- или require

ESP:Load()

-- Добавить ESP на игрока
local obj = ESP:Add(player, {
    -- 2D Box
    box_2d = true,
    box_color = Color3.new(1, 0, 0),
    box_thickness = 1,

    -- 3D Box
    box_3d = false,

    -- Name
    name = true,
    name_color = Color3.new(1, 1, 1),

    -- Distance
    distance = true,
    distance_color = Color3.new(1, 1, 1),

    -- Tracer
    tracer = true,
    tracer_color = Color3.new(1, 1, 1),
    tracer_origin = "bottom", -- "bottom", "top", "center"
    tracer_thickness = 1,

    -- Skeleton
    skeleton = true,
    skeleton_color = Color3.new(1, 1, 1),
    skeleton_thickness = 1,

    -- Health Bar (градиент от low до high)
    health_bar = true,
    health_color_low = Color3.fromRGB(255, 0, 0),
    health_color_high = Color3.fromRGB(0, 255, 0),

    -- Health Text
    health_text = true,
    health_text_color = Color3.new(1, 1, 1),

    -- Tool ESP
    tool = true,
    tool_color = Color3.new(1, 1, 1),

    -- Chams
    chams = true,
    chams_color = Color3.new(1, 0, 0),
    chams_transparency = 0.5,
    chams_thickness = 0.05,

    -- Glow
    glow = true,
    glow_color = Color3.new(1, 0, 0),
    glow_transparency = 0.5,

    -- Hologram (переливание цветов)
    hologram = true,
    hologram_color1 = Color3.fromRGB(0, 255, 255),
    hologram_color2 = Color3.fromRGB(255, 0, 255),

    -- Text settings
    text_size = 13,
    text_font = Drawing.Fonts.System,
})

-- Обновить опцию на лету
obj:SetOption("box_color", Color3.new(0, 1, 0))

-- С colorpicker из UI либки
obj:SetOption("box_color", flags["enemy_box_color"])
-- или прямо в RenderStepped colorpicker разрешится через resolve_color внутри либки

-- Включить/выключить
obj:SetEnabled(false)

-- Удалить
obj:Remove()
ESP:Remove(obj)

-- Добавить на кастомный объект (не игрок)
local custom = ESP:Add(workspace.SomeModel, {
    box_2d = true,
    name = true,
    name_text = "Chest",  -- кастомное имя
    distance = true,
    glow = true,
})

-- Выгрузить всё
ESP:Unload()

========================================
TOGGLE EXAMPLE:
========================================

local enemy_esp = {}

local function update_esp()
    for player, obj in pairs(enemy_esp) do
        obj:SetOption("box_2d", flags["enemy_box"])
        obj:SetOption("box_color", flags["enemy_box_color"])
        obj:SetOption("name", flags["enemy_name"])
        obj:SetOption("glow", flags["enemy_glow"])
        obj:SetOption("hologram", flags["enemy_hologram"])
    end
end

section:toggle({
    name = "Enemy ESP",
    flag = "enemy_esp",
    default = false,
    callback = function(bool)
        if bool then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= lp then
                    enemy_esp[player] = ESP:Add(player, {
                        box_2d = flags["enemy_box"],
                        box_color = flags["enemy_box_color"],
                        name = flags["enemy_name"],
                        distance = flags["enemy_distance"],
                        health_bar = flags["enemy_healthbar"],
                        glow = flags["enemy_glow"],
                        hologram = flags["enemy_hologram"],
                        hologram_color1 = flags["enemy_holo_color1"],
                        hologram_color2 = flags["enemy_holo_color2"],
                    })
                end
            end
        else
            for _, obj in pairs(enemy_esp) do
                obj:Remove()
            end
            enemy_esp = {}
        end
    end
})
]]
