--[[
    hako  —  Beautiful GUI ESP + Aim + Loot  (MacLib)
    Extraction shooter build.

    Rendering: instance-based GUI parented into gethui(). Keeping visuals out of
    workspace avoids modifying game models, but does not guarantee invisibility
    to an executor-aware or behavior-based anti-cheat.

    Safety:
      * Visuals live in gethui(), never under workspace / the enemy character.
      * No hooks (the "/" hook-detector stays quiet).
      * Aim nudges the OS mouse (mousemoverel) — no camera/CFrame writes, no
        remotes; the game's own Scriptable camera turns naturally.
      * Never touches WalkSpeed / JumpPower / position (server MovementAnticheat).
      * Chams use a Highlight in gethui() adorneed to the target; the character
        itself gets no new instances.
]]

-- ============================================================
-- Re-exec cleanup guard
-- ============================================================
if getgenv and getgenv().__HAKO_CLEANUP then
    pcall(getgenv().__HAKO_CLEANUP)
    task.wait(0.3)
end

-- ============================================================
-- Services
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local Window  -- forward declaration (used by aim + cleanup)
local restoreMenuMouse = function() end

-- ============================================================
-- Library
-- ============================================================
local okLib, MacLib = pcall(function()
    local errors = {}
    for _, url in ipairs({
        -- Pin the API version this script was verified against. Some executors
        -- fail the extra /latest redirect even though direct release assets work.
        "https://github.com/biggaboy212/Maclib/releases/download/9.Maclib/maclib.txt",
        "https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt",
    }) do
        local fetched, source = pcall(game.HttpGet, game, url)
        if fetched and type(source) == "string" then
            local chunk, compileError = loadstring(source)
            if chunk then
                local ran, library = pcall(chunk)
                if ran and library then return library end
                errors[#errors + 1] = tostring(library)
            else
                errors[#errors + 1] = tostring(compileError)
            end
        else
            errors[#errors + 1] = tostring(source)
        end
    end
    error(table.concat(errors, " | "))
end)
if not okLib or not MacLib then
    warn("[HAKO] Failed to load MacLib: " .. tostring(MacLib))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "hako: ошибка загрузки",
            Text = "MacLib не загрузилась. Откройте консоль исполнителя.",
            Duration = 10,
        })
    end)
    return
end
-- MacLib's bundled config parser skips Toggle=false during load and serializes
-- the Keybind:Bind method instead of the currently selected key. Keep its GUI,
-- folder layout and autoload UI, but replace only the serializer so every
-- control round-trips correctly (including MouseButton keybinds).
do
    local function ensureConfigFolders()
        if not (isfolder and makefolder) then return false, "Folder API unavailable." end
        for _, path in ipairs({ "hako", "hako/settings" }) do
            if not isfolder(path) then
                local ok, err = pcall(makefolder, path)
                if not ok and not isfolder(path) then return false, tostring(err) end
            end
        end
        return true
    end

    local folderOk, folderError = ensureConfigFolders()
    if not folderOk then warn("[HAKO] Config folder error: " .. tostring(folderError)) end
    pcall(function() MacLib:SetFolder("hako") end)

    local function colorToHex(color)
        return string.format("#%02X%02X%02X",
            math.floor(math.clamp(color.R, 0, 1) * 255 + 0.5),
            math.floor(math.clamp(color.G, 0, 1) * 255 + 0.5),
            math.floor(math.clamp(color.B, 0, 1) * 255 + 0.5))
    end

    local function hexToColor(hex)
        if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then return nil end
        return Color3.fromRGB(
            tonumber(hex:sub(2, 3), 16),
            tonumber(hex:sub(4, 5), 16),
            tonumber(hex:sub(6, 7), 16))
    end

    local function enumByName(enumType, name)
        if type(name) ~= "string" then return nil end
        local ok, value = pcall(function() return enumType[name] end)
        return ok and value or nil
    end

    function MacLib:SaveConfig(path)
        if not writefile then return false, "Config system unavailable." end
        if not path or tostring(path):gsub("%s", "") == "" then
            return false, "Please select a config file."
        end
        local foldersOk, foldersError = ensureConfigFolders()
        if not foldersOk then return false, foldersError end

        local objects = {}
        for flag, option in pairs(MacLib.Options or {}) do
            if not option.IgnoreConfig then
                local class = option.Class
                local object = { type = class, flag = flag }
                if class == "Toggle" then
                    if option.GetState then object.state = option:GetState()
                    else object.state = option.State == true end
                elseif class == "Slider" then
                    local value = option.GetValue and option:GetValue() or option.Value
                    object.value = value ~= nil and tostring(value) or nil
                elseif class == "Input" then
                    object.text = option.GetInput and option:GetInput() or option.Text
                elseif class == "Keybind" then
                    local bind = option.GetBind and option:GetBind() or nil
                    if typeof(bind) == "EnumItem" then
                        object.bind = bind.Name
                        object.bindType = string.find(tostring(bind.EnumType), "UserInputType", 1, true)
                            and "UserInputType" or "KeyCode"
                    end
                elseif class == "Dropdown" then
                    object.value = option.Value
                elseif class == "Colorpicker" and typeof(option.Color) == "Color3" then
                    object.color = colorToHex(option.Color)
                    object.alpha = option.Alpha
                else
                    object = nil
                end
                if object then objects[#objects + 1] = object end
            end
        end
        table.sort(objects, function(a, b) return tostring(a.flag) < tostring(b.flag) end)

        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, { version = 2, objects = objects })
        if not ok then return false, "Unable to encode JSON: " .. tostring(encoded) end
        local fullPath = MacLib.Folder .. "/settings/" .. tostring(path) .. ".json"
        local wrote, err = pcall(writefile, fullPath, encoded)
        if not wrote then return false, tostring(err) end
        if isfile and not isfile(fullPath) then return false, "Executor did not create the config file." end
        if readfile then
            local readOk, saved = pcall(readfile, fullPath)
            if not readOk or saved ~= encoded then return false, "Config verification failed after write." end
            local verifyOk, verified = pcall(HttpService.JSONDecode, HttpService, saved)
            if not verifyOk or type(verified) ~= "table" or type(verified.objects) ~= "table" then
                return false, "Saved config JSON is invalid."
            end
        end
        return true
    end

    function MacLib:LoadConfig(path)
        if not (isfile and readfile) then return false, "Config system unavailable." end
        if not path or tostring(path):gsub("%s", "") == "" then
            return false, "Please select a config file."
        end
        local foldersOk, foldersError = ensureConfigFolders()
        if not foldersOk then return false, foldersError end

        local file = MacLib.Folder .. "/settings/" .. tostring(path) .. ".json"
        if not isfile(file) then return false, "Invalid file" end
        local readOk, content = pcall(readfile, file)
        if not readOk then return false, tostring(content) end
        local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, content)
        if not decodeOk or type(decoded) ~= "table" or type(decoded.objects) ~= "table" then
            return false, "Unable to decode JSON data."
        end

        local errors = {}
        for _, object in ipairs(decoded.objects) do
            local option = MacLib.Options and MacLib.Options[object.flag]
            if option then
                local ok, err = pcall(function()
                    if object.type == "Toggle" and object.state ~= nil then
                        option:UpdateState(object.state == true)
                    elseif object.type == "Slider" and object.value ~= nil then
                        option:UpdateValue(tonumber(object.value))
                        -- MacLib's UpdateValue refreshes the widget with
                        -- ignorecallback=true; apply the runtime value too.
                        if option.Settings and option.Settings.Callback then
                            option.Settings.Callback(option:GetValue())
                        end
                    elseif object.type == "Input" and type(object.text) == "string" then
                        option:UpdateText(object.text)
                    elseif object.type == "Keybind" and object.bind then
                        local bind
                        if string.find(tostring(object.bindType), "UserInputType", 1, true) then
                            bind = enumByName(Enum.UserInputType, object.bind)
                        elseif string.find(tostring(object.bindType), "KeyCode", 1, true) then
                            bind = enumByName(Enum.KeyCode, object.bind)
                        else
                            -- Compatibility with version-1 MacLib configs.
                            bind = enumByName(Enum.KeyCode, object.bind)
                                or enumByName(Enum.UserInputType, object.bind)
                        end
                        if bind then option:Bind(bind) end
                    elseif object.type == "Dropdown" and object.value ~= nil then
                        option:UpdateSelection(object.value)
                    elseif object.type == "Colorpicker" and object.color then
                        local color = hexToColor(object.color)
                        if color then option:SetColor(color) end
                        if object.alpha ~= nil and option.SetAlpha then option:SetAlpha(object.alpha) end
                    end
                end)
                if not ok then errors[#errors + 1] = tostring(object.flag) .. ": " .. tostring(err) end
            end
        end
        if #errors > 0 then return false, table.concat(errors, "; ") end
        return true
    end

    -- MacLib:Window() defines its native serializer again while constructing
    -- the config UI. Preserve these fixed closures and restore them immediately
    -- after the window is created.
    MacLib.__HakoSaveConfig = MacLib.SaveConfig
    MacLib.__HakoLoadConfig = MacLib.LoadConfig
end

-- ============================================================
-- Hidden GUI root
-- ============================================================
local guiParent = (gethui and gethui()) or (get_hidden_gui and get_hidden_gui()) or game:GetService("CoreGui")

local function newInst(class, props, parent)
    local i = Instance.new(class)
    if props then
        for k, v in pairs(props) do i[k] = v end
    end
    if parent then i.Parent = parent end
    return i
end

local espGui = newInst("ScreenGui", {
    Name = string.format("_%x", math.random(0x100000, 0xFFFFFF)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 100000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
espGui.Parent = guiParent

-- ============================================================
-- Runtime settings. Defaults are declared next to their GUI controls below,
-- so this table contains only the values selected for the current session.
-- ============================================================
local cfg = {}
local function guiDefault(key, value)
    if cfg[key] == nil then cfg[key] = value end
    return cfg[key]
end

local aimHolding = false

-- ============================================================
-- Colors
-- ============================================================
local COLORS = {
    White = Color3.new(1, 1, 1), Black = Color3.new(0, 0, 0),
    Exfil = Color3.fromRGB(0, 255, 128), ExfilSub = Color3.fromRGB(160, 255, 190),
    Timer = Color3.fromRGB(255, 220, 100), Fov = Color3.fromRGB(255, 255, 255),
    Item = Color3.fromRGB(120, 255, 130), Body = Color3.fromRGB(230, 230, 230),
    HpRed = Color3.fromRGB(255, 45, 45), HpYellow = Color3.fromRGB(255, 210, 50),
    HpGreen = Color3.fromRGB(60, 255, 70),
    Loot = {
        Elite = Color3.fromRGB(255, 215, 0), High = Color3.fromRGB(200, 120, 255),
        Mid = Color3.fromRGB(90, 200, 255), Trash = Color3.fromRGB(150, 150, 150),
    },
}

-- Health -> color (green full, yellow half, red low). Color indicates HP level.
local function hpColor(frac)
    if frac >= 0.5 then return COLORS.HpYellow:Lerp(COLORS.HpGreen, (frac - 0.5) * 2) end
    return COLORS.HpRed:Lerp(COLORS.HpYellow, frac * 2)
end

-- ============================================================
-- GUI factory helpers
-- ============================================================
local function mkCorner(parent, r)
    return newInst("UICorner", { CornerRadius = UDim.new(0, r or 5) }, parent)
end

local function mkStroke(parent, color, thick, transparency)
    return newInst("UIStroke", {
        Color = color or COLORS.Black,
        Thickness = thick or 1,
        Transparency = transparency or 0,
        -- Contextual: outlines text glyphs (and follows frame shape) instead of
        -- drawing a rectangular border box around the label.
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
    }, parent)
end

local function mkText(parent, size, bold)
    return newInst("TextLabel", {
        BackgroundTransparency = 1,
        Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
        TextSize = size or 13,
        TextColor3 = COLORS.White,
        TextStrokeColor3 = COLORS.Black,       -- glyph outline (no border box)
        TextStrokeTransparency = 0.15,
        Text = "",
        RichText = true,
        Visible = false,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(320, (size or 13) + 6),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
end

-- ============================================================
-- Entity container (obfuscated, changes per server)
-- ============================================================
local function findEntityContainer()
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChild("NPCs") then
            return child
        end
    end
    return nil
end

-- ============================================================
-- ESP entry cache
-- ============================================================
local cache = {}
local conns = {}

-- BillboardGui-based ESP (Highlight outline + floating labels + gradient HP bar)
local function createEntry(model, isNpc)
    if cache[model] then return end
    local d = { isNpc = isNpc, visible = true, visAccum = 0 }

    -- Highlight: glowing outline (primary) + optional through-wall fill
    d.hl = newInst("Highlight", {
        Adornee = model,
        Enabled = false,
        FillColor = COLORS.White,
        OutlineColor = COLORS.White,
        FillTransparency = 1,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, espGui)

    -- Info billboard: name / distance+hp / weapon (auto-tracks the head in 3D)
    local infoBB = newInst("BillboardGui", {
        Size = UDim2.fromOffset(260, 70),
        StudsOffset = Vector3.new(0, 2.7, 0),
        AlwaysOnTop = true,
        MaxDistance = 6000,
        Enabled = false,
    }, espGui)
    d.infoBB = infoBB
    d.nameLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 0),
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = COLORS.White, Text = "",
        TextStrokeColor3 = COLORS.Black, TextStrokeTransparency = 0.15,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoBB)
    d.detailLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Position = UDim2.fromOffset(0, 19),
        Font = Enum.Font.GothamMedium, TextSize = 10, TextColor3 = Color3.fromRGB(215, 215, 215), Text = "",
        TextStrokeColor3 = COLORS.Black, TextStrokeTransparency = 0.2,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoBB)
    d.weapLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Position = UDim2.fromOffset(0, 35),
        Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.fromRGB(255, 200, 90), Text = "",
        TextStrokeColor3 = COLORS.Black, TextStrokeTransparency = 0.2,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoBB)
    d.gearLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Position = UDim2.fromOffset(0, 51),
        Font = Enum.Font.GothamMedium, TextSize = 9, TextColor3 = Color3.fromRGB(150, 205, 255), Text = "",
        TextStrokeColor3 = COLORS.Black, TextStrokeTransparency = 0.2,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoBB)

    -- Health bar billboard: pill, tri-color gradient, height matched to character
    local hpBB = newInst("BillboardGui", {
        Size = UDim2.fromOffset(5, 60),
        AlwaysOnTop = true,
        MaxDistance = 6000,
        Enabled = false,
    }, espGui)
    d.hpBB = hpBB
    local hpBg = newInst("Frame", {
        BackgroundColor3 = Color3.fromRGB(15, 15, 15), BackgroundTransparency = 0.2,
        Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
    }, hpBB)
    newInst("UICorner", { CornerRadius = UDim.new(1, 0) }, hpBg)
    mkStroke(hpBg, COLORS.Black, 1.4, 0.4)
    local hpFill = newInst("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0, BackgroundColor3 = COLORS.White,
    }, hpBg)
    newInst("UICorner", { CornerRadius = UDim.new(1, 0) }, hpFill)
    -- subtle vertical gloss; the fill's solid colour carries the HP level
    newInst("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.05),
            NumberSequenceKeypoint.new(1, 0.4),
        }),
    }, hpFill)
    d.hpFill = hpFill

    -- Tracer (2D, screen-space rotated line)
    d.tr = newInst("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = COLORS.White, BorderSizePixel = 0,
        Size = UDim2.fromOffset(0, 2), Visible = false,
    }, espGui)

    cache[model] = d
end

local function destroyEntry(model)
    local d = cache[model]
    if not d then return end
    pcall(function() d.hl:Destroy() end)
    pcall(function() d.infoBB:Destroy() end)
    pcall(function() d.hpBB:Destroy() end)
    pcall(function() d.tr:Destroy() end)
    cache[model] = nil
end

local function hideEntry(d)
    d.hl.Enabled = false
    d.infoBB.Enabled = false
    d.hpBB.Enabled = false
    d.tr.Visible = false
end

-- ============================================================
-- Line-of-sight raycasting for ESP visibility colors
-- ============================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function() rayParams.CollisionGroup = "Raycast" end)

local _rayFilter = {}
local _rayFilterStamp = -1
local function refreshRayFilter()
    local stamp = workspace.DistributedGameTime
    if stamp == _rayFilterStamp then return end
    _rayFilterStamp = stamp
    local n = 0
    local ch = player.Character
    if ch then n = n + 1; _rayFilter[n] = ch end
    local cam = workspace.CurrentCamera
    if cam then n = n + 1; _rayFilter[n] = cam end
    local ignored = workspace:FindFirstChild("Ignored")
    if ignored then n = n + 1; _rayFilter[n] = ignored end
    for i = n + 1, #_rayFilter do _rayFilter[i] = nil end
    rayParams.FilterDescendantsInstances = _rayFilter
end

-- The game's projectile handler measures a hit part from the entry point to its
-- reverse-ray exit and compares that depth with weapon.penetrate_depth. Reuse
-- the same geometry for LOS so invisible query parts do not create false cover
-- and Aim can recognise genuinely penetrable surfaces.
local rayReachesTarget
do
local penetrationState = { include = RaycastParams.new(), hardness = nil }
penetrationState.include.FilterType = Enum.RaycastFilterType.Include
penetrationState.include.IgnoreWater = true
pcall(function() penetrationState.include.CollisionGroup = "Raycast" end)
pcall(function()
    local storage = ReplicatedStorage:FindFirstChild("Storage")
    local modules = storage and storage:FindFirstChild("Modules")
    local source = modules and modules:FindFirstChild("MaterialPenetration")
    if source and source:IsA("ModuleScript") then penetrationState.hardness = require(source) end
end)

local function penetrationHardness(material)
    local module = penetrationState.hardness
    if not module or type(module.getHardness) ~= "function" then return 0 end
    local ok, value = pcall(module.getHardness, module, material)
    return ok and tonumber(value) or 0
end

local function rayPartDepth(entryPosition, unit, part, material)
    if not part:IsA("BasePart") then return nil end
    penetrationState.include.FilterDescendantsInstances = { part }
    local outside = entryPosition + unit * math.max(part.Size.Magnitude, 0.1)
    local exitHit = workspace:Raycast(outside, entryPosition - outside, penetrationState.include)
    if not exitHit then return nil end
    return (entryPosition - exitHit.Position).Magnitude + penetrationHardness(material), exitHit.Position
end

local function isDoorPart(part)
    local buildings = workspace:FindFirstChild("Buildings")
    local loots = buildings and buildings:FindFirstChild("Loots")
    local doors = loots and loots:FindFirstChild("Doors")
    return doors ~= nil and part:IsDescendantOf(doors)
end

local function isVisualNoise(part, material)
    if part:IsA("BasePart") and part.Transparency >= 0.95 then return true end
    if material == Enum.Material.Glass or material == Enum.Material.ForceField then return true end
    local buildings = workspace:FindFirstChild("Buildings")
    local glass = buildings and buildings:FindFirstChild("Glass")
    return glass ~= nil and part:IsDescendantOf(glass)
end

rayReachesTarget = function(origin, targetPosition, targetPart, params, allowBodyHit, penetrationDepth, totalPierceBudget)
    local fullDirection = targetPosition - origin
    local fullDistance = fullDirection.Magnitude
    if fullDistance < 0.001 then return false end
    local unit = fullDirection.Unit
    local cursor = origin
    local surfaceLimit = math.max(tonumber(penetrationDepth) or 0, 0)
    local totalLimit = math.max(tonumber(totalPierceBudget) or 0, 0)
    local spent = 0

    for _ = 1, 6 do
        local remaining = targetPosition - cursor
        if remaining:Dot(unit) <= 0 then return true end
        local result = workspace:Raycast(cursor, remaining, params)
        -- Non-queryable character parts cannot be returned by Raycast. No hit
        -- before their requested point therefore means the path itself is open.
        if not result or not result.Instance then return true end
        local hit = result.Instance
        if hit == targetPart or (allowBodyHit and hit:IsDescendantOf(targetPart.Parent)) then return true end
        if hit == workspace.Terrain or not hit:IsA("BasePart") then return false end

        local noise = isVisualNoise(hit, result.Material)
        local depth, exitPosition = rayPartDepth(result.Position, unit, hit, result.Material)
        if not depth or not exitPosition then return false end
        if not noise then
            if surfaceLimit <= 0 or isDoorPart(hit) or depth > surfaceLimit or spent >= totalLimit then
                return false
            end
            spent = spent + math.max(depth, 0)
        end
        cursor = exitPosition + unit * 0.02
    end
    return false
end
end

local function hasLineOfSight(cam, targetPart, targetPosition)
    if not targetPart:IsA("BasePart") then return false end
    refreshRayFilter()
    local origin = cam.CFrame.Position
    return rayReachesTarget(origin, targetPosition or targetPart.Position, targetPart, rayParams, true, 0, 0)
end

local ESP_VIS_POINTS = {
    Head = {
        Vector3.zero,
        Vector3.new(0, 0.32, 0),
        Vector3.new(-0.32, 0.08, 0),
        Vector3.new(0.32, 0.08, 0),
        Vector3.new(0, 0.08, -0.32),
        Vector3.new(0, 0.08, 0.32),
    },
    Torso = {
        Vector3.zero,
        Vector3.new(0, 0.3, 0),
        Vector3.new(-0.3, 0, 0),
        Vector3.new(0.3, 0, 0),
    },
}

local function partVisibleAtOffsets(part, cam, offsets)
    if not part or not part:IsA("BasePart") then return false end
    for _, offset in ipairs(offsets) do
        local point = part.CFrame:PointToWorldSpace(Vector3.new(
            offset.X * part.Size.X,
            offset.Y * part.Size.Y,
            offset.Z * part.Size.Z
        ))
        if hasLineOfSight(cam, part, point) then return true end
    end
    return false
end

-- Multipoint visibility catches partial peeks: the centre can still be behind a
-- wall while the top or one side of the head is already exposed.
local function computeVisible(model, cam)
    local head = model:FindFirstChild("Head")
    if partVisibleAtOffsets(head, cam, ESP_VIS_POINTS.Head) then return true end
    local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
        or model:FindFirstChild("HumanoidRootPart")
    if partVisibleAtOffsets(torso, cam, ESP_VIS_POINTS.Torso) then return true end
    return false
end

local function equipmentText(model)
    local gear, seen = {}, {}
    local function add(value)
        value = tostring(value or "")
        if value ~= "" and value ~= "nil" and not seen[value] then seen[value] = true; gear[#gear + 1] = value end
    end
    pcall(function()
        for key, value in pairs(model:GetAttributes()) do
            local lower = string.lower(tostring(key))
            if string.find(lower, "armor", 1, true) or string.find(lower, "helmet", 1, true) or string.find(lower, "backpack", 1, true) then add(value) end
        end
        local link = model:FindFirstChild("WeldObjectsLink")
        local root = link and link:IsA("ObjectValue") and link.Value
        if root then
            for _, child in ipairs(root:GetChildren()) do
                if child.Name ~= "thermalTemplate" then add(child.Name) end
                if #gear >= 3 then break end
            end
        end
        local plr = Players:GetPlayerFromCharacter(model)
        local data = plr and plr:FindFirstChild("playerData")
        local equipment = data and data:FindFirstChild("equipment", true)
        if equipment then
            for _, value in ipairs(equipment:GetChildren()) do
                if value:IsA("ObjectValue") and value.Value then add(value.Value.Name) end
                if #gear >= 3 then break end
            end
        end
    end)
    return table.concat(gear, " • ")
end

local function entityTypeAllowed(model, d)
    if d.isNpc then
        if not cfg.NpcESP then return false end
        if cfg.NpcNameFilter ~= "" and not string.find(string.lower(model.Name), string.lower(cfg.NpcNameFilter), 1, true) then
            return false
        end
        return true
    end
    if not cfg.PlayerESP then return false end
    if cfg.TeamCheck then
        local plr = Players:GetPlayerFromCharacter(model)
        if plr and plr.Team and plr.Team == player.Team then return false end
    end
    return true
end

local function entityMaxDistance(d)
    if not cfg.SeparateRanges then return cfg.MaxDistance end
    return d.isNpc and cfg.NpcMaxDistance or cfg.PlayerMaxDistance
end

local function detailFlags()
    if cfg.DetailMode == "Minimal" then return true, false, true, false end
    if cfg.DetailMode == "Combat" then return true, true, true, false end
    return true, true, true, true
end

-- ============================================================
-- Draw one entity
-- ============================================================
local function drawEntity(model, d, myRoot, cam, vpSize, dt)
    if not entityTypeAllowed(model, d) then return false end

    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end
    if not model:IsDescendantOf(workspace) then return false end
    local head = model:FindFirstChild("Head") or hrp

    local dist = myRoot and (hrp.Position - myRoot.Position).Magnitude or 0
    local maxDistance = entityMaxDistance(d)
    if dist > maxDistance then return false end
    local showNames, showHealth, showDistance, showWeapon = detailFlags()

    local hrpS, onScreen = cam:WorldToViewportPoint(hrp.Position)
    -- Off-screen (behind us / outside viewport): nothing renders anyway, so skip
    -- the raycasts, billboard updates and projections entirely.
    if not onScreen then
        hideEntry(d)
        return false
    end

    local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
    local col
    if d.isNpc then
        if cfg.NpcVisibleCheck then
            d.visAccum = (d.visAccum or 0) + (dt or 0)
            if d.visAccum >= 0.1 then
                d.visAccum = 0
                d.visible = computeVisible(model, cam)
            end
        end
        col = (not cfg.NpcVisibleCheck or d.visible) and cfg.NpcColor or cfg.HiddenColor
    else
        -- Wall check (always on for players): custom visible / behind-wall colors
        d.visAccum = (d.visAccum or 0) + (dt or 0)
        if d.visAccum >= 0.08 then
            d.visAccum = 0
            d.visible = computeVisible(model, cam)
        end
        col = d.visible and cfg.VisibleColor or cfg.HiddenColor
    end

    -- Highlight: outline (primary) + optional fill
    local useOutline = cfg.VisualMode == "Outline" or cfg.VisualMode == "Both"
    local useFill = cfg.VisualMode == "Fill" or cfg.VisualMode == "Both"
    if (useOutline or useFill) and d.highlightAllowed ~= false then
        d.hl.OutlineColor = col
        d.hl.OutlineTransparency = useOutline and 0 or 1
        d.hl.FillColor = col
        d.hl.FillTransparency = useFill and (1 - cfg.ChamsOpacity / 100) or 1
        d.hl.Enabled = true
    else
        d.hl.Enabled = false
    end

    local fade = 0
    if cfg.DistanceFade and maxDistance > 0 then
        fade = math.clamp((dist / maxDistance - 0.65) / 0.35, 0, 0.75)
    end
    d.nameLabel.TextTransparency = fade
    d.detailLabel.TextTransparency = fade
    d.weapLabel.TextTransparency = fade
    d.gearLabel.TextTransparency = fade
    d.hpFill.BackgroundTransparency = fade

    -- Info billboard
    if showNames or showDistance or showHealth or showWeapon then
        d.infoBB.Adornee = head
        d.infoBB.Enabled = true

        if showNames then
            local label
            if d.isNpc then
                label = model.Name
            else
                local plr = Players:GetPlayerFromCharacter(model)
                label = plr and plr.DisplayName or model.Name
            end
            d.nameLabel.Text = label
            d.nameLabel.TextColor3 = col
            d.nameLabel.Visible = true
        else
            d.nameLabel.Visible = false
        end

        if showDistance or showHealth then
            local parts = {}
            if showDistance then parts[#parts + 1] = string.format("%.0fм", dist) end
            if showHealth then parts[#parts + 1] = string.format("%d ОЗ", math.floor(hum.Health)) end
            d.detailLabel.Text = table.concat(parts, "  ")
            d.detailLabel.Visible = true
        else
            d.detailLabel.Visible = false
        end

        if showWeapon then
            local tool = model:FindFirstChildOfClass("Tool")
            if tool then
                d.gearAccum = (d.gearAccum or 999) + (dt or 0)
                if d.gearAccum >= 0.4 then
                    d.gearAccum = 0
                    local ammo, capacity
                    local okDesc, descendants = pcall(function() return tool:GetDescendants() end)
                    if okDesc then
                        for _, obj in ipairs(descendants) do
                            local lname = string.lower(obj.Name)
                            if obj:IsA("ValueBase") then
                                local okVal, value = pcall(function() return obj.Value end)
                                if okVal and type(value) == "number" then
                                    if lname == "ammo" or lname == "currentammo" or lname == "ammocount" then ammo = value end
                                    if lname == "capacity" or lname == "maxammo" or lname == "magazinesize" then capacity = value end
                                end
                            end
                        end
                    end
                    d.weaponText = tool.Name
                    if ammo then
                        d.weaponText = d.weaponText .. "  " .. tostring(math.floor(ammo))
                        if capacity then d.weaponText = d.weaponText .. "/" .. tostring(math.floor(capacity)) end
                    end
                end
                d.weapLabel.Text = "[" .. (d.weaponText or tool.Name) .. "]"
                d.weapLabel.Visible = true
            else
                local holsters = model:FindFirstChild("Holsters")
                local models = holsters and holsters:FindFirstChild("Models")
                local held = models and models:FindFirstChildWhichIsA("Model")
                if held then
                    d.weapLabel.Text = "[убрано: " .. held.Name .. "]"
                    d.weapLabel.Visible = true
                else
                    d.weapLabel.Visible = false
                end
            end
            d.equipAccum = (d.equipAccum or 999) + (dt or 0)
            if d.equipAccum >= 1 then
                d.equipAccum = 0
                d.gearText = equipmentText(model)
            end
            d.gearLabel.Text = d.gearText or ""
            d.gearLabel.Visible = d.gearLabel.Text ~= ""
        else
            d.weapLabel.Visible = false
            d.gearLabel.Visible = false
        end
    else
        d.infoBB.Enabled = false
    end

    -- Health bar billboard (size matched to character height)
    if showHealth then
        d.hpBB.Adornee = head
        d.hpBB.Enabled = true
        local sB = cam:WorldToViewportPoint(head.Position)
        local sT = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 5, 0))
        local px = math.max(math.abs(sT.Y - sB.Y), 6)
        d.hpBB.Size = UDim2.fromOffset(5, px)
        d.hpBB.StudsOffset = Vector3.new(-1.8, -2.5, 0)
        d.hpFill.Size = UDim2.new(1, 0, frac, 0)
        d.hpFill.BackgroundColor3 = hpColor(frac)
    else
        d.hpBB.Enabled = false
    end

    -- Tracer (2D, players only) — always on-screen here (off-screen returned early)
    if cfg.Tracers and not d.isNpc then
        local fx, fy = vpSize.X / 2, vpSize.Y
        local tx, ty = hrpS.X, hrpS.Y
        local dx, dy = tx - fx, ty - fy
        local len = math.sqrt(dx * dx + dy * dy)
        d.tr.Position = UDim2.fromOffset((fx + tx) / 2, (fy + ty) / 2)
        d.tr.Size = UDim2.fromOffset(len, 2)
        d.tr.Rotation = math.deg(math.atan2(dy, dx))
        d.tr.BackgroundColor3 = col
        d.tr.Visible = true
    else
        d.tr.Visible = false
    end

    return true
end

-- ============================================================
-- Exfil ESP + Raid Timer
-- ============================================================
local exfilCache = {}
local exfilFolder = nil
local raidContext = false

local raidPill = newInst("Frame", {
    BackgroundColor3 = Color3.fromRGB(15, 15, 18),
    BackgroundTransparency = 0.25,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 14),
    Size = UDim2.fromOffset(285, 34),
    Visible = false,
}, espGui)
mkCorner(raidPill, 8)
mkStroke(raidPill, Color3.fromRGB(255, 220, 100), 1, 0.4)
local raidLabel = newInst("TextLabel", {
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = COLORS.Timer,
    Text = "РЕЙД",
}, raidPill)

local contextLabel = mkText(espGui, 10, true)
contextLabel.AnchorPoint = Vector2.new(1, 0)
contextLabel.Position = UDim2.new(1, -18, 0, 16)
contextLabel.Size = UDim2.fromOffset(220, 22)
contextLabel.TextXAlignment = Enum.TextXAlignment.Right
contextLabel.Visible = true

local nearbyLabel = mkText(espGui, 11, true)
nearbyLabel.AnchorPoint = Vector2.new(0, 0)
nearbyLabel.Position = UDim2.fromOffset(18, 16)
nearbyLabel.Size = UDim2.fromOffset(560, 24)
nearbyLabel.TextXAlignment = Enum.TextXAlignment.Left

local function availableExfils()
    local result = {}
    local data = player:FindFirstChild("playerData")
    local folder = data and data:FindFirstChild("availableExtractionZones")
    if not folder then return result, false end
    for _, zone in ipairs(folder:GetChildren()) do
        if zone:IsA("Configuration") then
            local id = zone:GetAttribute("id") or zone:GetAttribute("name") or zone.Name
            result[tostring(id)] = {
                locked = zone:GetAttribute("locked") == true,
                timer = zone:GetAttribute("timer"),
                maxTimer = zone:GetAttribute("maxTimer"),
                position = zone:GetAttribute("position"),
                instance = zone,
            }
        end
    end
    return result, true
end

local function clearExfilCache()
    for _, d in pairs(exfilCache) do
        pcall(function() d.text:Destroy() end)
        pcall(function() d.sub:Destroy() end)
    end
    exfilCache = {}
end

local function findExfils()
    local ignored = workspace:FindFirstChild("Ignored")
    local exfils = ignored and ignored:FindFirstChild("Exfils")
    if exfils and exfils ~= exfilFolder then
        clearExfilCache()
        exfilFolder = exfils
    end
    local alive = {}
    local function ensureEntry(name)
        name = tostring(name)
        alive[name] = true
        if not exfilCache[name] then
            local text = mkText(espGui, 10, true)
            text.TextColor3 = COLORS.Exfil
            local sub = mkText(espGui, 9, false)
            sub.TextColor3 = COLORS.ExfilSub
            exfilCache[name] = { text = text, sub = sub, ename = name }
        end
        return exfilCache[name]
    end
    if exfils then
        for _, exfil in ipairs(exfils:GetChildren()) do
            local hitbox = exfil:FindFirstChild("hitbox")
            if hitbox and hitbox:IsA("BasePart") then ensureEntry(exfil.Name).part = hitbox end
        end
    end
    local available = availableExfils()
    for name, state in pairs(available) do
        local d = ensureEntry(name)
        if typeof(state.position) == "Vector3" then d.position = state.position end
    end
    for name, d in pairs(exfilCache) do
        if not alive[name] then
            pcall(function() d.text:Destroy(); d.sub:Destroy() end)
            exfilCache[name] = nil
        end
    end
end

local function drawExfils(myRoot, cam)
    local available, hasAvailability = availableExfils()
    local nearestName, nearestDistance
    if cfg.ExfilNearest and myRoot then
        for name, d in pairs(exfilCache) do
            local state = available[name]
            local pos = d.part and d.part.Parent and d.part.Position or (state and state.position) or d.position
            local shown = not cfg.ExfilOnlyAvailable or not hasAvailability or state ~= nil
            if shown and typeof(pos) == "Vector3" and (not state or not state.locked) then
                local distance = (pos - myRoot.Position).Magnitude
                if not nearestDistance or distance < nearestDistance then nearestName, nearestDistance = name, distance end
            end
        end
    end
    for name, d in pairs(exfilCache) do
        local ok2, vis2 = pcall(function()
            local state = available[name]
            local show = not cfg.ExfilOnlyAvailable or not hasAvailability or state ~= nil
            if state and state.locked and not cfg.ExfilShowLocked then show = false end
            if not show then return false end
            local pos = d.part and d.part.Parent and d.part.Position or (state and state.position) or d.position
            if typeof(pos) ~= "Vector3" then return false end
            d.position = pos
            local sPos, onScreen = cam:WorldToViewportPoint(pos)
            local dist = myRoot and (pos - myRoot.Position).Magnitude or 0
            local locked = state and state.locked
            local nearest = name == nearestName
            local color = locked and Color3.fromRGB(255, 80, 65) or (nearest and Color3.fromRGB(255, 225, 70) or COLORS.Exfil)
            if not onScreen then return false end
            d.text.Text = locked and "ЗАКРЫТЫЙ ВЫХОД" or (nearest and "БЛИЖАЙШИЙ ВЫХОД" or "ВЫХОД")
            d.text.TextColor3 = color
            d.text.Position = UDim2.fromOffset(sPos.X, sPos.Y - 8)
            d.text.Visible = true
            local suffix = ""
            if state and type(state.timer) == "number" then
                local mins = math.floor(math.max(state.timer, 0) / 60)
                local secs = math.floor(math.max(state.timer, 0) % 60)
                suffix = suffix .. string.format("  | %02d:%02d", mins, secs)
            end
            d.sub.Text = string.format("%.0fм%s", dist, suffix)
            d.sub.Position = UDim2.fromOffset(sPos.X, sPos.Y + 9)
            d.sub.Visible = true
            return true
        end)
        if not ok2 or not vis2 then
            d.text.Visible = false
            d.sub.Visible = false
        end
    end
end

local function hideExfils()
    for _, d in pairs(exfilCache) do
        d.text.Visible = false
        d.sub.Visible = false
    end
end

local raidCounter = 0
local raidWarned = {}
local lastRaidValue = nil
local function formatRaidTime(value)
    local hours = math.floor(value / 3600)
    local mins = math.floor((value % 3600) / 60)
    local secs = math.floor(value % 60)
    return hours > 0 and string.format("%02d:%02d:%02d", hours, mins, secs) or string.format("%02d:%02d", mins, secs)
end

local function detectContext()
    local available, hasAvailability = availableExfils()
    local ignored = workspace:FindFirstChild("Ignored")
    local exfils = ignored and ignored:FindFirstChild("Exfils")
    local hasExfils = exfils and #exfils:GetChildren() > 0
    raidContext = hasExfils or (hasAvailability and next(available) ~= nil)
    contextLabel.Visible = cfg.ServerInfo == true
    contextLabel.Text = raidContext and "● РЕЙД" or "● ЛОББИ"
    contextLabel.TextColor3 = raidContext and Color3.fromRGB(255, 100, 75) or Color3.fromRGB(100, 190, 255)
end

local function updateRaidTimer(dt)
    raidCounter = raidCounter + dt
    if raidCounter < 1 then return end
    raidCounter = 0
    detectContext()
    local s, val, maxTime, ended, doubleXp, fps = pcall(function()
        local srv = ReplicatedStorage:FindFirstChild("__server")
        local rt = srv and srv:FindFirstChild("RaidTimer")
        return rt and rt.Value, rt and rt:GetAttribute("maxTime"),
            srv and srv:FindFirstChild("IsRaidEnd") and srv.IsRaidEnd.Value,
            srv and srv:FindFirstChild("DoubleXp") and srv.DoubleXp.Value,
            srv and srv:FindFirstChild("Fps") and srv.Fps.Value
    end)
    if not s or type(val) ~= "number" or (cfg.ContextAuto and not raidContext) then
        raidPill.Visible = false
        return
    end
    if lastRaidValue and val > lastRaidValue + 30 then raidWarned = {} end
    lastRaidValue = val
    local extras = {}
    if ended then extras[#extras + 1] = "ЗАВЕРШЁН" end
    if cfg.ServerInfo and doubleXp then extras[#extras + 1] = "2XP" end
    if cfg.ServerInfo and fps then extras[#extras + 1] = tostring(fps) .. " К/С" end
    raidLabel.Text = "РЕЙД  " .. formatRaidTime(val) .. (#extras > 0 and ("  •  " .. table.concat(extras, "  •  ")) or "")
    if type(maxTime) == "number" and maxTime > 0 then
        raidLabel.TextColor3 = Color3.fromRGB(255, 55, 55):Lerp(COLORS.Timer, math.clamp(val / maxTime, 0, 1))
    end
    raidPill.Visible = true
    if cfg.RaidWarnings then
        for _, threshold in ipairs({600, 300, 60}) do
            if val <= threshold and not raidWarned[threshold] then
                raidWarned[threshold] = true
                if Window then pcall(function() Window:Notify({ Title = "Таймер рейда", Description = "Осталось " .. formatRaidTime(val), Lifetime = 5 }) end) end
            end
        end
    end
end

-- ============================================================
-- Loot ESP (pooled)
-- ============================================================
local RARITY = {
    ["Safe"] = "Elite", ["Scavs Safe"] = "Elite", ["Stocked Rifle Case"] = "Elite",
    ["Catacombs Weapon Box"] = "Elite", ["Catacombs Military Crate"] = "Elite",
    ["Military Crate"] = "Elite", ["StandingATM"] = "Elite", ["Military Radio"] = "Elite",
    ["Weapon Locker"] = "High", ["Rifle Case"] = "High", ["Weapon Box"] = "High",
    ["Medical Box"] = "High", ["Ammunition Box"] = "High", ["Complex Crate"] = "High",
    ["Surgeon's Tool Shelf"] = "High", ["Worn Surgeon's Tool Shelf"] = "High",
    ["Military File Cabinet"] = "High",
    ["Pistol Case"] = "Mid", ["Small Case"] = "Mid", ["Salvaged Small Case"] = "Mid",
    ["Toolbox"] = "Mid", ["Duffel Bag"] = "Mid", ["Ruined Duffel Bag"] = "Mid",
    ["Server Unit"] = "Mid", ["Cash Register"] = "Mid", ["Computer"] = "Mid",
    ["File Cabinet"] = "Mid", ["Tool Shelf"] = "Mid", ["Technical Shelf"] = "Mid",
    ["Medium Wooden Crate"] = "Mid", ["Worn Medium Wooden Crate"] = "Mid",
}
local function rarityOf(name) return RARITY[name] or "Trash" end

local itemDatabase = nil
local itemById = {}
local itemByLowerName = {}
pcall(function()
    local storage = ReplicatedStorage:WaitForChild("Storage", 10)
    local modules = storage and storage:FindFirstChild("Modules")
    local library = modules and modules:FindFirstChild("Library")
    local source = library and library:FindFirstChild("itemData")
    if source then
        itemDatabase = require(source)
        if type(itemDatabase) == "table" and type(itemDatabase.items) == "table" then
            for name, data in pairs(itemDatabase.items) do
                itemByLowerName[string.lower(tostring(name))] = tostring(name)
                if type(data) == "table" and data.itemId ~= nil then itemById[tostring(data.itemId)] = { name = name, data = data } end
            end
        end
    end
end)

local function itemMeta(inst)
    if not itemDatabase or type(itemDatabase.items) ~= "table" then return nil end
    local candidates = { inst.Name, inst:GetAttribute("itemName"), inst:GetAttribute("itemId"), inst:GetAttribute("id") }
    for _, candidate in ipairs(candidates) do
        if candidate ~= nil then
            local direct = itemDatabase.items[tostring(candidate)]
            if direct then return tostring(candidate), direct end
            local byId = itemById[tostring(candidate)]
            if byId then return byId.name, byId.data end
        end
    end
    return nil
end

local questDatabase = nil
local questDefinitionCache = {}
pcall(function()
    local storage = ReplicatedStorage:FindFirstChild("Storage")
    local modules = storage and storage:FindFirstChild("Modules")
    local library = modules and modules:FindFirstChild("Library")
    local source = library and library:FindFirstChild("quests")
    if source then questDatabase = require(source) end
end)

local inventorySummary = {
    totalValue = 0, totalWeight = 0, totalSlots = 0, count = 0,
    items = {}, ownedIds = {}, ownedNames = {}, lowest = nil, questCount = 0,
}
local activeQuestItems = {}
local currentQuestTitle = ""

local inventoryLabel = mkText(espGui, 10, true)
inventoryLabel.AnchorPoint = Vector2.new(0, 1)
inventoryLabel.Position = UDim2.new(0, 18, 1, -18)
inventoryLabel.Size = UDim2.fromOffset(400, 58)
inventoryLabel.TextXAlignment = Enum.TextXAlignment.Left
inventoryLabel.TextYAlignment = Enum.TextYAlignment.Bottom
inventoryLabel.TextColor3 = Color3.fromRGB(170, 235, 255)
inventoryLabel.Visible = false

local questPlannerLabel = mkText(espGui, 10, true)
questPlannerLabel.AnchorPoint = Vector2.new(0, 0)
questPlannerLabel.Position = UDim2.fromOffset(18, 48)
questPlannerLabel.Size = UDim2.fromOffset(400, 58)
questPlannerLabel.TextXAlignment = Enum.TextXAlignment.Left
questPlannerLabel.TextYAlignment = Enum.TextYAlignment.Top
questPlannerLabel.TextWrapped = true
questPlannerLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
questPlannerLabel.Visible = false

local function getBackpackFrame()
    local gui = player:FindFirstChild("PlayerGui")
    local ui = gui and gui:FindFirstChild("UI")
    local hud = ui and ui:FindFirstChild("HUD")
    return hud and hud:FindFirstChild("backpackFrame")
end

local function getInventoryItemsRoot()
    local bp = getBackpackFrame()
    local playerFrame = bp and bp:FindFirstChild("player")
    local inventoryFrame = playerFrame and playerFrame:FindFirstChild("inventoryFrame")
    return inventoryFrame and inventoryFrame:FindFirstChild("items")
end

local function gridSlots(data)
    local size = data and data.gridSize
    if typeof(size) == "Vector2" then return math.max(1, math.floor(size.X * size.Y)) end
    if type(size) == "table" then
        local x = tonumber(size.X or size.x or size[1]) or 1
        local y = tonumber(size.Y or size.y or size[2]) or 1
        return math.max(1, math.floor(x * y))
    end
    return 1
end

local function addInventoryItem(summary, inst, questFlag, seen)
    if not inst or seen[inst] then return end
    seen[inst] = true
    local name, data = itemMeta(inst)
    if not data then return end
    local slots = gridSlots(data)
    local price = tonumber(data.price) or 0
    local weight = tonumber(data.weight) or 0
    local id = data.itemId or inst:GetAttribute("itemId") or inst:GetAttribute("id")
    local row = {
        inst = inst, name = name or inst.Name, data = data, slots = slots,
        price = price, weight = weight, valuePerSlot = price / slots, quest = questFlag == true,
    }
    summary.items[#summary.items + 1] = row
    summary.totalValue = summary.totalValue + price
    summary.totalWeight = summary.totalWeight + weight
    summary.totalSlots = summary.totalSlots + slots
    summary.count = summary.count + 1
    summary.ownedNames[string.lower(row.name)] = (summary.ownedNames[string.lower(row.name)] or 0) + 1
    if id ~= nil then summary.ownedIds[tostring(id)] = (summary.ownedIds[tostring(id)] or 0) + 1 end
    if row.quest then summary.questCount = summary.questCount + 1 end
    if not row.quest and (not summary.lowest or row.valuePerSlot < summary.lowest.valuePerSlot) then summary.lowest = row end
end

local function addOwnedReference(summary, inst, seen)
    if not inst or seen[inst] then return end
    seen[inst] = true
    local name, data = itemMeta(inst)
    if not data then return end
    local resolvedName = name or inst.Name
    local id = data.itemId or inst:GetAttribute("itemId") or inst:GetAttribute("id")
    summary.ownedNames[string.lower(resolvedName)] = (summary.ownedNames[string.lower(resolvedName)] or 0) + 1
    if id ~= nil then summary.ownedIds[tostring(id)] = (summary.ownedIds[tostring(id)] or 0) + 1 end
end

local function scanInventory()
    local summary = {
        totalValue = 0, totalWeight = 0, totalSlots = 0, count = 0,
        items = {}, ownedIds = {}, ownedNames = {}, lowest = nil, questCount = 0,
    }
    local seen = {}
    local itemsRoot = getInventoryItemsRoot()
    if itemsRoot then
        for _, frame in ipairs(itemsRoot:GetDescendants()) do
            if frame.Name == "itemFrame" and frame:IsA("GuiObject") then
                local objectValue = frame:FindFirstChild("itemFolderObject")
                local linked = objectValue and objectValue:IsA("ObjectValue") and objectValue.Value
                local quest = frame:FindFirstChild("quest")
                addInventoryItem(summary, linked, quest and quest.Visible == true, seen)
            end
        end
    end
    local bag = player:FindFirstChild("Backpack")
    if bag then
        for _, object in ipairs(bag:GetDescendants()) do
            if object:IsA("ObjectValue") and object.Value then addOwnedReference(summary, object.Value, seen) end
        end
    end
    for _, row in ipairs(summary.items) do
        if row.quest then
            local key = string.lower(row.name)
            activeQuestItems[key] = math.max(activeQuestItems[key] or 0, 1)
        end
    end
    inventorySummary = summary
    if cfg.InventoryHelper then
        local lowest = summary.lowest and string.format(" | минимум: %s $%d/слот", summary.lowest.name, math.floor(summary.lowest.valuePerSlot)) or ""
        inventoryLabel.Text = string.format(
            "ИНВЕНТАРЬ  предметов: %d | слотов: %d | %.1f кг\nСтоимость: $%d | квестовых: %d%s",
            summary.count, summary.totalSlots, summary.totalWeight, math.floor(summary.totalValue), summary.questCount, lowest
        )
        inventoryLabel.Visible = true
    else
        inventoryLabel.Visible = false
    end
end

local function cleanGuiText(value)
    value = tostring(value or ""):gsub("<.->", ""):gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function questUiInfo()
    local bp = getBackpackFrame()
    local gui = player:FindFirstChild("PlayerGui")
    local ui = gui and gui:FindFirstChild("UI")
    local hud = ui and ui:FindFirstChild("HUD")
    local panel = bp and bp:FindFirstChild("questFrameDescriptions")
    local gameplay = (ui and ui:FindFirstChild("HUD_GAMEPLAY")) or (hud and hud:FindFirstChild("HUD_GAMEPLAY"))
    gameplay = gameplay and gameplay:FindFirstChild("quest")
    local source = panel and panel.Visible and panel or (gameplay and gameplay.Visible and gameplay)
    if not source then return "", {}, "" end
    local nameObject = source:FindFirstChild("questName", true)
    local typeObject = source:FindFirstChild("questType", true)
    local title = nameObject and nameObject:IsA("TextLabel") and cleanGuiText(nameObject.Text) or ""
    local qtype = typeObject and typeObject:IsA("TextLabel") and cleanGuiText(typeObject.Text) or ""
    local lines, used = {}, {}
    for _, object in ipairs(source:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible and object ~= nameObject and object ~= typeObject then
            local value = cleanGuiText(object.Text)
            if value ~= "" and #value <= 140 and not used[value] then
                used[value] = true
                lines[#lines + 1] = value
                if #lines >= 4 then break end
            end
        end
    end
    return title, lines, qtype
end

local function normalized(value)
    return string.lower(cleanGuiText(value)):gsub("[%s%p%c]+", "")
end

local function findQuestDefinition(title)
    if type(questDatabase) ~= "table" or title == "" then return nil end
    local wanted = normalized(title)
    if questDefinitionCache[wanted] ~= nil then return questDefinitionCache[wanted] or nil end
    local seen, visits = {}, 0
    local function walk(node, depth)
        if type(node) ~= "table" or seen[node] or depth > 12 or visits > 20000 then return nil end
        seen[node], visits = true, visits + 1
        for _, key in ipairs({"title", "name", "questName", "title_desc"}) do
            if type(node[key]) == "string" and normalized(node[key]) == wanted then return node end
        end
        for _, child in pairs(node) do
            local found = walk(child, depth + 1)
            if found then return found end
        end
        return nil
    end
    local found = walk(questDatabase, 0)
    questDefinitionCache[wanted] = found or false
    return found
end

local function rebuildQuestPlan()
    local title, _, qtype = questUiInfo()
    local lines = {}
    currentQuestTitle = title
    activeQuestItems = {}
    local definition = findQuestDefinition(title)
    local seen = {}
    local function addRequirement(value, count)
        if value == nil then return end
        local name = tostring(value)
        local byId = itemById[name]
        if byId then name = byId.name end
        name = itemByLowerName[string.lower(name)] or name
        activeQuestItems[string.lower(name)] = math.max(activeQuestItems[string.lower(name)] or 0, tonumber(count) or 1)
    end
    local function collect(node, depth)
        if type(node) ~= "table" or seen[node] or depth > 5 then return end
        seen[node] = true
        if type(node.objective_item_name) == "string" then addRequirement(node.objective_item_name, node.amount or node.count) end
        if type(node.objective_item_turn_in) == "table" then
            addRequirement(node.objective_item_turn_in.name or node.objective_item_turn_in.itemName or node.objective_item_turn_in.itemId,
                node.objective_item_turn_in.amount or node.objective_item_turn_in.count)
        end
        for _, child in pairs(node) do collect(child, depth + 1) end
    end
    if definition then
        collect(definition, 0)
        if type(definition.desc) == "string" then
            for candidate in string.gmatch(definition.desc, "<b>(.-)</b>") do
                local known = itemByLowerName[string.lower(cleanGuiText(candidate))]
                if known then addRequirement(known, 1) end
            end
        end
    end
    if cfg.QuestHelper and title ~= "" then
        local needed = {}
        for name, count in pairs(activeQuestItems) do
            needed[#needed + 1] = (itemByLowerName[name] or name) .. (count > 1 and (" x" .. tostring(count)) or "")
        end
        table.sort(needed)
        if #needed > 0 then table.insert(lines, 1, "Нужно: " .. table.concat(needed, ", ")) end
        local suffix = #lines > 0 and ("\n" .. table.concat(lines, "\n")) or ""
        local typeRu = ({["STORY QUEST"] = "СЮЖЕТ", ["DAILY QUEST"] = "ЕЖЕДНЕВНЫЙ", ["WEEKLY QUEST"] = "ЕЖЕНЕДЕЛЬНЫЙ"})[string.upper(qtype)] or qtype
        questPlannerLabel.Text = string.format("КВЕСТ%s  %s%s", typeRu ~= "" and (" [" .. typeRu .. "]") or "", title, suffix)
        questPlannerLabel.Visible = true
    else
        questPlannerLabel.Visible = false
    end
end

local function lootAdvice(entry)
    if entry.cat ~= "item" then return nil end
    if cfg.QuestHelper and activeQuestItems[string.lower(entry.label or "")] then return "КВЕСТ: ВЗЯТЬ", Color3.fromRGB(255, 220, 70) end
    local lowest = inventorySummary.lowest
    if lowest and (entry.valuePerSlot or 0) > lowest.valuePerSlot * 1.15 then
        return string.format("ЛУЧШЕ %s +$%d/слот", lowest.name, math.floor(entry.valuePerSlot - lowest.valuePerSlot)), Color3.fromRGB(90, 255, 150)
    end
    if (entry.price or 0) >= math.max(cfg.LootMinPrice, 2500) then return "ВЗЯТЬ", Color3.fromRGB(100, 235, 150) end
    return "ПРОПУСТИТЬ", Color3.fromRGB(180, 180, 180)
end

local function enrichLootEntry(entry)
    local name, data = itemMeta(entry.inst)
    if not data then return entry end
    entry.label = name or entry.label
    entry.price = tonumber(data.price) or 0
    entry.weight = tonumber(data.weight) or 0
    entry.pricePerKg = entry.weight > 0 and entry.price / entry.weight or entry.price
    entry.slots = gridSlots(data)
    entry.valuePerSlot = entry.price / entry.slots
    entry.tierType = data.tierType
    entry.color = typeof(data.tierColor) == "Color3" and data.tierColor or entry.color
    entry.category = type(data.baseData) == "table" and data.baseData.category or nil
    entry.lootAvailable = data.lootAvailable
    return entry
end

local LOOT_POOL = 45
local LOOT_HL = 16   -- Highlights are engine-limited (~31 total); cap loot glow low
local lootPool = {}
local lootHlPool = {}
for i = 1, LOOT_POOL do
    lootPool[i] = mkText(espGui, 9, true)
end
for i = 1, LOOT_HL do
    lootHlPool[i] = newInst("Highlight", {
        Enabled = false,
        FillTransparency = 0.8,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, espGui)
end

local lootEntries = {}
local lootDirty = true
local lootWatchRoot = nil
local lootWatchConns = {}
local lootListLabels = {}
for i = 1, 10 do
    local label = mkText(espGui, 9, i == 1)
    label.AnchorPoint = Vector2.new(1, 0)
    label.Position = UDim2.new(1, -18, 0, 50 + (i - 1) * 17)
    label.Size = UDim2.fromOffset(310, 17)
    label.TextXAlignment = Enum.TextXAlignment.Right
    lootListLabels[i] = label
end

local function rebuildLoot()
    local new = {}
    local buildings = workspace:FindFirstChild("Buildings")
    local loots = buildings and buildings:FindFirstChild("Loots")
    if loots ~= lootWatchRoot then
        for _, connection in ipairs(lootWatchConns) do
            pcall(function() connection:Disconnect() end)
        end
        lootWatchConns = {}
        lootWatchRoot = loots
        if loots then
            lootWatchConns[#lootWatchConns + 1] = loots.DescendantAdded:Connect(function() lootDirty = true end)
            lootWatchConns[#lootWatchConns + 1] = loots.DescendantRemoving:Connect(function() lootDirty = true end)
        end
    end
    if not loots then lootEntries = new return end

    local inner = loots:FindFirstChild("Loots")
    if inner then
        local crates = inner:FindFirstChild("Crates")
        if crates then
            for _, cc in ipairs(crates:GetChildren()) do
                if cc.Name ~= "X" then
                    local tier = rarityOf(cc.Name)
                    local ok, piv = pcall(function() return cc:GetPivot().Position end)
                    if ok and piv then
                        new[#new + 1] = { inst = cc, pos = piv, top = piv + Vector3.new(0, 2, 0), label = cc.Name, cat = "container", tier = tier, color = COLORS.Loot[tier], price = 0, pricePerKg = 0 }
                    end
                end
            end
        end
        local chars = inner:FindFirstChild("Characters")
        if chars then
            for _, cc in ipairs(chars:GetChildren()) do
                local ok, piv = pcall(function() return cc:GetPivot().Position end)
                if ok and piv then
                    new[#new + 1] = { inst = cc, pos = piv, top = piv + Vector3.new(0, 2, 0), label = "☠ Body", cat = "body", color = COLORS.Body, price = 0, pricePerKg = 0 }
                end
            end
        end
    end

    local items = loots:FindFirstChild("Items")
    if items then
        for _, cc in ipairs(items:GetChildren()) do
            local ok, piv = pcall(function() return cc:GetPivot().Position end)
            if ok and piv then
                local entry = { inst = cc, pos = piv, top = piv + Vector3.new(0, 2, 0), label = cc.Name, cat = "item", color = COLORS.Item, price = 0, pricePerKg = 0 }
                new[#new + 1] = enrichLootEntry(entry)
            end
        end
    end

    lootEntries = new
    lootDirty = false
end

local function lootCatEnabled(e)
    if e.cat == "item" then
        if not cfg.LootItems then return false end
        if cfg.QuestHelper and activeQuestItems[string.lower(e.label or "")] then return true end
        if (e.price or 0) < cfg.LootMinPrice then return false end
        if (e.pricePerKg or 0) < cfg.LootMinPricePerKg then return false end
        return true
    end
    if e.cat == "body" then return cfg.LootBodies end
    if e.tier == "Elite" then return cfg.LootElite end
    if e.tier == "High" then return cfg.LootHigh end
    if e.tier == "Mid" then return cfg.LootMid end
    return cfg.LootTrash
end

local function hideLoot()
    for i = 1, LOOT_POOL do lootPool[i].Visible = false end
    for i = 1, LOOT_HL do lootHlPool[i].Enabled = false end
    for _, label in ipairs(lootListLabels) do label.Visible = false end
end

-- The nearest-N selection + sort (the expensive part) is throttled; the chosen
-- entries are re-projected every frame so the labels still track smoothly.
local lootSelected = {}
local lootSelAccum = 999

local function selectLoot(myPos)
    local maxd = cfg.LootMaxDist
    local shown = {}
    for _, e in ipairs(lootEntries) do
        if lootCatEnabled(e) then
            local ok, piv = pcall(function() return e.inst:GetPivot().Position end)
            if ok and piv then e.pos = piv; e.top = piv + Vector3.new(0, 2, 0) end
            local dd = (e.pos - myPos).Magnitude
            if dd <= maxd then
                shown[#shown + 1] = { e = e, d = dd }
            end
        end
    end
    table.sort(shown, function(a, b)
        if cfg.LootSort == "Price" then
            if (a.e.price or 0) == (b.e.price or 0) then return a.d < b.d end
            return (a.e.price or 0) > (b.e.price or 0)
        elseif cfg.LootSort == "Price/kg" then
            if (a.e.pricePerKg or 0) == (b.e.pricePerKg or 0) then return a.d < b.d end
            return (a.e.pricePerKg or 0) > (b.e.pricePerKg or 0)
        end
        return a.d < b.d
    end)
    local sel = {}
    for i = 1, math.min(#shown, LOOT_POOL) do sel[i] = shown[i].e end
    lootSelected = sel
end

local function drawLoot(myRoot, cam, dt)
    if not myRoot then hideLoot() return end
    local myPos = myRoot.Position

    lootSelAccum = lootSelAccum + (dt or 0)
    if lootSelAccum >= 0.1 then
        lootSelAccum = 0
        selectLoot(myPos)
    end

    local n = #lootSelected
    for i = 1, LOOT_POOL do
        local e = (i <= n) and lootSelected[i] or nil
        local alive = e and e.inst and e.inst.Parent ~= nil

        -- Highlight the loot model itself (nearest LOOT_HL, glows by rarity)
        if lootHlPool[i] then
            if alive then
                local hl = lootHlPool[i]
                hl.Adornee = e.inst
                hl.FillColor = e.color
                hl.OutlineColor = e.color
                hl.Enabled = true
            else
                lootHlPool[i].Enabled = false
            end
        end

        -- Optional name + distance label (on-screen only)
        local txt = lootPool[i]
        if alive and cfg.LootNames then
            local sc, on = cam:WorldToViewportPoint(e.top or e.pos)
            if on then
                local parts = {e.label}
                if cfg.LootShowPrice and (e.price or 0) > 0 then parts[#parts + 1] = "$" .. tostring(math.floor(e.price)) end
                if cfg.LootShowCategory and e.category then parts[#parts + 1] = tostring(e.category) end
                local advice, adviceColor = cfg.LootShowAdvice and lootAdvice(e) or nil
                if advice then parts[#parts + 1] = advice end
                parts[#parts + 1] = string.format("<font transparency='0.4'>%.0fм</font>", (e.pos - myPos).Magnitude)
                txt.Text = table.concat(parts, " • ")
                txt.Position = UDim2.fromOffset(sc.X, sc.Y)
                txt.TextColor3 = adviceColor or e.color
                txt.Visible = true
            else
                txt.Visible = false
            end
        else
            txt.Visible = false
        end
    end

    for i, label in ipairs(lootListLabels) do
        local e = lootSelected[i]
        if cfg.LootList and e and e.inst and e.inst.Parent then
            local parts = {e.label}
            if cfg.LootShowPrice and (e.price or 0) > 0 then parts[#parts + 1] = "$" .. tostring(math.floor(e.price)) end
            local advice, adviceColor = cfg.LootShowAdvice and lootAdvice(e) or nil
            if advice then parts[#parts + 1] = advice end
            parts[#parts + 1] = string.format("%.0fм", (e.pos - myPos).Magnitude)
            label.Text = table.concat(parts, " • ")
            label.TextColor3 = adviceColor or e.color
            label.Visible = true
        else
            label.Visible = false
        end
    end
end

-- ============================================================
-- Door assistant (passive Configuration reader)
-- ============================================================
local DOOR_POOL = 18
local doorLabels = {}
for i = 1, DOOR_POOL do doorLabels[i] = mkText(espGui, 9, true) end
local doorEntries = {}

local function configValue(parent, name, fallback)
    local object = parent and parent:FindFirstChild(name)
    if object and object:IsA("ValueBase") then return object.Value end
    return fallback
end

local function refreshDoors()
    local buildings = workspace:FindFirstChild("Buildings")
    local loots = buildings and buildings:FindFirstChild("Loots")
    local folder = loots and loots:FindFirstChild("Doors")
    local result = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            local data = model:FindFirstChild("data")
            if model:IsA("Model") and data then
                local required = data:FindFirstChild("isKeyRequired")
                local health = data:FindFirstChild("health")
                local ok, pos = pcall(function() return model:GetPivot().Position end)
                if ok and pos then
                    result[#result + 1] = {
                        model = model, data = data, pos = pos,
                        open = configValue(data, "isOpen", false) == true,
                        locked = configValue(data, "isLocked", false) == true,
                        broken = configValue(data, "isBroken", false) == true,
                        knobBroken = configValue(data, "knobBroken", false) == true,
                        keyRequired = required and required:IsA("BoolValue") and required.Value == true or false,
                        keyItemId = required and required:GetAttribute("keyItemId"),
                        keycard = required and required:GetAttribute("isKeycard") == true or false,
                        health = tonumber(configValue(health, "current", nil)),
                        maxHealth = tonumber(configValue(health, "max", nil)),
                    }
                end
            end
        end
    end
    doorEntries = result
end

local function hideDoors()
    for _, label in ipairs(doorLabels) do label.Visible = false end
end

local function drawDoors(myRoot, cam)
    if not myRoot then hideDoors() return end
    local nearby = {}
    for _, door in ipairs(doorEntries) do
        if door.model and door.model.Parent then
            local ok, pos = pcall(function() return door.model:GetPivot().Position end)
            if ok then door.pos = pos end
            local distance = (door.pos - myRoot.Position).Magnitude
            local interesting = door.locked or door.keyRequired or door.broken or door.knobBroken
            if distance <= cfg.DoorMaxDist and (not cfg.DoorOnlyInteresting or interesting) then
                nearby[#nearby + 1] = { door = door, distance = distance }
            end
        end
    end
    table.sort(nearby, function(a, b) return a.distance < b.distance end)
    for i, label in ipairs(doorLabels) do
        local row = nearby[i]
        if row then
            local door = row.door
            local screen, onScreen = cam:WorldToViewportPoint(door.pos + Vector3.new(0, 2.5, 0))
            if onScreen then
                local keyOwned = door.keyItemId ~= nil and inventorySummary.ownedIds[tostring(door.keyItemId)] ~= nil
                local state, color = "ЗАКРЫТА", Color3.fromRGB(190, 220, 255)
                if door.open then state, color = "ОТКРЫТА", Color3.fromRGB(100, 255, 145)
                elseif door.broken or door.knobBroken then state, color = "СЛОМАНА", Color3.fromRGB(255, 175, 70)
                elseif door.keyRequired then
                    if cfg.DoorCheckKeys and keyOwned then state, color = "КЛЮЧ ЕСТЬ", Color3.fromRGB(100, 255, 145)
                    elseif cfg.DoorCheckKeys then state, color = "НЕТ КЛЮЧА", Color3.fromRGB(255, 90, 75)
                    else state, color = door.keycard and "НУЖНА КАРТА" or "НУЖЕН КЛЮЧ", Color3.fromRGB(255, 185, 70) end
                elseif door.locked then state, color = "ЗАПЕРТА", Color3.fromRGB(255, 90, 75) end
                local hp = door.health and door.maxHealth and string.format(" | прочность %d/%d", door.health, door.maxHealth) or ""
                label.Text = string.format("ДВЕРЬ: %s%s | %.0fм", state, hp, row.distance)
                label.TextColor3 = color
                label.Position = UDim2.fromOffset(screen.X, screen.Y)
                label.Visible = true
            else
                label.Visible = false
            end
        else
            label.Visible = false
        end
    end
end

-- ============================================================
-- Fullbright
-- ============================================================
local lightingSaved = nil
local function applyFullbright()
    if not lightingSaved then
        lightingSaved = {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient, GlobalShadows = Lighting.GlobalShadows,
        }
    end
    Lighting.Brightness = 2
    Lighting.ClockTime = 12
    Lighting.FogEnd = 1e9
    Lighting.Ambient = Color3.fromRGB(180, 180, 180)
    Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
    Lighting.GlobalShadows = false
end
local function restoreFullbright()
    if not lightingSaved then return end
    pcall(function()
        Lighting.Brightness = lightingSaved.Brightness
        Lighting.ClockTime = lightingSaved.ClockTime
        Lighting.FogEnd = lightingSaved.FogEnd
        Lighting.Ambient = lightingSaved.Ambient
        Lighting.OutdoorAmbient = lightingSaved.OutdoorAmbient
        Lighting.GlobalShadows = lightingSaved.GlobalShadows
    end)
    lightingSaved = nil
end

-- ============================================================
-- Quest item highlight (uses the game's built-in itemFrame.quest flag)
-- ============================================================
local QUEST_HL = "_hakoQuestHL"
local QUEST_TAG = "_hakoQuestTag"

local function backpackRoot()
    return getBackpackFrame()
end

local function clearQuestHL()
    local bp = backpackRoot()
    if not bp then return end
    for _, f in ipairs(bp:GetDescendants()) do
        if f.Name == QUEST_HL or f.Name == QUEST_TAG then pcall(function() f:Destroy() end) end
    end
end

-- Highlight every item slot the game flags as a quest item
local function scanQuestItems()
    local bp = backpackRoot()
    if not bp then return end
    for _, f in ipairs(bp:GetDescendants()) do
        if f.Name == "itemFrame" and f:IsA("GuiObject") and f.Visible then
            local q = f:FindFirstChild("quest")
            local isQuest = q ~= nil and q.Visible == true
            local hl = f:FindFirstChild(QUEST_HL)
            if isQuest and not hl then
                local s = Instance.new("UIStroke")
                s.Name = QUEST_HL
                s.Color = Color3.fromRGB(255, 215, 0)
                s.Thickness = 3
                s.Transparency = 0
                s.Parent = f
                local tag = Instance.new("TextLabel")
                tag.Name = QUEST_TAG
                tag.AnchorPoint = Vector2.new(0, 1)
                tag.Position = UDim2.new(0, 3, 1, -3)
                tag.Size = UDim2.new(1, -6, 0, 15)
                tag.BackgroundTransparency = 1
                tag.Font = Enum.Font.GothamBold
                tag.TextSize = 10
                tag.TextXAlignment = Enum.TextXAlignment.Left
                tag.TextColor3 = Color3.fromRGB(255, 215, 0)
                tag.TextStrokeTransparency = 0.25
                tag.Text = "КВЕСТ"
                local obj = f:FindFirstChild("itemFolderObject")
                local linked = obj and obj:IsA("ObjectValue") and obj.Value
                if linked then
                    local _, data = itemMeta(linked)
                    if data and data.price then tag.Text = "КВЕСТ • $" .. tostring(math.floor(data.price)) end
                end
                tag.ZIndex = math.max(f.ZIndex + 20, 20)
                tag.Parent = f
            elseif not isQuest then
                if hl then pcall(function() hl:Destroy() end) end
                local tag = f:FindFirstChild(QUEST_TAG)
                if tag then pcall(function() tag:Destroy() end) end
            end
        end
    end
end

-- ============================================================
-- Aim Assist
-- ============================================================
local aimTarget = nil
local aimOccludedAt = nil
local aimTargetVisible = true
local aimLockedModel = nil
local aimLockedAt = 0
local aimMouseWarningShown = false
local smartHeadBlockedAt = setmetatable({}, { __mode = "k" })
local aimPointLocal = setmetatable({}, { __mode = "k" })
local gunProfileCache = setmetatable({}, { __mode = "k" })
local gunRuntimeCache = setmetatable({}, { __mode = "k" })
local muzzleObjectCache = setmetatable({}, { __mode = "k" })
local getGunAimState = function() return nil end
local aimWhitelist = {}  -- [UserId] = true; aim ignores these players
local WHITELIST_FILE = "hako/aim_whitelist.json"

local function saveWhitelist()
    if not writefile then return end
    pcall(function()
        if makefolder then pcall(makefolder, "hako") end
        local ids = {}
        for id in pairs(aimWhitelist) do ids[#ids + 1] = id end
        writefile(WHITELIST_FILE, HttpService:JSONEncode(ids))
    end)
end

pcall(function()
    if readfile and (not isfile or isfile(WHITELIST_FILE)) then
        for _, id in ipairs(HttpService:JSONDecode(readfile(WHITELIST_FILE))) do aimWhitelist[tonumber(id) or id] = true end
    end
end)

local fovCircle = newInst("Frame", {
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Visible = false,
}, espGui)
mkCorner(fovCircle, 999)
mkStroke(fovCircle, COLORS.Fov, 1.5, 0.4)

local aimRayParams = RaycastParams.new()
aimRayParams.FilterType = Enum.RaycastFilterType.Exclude
aimRayParams.IgnoreWater = true
pcall(function() aimRayParams.CollisionGroup = "Raycast" end)

local AIM_STYLE = {
    Legit = { smoothness = 7, deadzone = 2, maxStep = 18, recoil = 0.75, spreadDeadzone = 2.5, targetHold = 0.55, switchRatio = 1.08, switchBonus = 3 },
    Rage = { smoothness = 3, deadzone = 0.8, maxStep = 40, recoil = 1.05, spreadDeadzone = 1.25, targetHold = 0.72, switchRatio = 1.18, switchBonus = 6 },
    SuperRage = { smoothness = 1, deadzone = 0, maxStep = 80, recoil = 1.35, spreadDeadzone = 0.25, targetHold = 0.85, switchRatio = 1.3, switchBonus = 10 },
}
local function aimStyle()
    return AIM_STYLE[cfg.AimStyle] or AIM_STYLE.Legit
end

local function equippedMuzzlePosition(character)
    local tool = character and character:FindFirstChildWhichIsA("Tool")
    if not tool or tool:GetAttribute("Gun") ~= true then return nil end
    local muzzle = muzzleObjectCache[tool]
    if not muzzle or not muzzle.Parent or not muzzle:IsDescendantOf(tool) then
        local model = tool:FindFirstChild("_mod")
        local handle = (model and model:FindFirstChild("Handle", true)) or tool:FindFirstChild("Handle", true)
        muzzle = (handle and handle:FindFirstChild("MuzzleFX", true)) or tool:FindFirstChild("MuzzleFX", true)
        if muzzle and not (muzzle:IsA("Attachment") or muzzle:IsA("BasePart")) then
            muzzle = muzzle:FindFirstChildWhichIsA("Attachment", true)
                or muzzle:FindFirstChildWhichIsA("BasePart", true)
        end
        if muzzle then muzzleObjectCache[tool] = muzzle end
    end
    if muzzle and muzzle:IsA("Attachment") then return muzzle.WorldPosition end
    if muzzle and muzzle:IsA("BasePart") then return muzzle.Position end
    return nil
end

local aimFilterState = { stamp = -1, values = {} }
local function currentAimFilter(cam)
    local stamp = workspace.DistributedGameTime
    if stamp == aimFilterState.stamp then return aimFilterState.values end
    aimFilterState.stamp = stamp
    local filter = aimFilterState.values
    table.clear(filter)
    local character = player.Character
    if character then filter[#filter + 1] = character end
    filter[#filter + 1] = cam
    local ignored = workspace:FindFirstChild("Ignored")
    if ignored then filter[#filter + 1] = ignored end
    return filter
end

local function rayReachesAimPart(origin, targetPart, targetPosition, filter, allowBodyHit)
    aimRayParams.FilterDescendantsInstances = filter
    local gunState = getGunAimState()
    local penetrationDepth = gunState and gunState.penetrationDepth or 0
    local pierceBudget = gunState and gunState.pierceBudget or 0
    return rayReachesTarget(origin, targetPosition, targetPart, aimRayParams, allowBodyHit, penetrationDepth, pierceBudget)
end

local function hasAimLineOfSight(cam, targetPart, targetPosition)
    local character = player.Character
    local filter = currentAimFilter(cam)
    targetPosition = targetPosition or targetPart.Position
    if not rayReachesAimPart(cam.CFrame.Position, targetPart, targetPosition, filter, true) then
        return false
    end

    -- Camera visibility is insufficient near cover: the game fires from
    -- Handle.MuzzleFX. Require the same point to be clear from the muzzle so a
    -- visible head above a truck is not selected while the barrel hits its side.
    local muzzlePosition = equippedMuzzlePosition(character)
    if muzzlePosition and not rayReachesAimPart(muzzlePosition, targetPart, targetPosition, filter, true) then
        return false
    end
    return true
end

local function currentAimPoint(part)
    local localPoint = aimPointLocal[part]
    if typeof(localPoint) ~= "Vector3" then return part.Position end
    return part.CFrame:PointToWorldSpace(localPoint)
end

local function visibleAimPoint(cam, part)
    if not cfg.AimLosCheck then
        aimPointLocal[part] = Vector3.zero
        return part.Position
    end

    local size = part.Size
    local offsets = { Vector3.zero }
    if cfg.AimTargetPart == "Smart" then
        if part.Name == "Head" then
            offsets[#offsets + 1] = Vector3.new(0, size.Y * 0.24, 0)
            offsets[#offsets + 1] = Vector3.new(-size.X * 0.28, size.Y * 0.08, 0)
            offsets[#offsets + 1] = Vector3.new(size.X * 0.28, size.Y * 0.08, 0)
            offsets[#offsets + 1] = Vector3.new(0, 0, -size.Z * 0.24)
            offsets[#offsets + 1] = Vector3.new(0, 0, size.Z * 0.24)
            offsets[#offsets + 1] = Vector3.new(0, -size.Y * 0.2, 0)
        else
            offsets[#offsets + 1] = Vector3.new(0, size.Y * 0.22, 0)
            offsets[#offsets + 1] = Vector3.new(-size.X * 0.25, 0, 0)
            offsets[#offsets + 1] = Vector3.new(size.X * 0.25, 0, 0)
            offsets[#offsets + 1] = Vector3.new(0, -size.Y * 0.2, 0)
        end
    end

    for _, offset in ipairs(offsets) do
        local point = part.CFrame:PointToWorldSpace(offset)
        if hasAimLineOfSight(cam, part, point) then
            aimPointLocal[part] = offset
            return point
        end
    end
    return nil
end

local function canAimAtPart(cam, part)
    return visibleAimPoint(cam, part) ~= nil
end

local function aimParts(model)
    local result, seen = {}, {}
    local function add(name)
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") and not seen[part] then
            seen[part] = true
            result[#result + 1] = part
        end
    end
    local mode = cfg.AimTargetPart
    if mode == "Smart" then
        add("Head"); add("UpperTorso"); add("Torso"); add("LowerTorso"); add("HumanoidRootPart")
    elseif mode == "Body" or mode == "Torso" then
        add("UpperTorso"); add("Torso"); add("LowerTorso"); add("HumanoidRootPart")
    elseif mode == "Center" or mode == "HumanoidRootPart" then
        add("HumanoidRootPart"); add("UpperTorso"); add("Torso")
    else
        add("Head")
    end
    if #result == 0 then add("HumanoidRootPart"); add("UpperTorso"); add("Torso") end
    return result
end

local function aimPartWithinRadius(cam, part, center, radius)
    if not center or not radius then return true end
    local screen, onScreen = cam:WorldToViewportPoint(currentAimPoint(part))
    if not onScreen then return false end
    return (Vector2.new(screen.X, screen.Y) - center).Magnitude < radius
end

local function resolveAimPart(model, cam, center, radius)
    local parts = aimParts(model)
    if cfg.AimTargetPart == "Smart" and parts[1] and parts[1].Name == "Head" then
        local head = parts[1]
        local headVisible = canAimAtPart(cam, head)
        if headVisible and aimPartWithinRadius(cam, head, center, radius) then
            smartHeadBlockedAt[model] = nil
            return head
        end
        -- Grace is useful only when an already locked head disappears for one
        -- noisy raycast frame. On first acquisition it merely creates a visible
        -- delay before Smart falls back to an exposed torso.
        local wasLockedOnHead = aimLockedModel == model and aimTarget
            and aimTarget.Parent == model and aimTarget.Name == "Head"
        if not headVisible and wasLockedOnHead then
            smartHeadBlockedAt[model] = smartHeadBlockedAt[model] or os.clock()
            if os.clock() - smartHeadBlockedAt[model] < 0.12 then return nil end
        else
            smartHeadBlockedAt[model] = nil
        end
        for i = 2, #parts do
            if canAimAtPart(cam, parts[i]) and aimPartWithinRadius(cam, parts[i], center, radius) then
                return parts[i]
            end
        end
        return nil
    end
    for _, part in ipairs(parts) do
        if canAimAtPart(cam, part) and aimPartWithinRadius(cam, part, center, radius) then return part end
    end
    return nil
end

local function aimScore(hum, screenDistance, worldDistance)
    if cfg.AimPriority == "Distance" then return worldDistance + screenDistance * 0.05 end
    if cfg.AimPriority == "Lowest HP" then
        return (hum.Health / math.max(hum.MaxHealth, 1)) * 100 + screenDistance * 0.01
    end
    return screenDistance
end

local function pickAimTarget(cam, vpSize, myRoot)
    local center = Vector2.new(vpSize.X / 2, vpSize.Y / 2)
    local bestPlayer, bestPlayerScore = nil, math.huge
    local bestNpc, bestNpcScore = nil, math.huge
    local lockedCandidate, lockedScore = nil, math.huge

    for model, d in pairs(cache) do
        local skip = false
        if d.isNpc and not cfg.AimTargetNpcs then skip = true end
        if not d.isNpc and not cfg.AimTargetPlayers then skip = true end
        if not skip and not d.isNpc then
            local wp = Players:GetPlayerFromCharacter(model)
            if wp and aimWhitelist[wp.UserId] then skip = true end
        end
        if not skip then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then skip = true end
            if not skip and not d.isNpc and cfg.AimTeamCheck then
                local plr = Players:GetPlayerFromCharacter(model)
                if plr and plr.Team and plr.Team == player.Team then skip = true end
            end
            if not skip then
                local anchor = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
                if not anchor or (anchor.Position - myRoot.Position).Magnitude > cfg.AimMaxDist then
                    skip = true
                end
            end
            if not skip then
                local part = resolveAimPart(model, cam, center, cfg.AimFov)
                if not part then skip = true end
                if not skip then
                    local d3 = (part.Position - myRoot.Position).Magnitude
                    if d3 > cfg.AimMaxDist then skip = true end
                    if not skip then
                        local screen, onScreen = cam:WorldToViewportPoint(currentAimPoint(part))
                        if onScreen then
                            local sd = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                            if sd < cfg.AimFov then
                                local score = aimScore(hum, sd, d3)
                                if model == aimLockedModel then
                                    lockedCandidate, lockedScore = part, score
                                end
                                if d.isNpc then
                                    if score < bestNpcScore then bestNpc, bestNpcScore = part, score end
                                else
                                    if score < bestPlayerScore then bestPlayer, bestPlayerScore = part, score end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local chosen, chosenScore
    if cfg.AimPreferPlayers and bestPlayer then
        chosen, chosenScore = bestPlayer, bestPlayerScore
    elseif bestPlayerScore <= bestNpcScore then
        chosen, chosenScore = bestPlayer, bestPlayerScore
    else
        chosen, chosenScore = bestNpc, bestNpcScore
    end

    -- Prevent frame-to-frame ping-pong when two targets overlap. Keep the
    -- current model for a short minimum time and afterwards switch only when
    -- the replacement is meaningfully better, not one or two pixels better.
    if cfg.AimRetention ~= "Off" and lockedCandidate then
        local tuning = aimStyle()
        local youngLock = os.clock() - aimLockedAt < tuning.targetHold
        local closeEnough = not chosen
            or lockedScore <= chosenScore * tuning.switchRatio + tuning.switchBonus
        if youngLock or closeEnough then chosen = lockedCandidate end
    end

    local chosenModel = chosen and chosen:FindFirstAncestorOfClass("Model")
    if chosenModel ~= aimLockedModel then
        aimLockedModel = chosenModel
        aimLockedAt = os.clock()
    end
    return chosen
end

local function isTargetStillValid(cam, myRoot)
    if not aimTarget or not aimTarget.Parent then return false end
    local model = aimTarget:FindFirstAncestorOfClass("Model")
    local cached = model and cache[model]
    if not model or not cached then return false end
    if cached.isNpc and not cfg.AimTargetNpcs then return false end
    if not cached.isNpc and not cfg.AimTargetPlayers then return false end
    local wp = Players:GetPlayerFromCharacter(model)
    if wp and aimWhitelist[wp.UserId] then return false end
    if wp and cfg.AimTeamCheck and wp.Team and wp.Team == player.Team then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local d3 = (aimTarget.Position - myRoot.Position).Magnitude
    if d3 > cfg.AimMaxDist then return false end

    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local breakMultiplier = cfg.AimRetention == "Hard" and 1.75 or 1.25
    local gunState = getGunAimState()
    if cfg.AimTargetPart == "Smart" and gunState and gunState.recovering then
        breakMultiplier = breakMultiplier + 0.5 * gunState.recoilFactor
    end
    local visiblePart = resolveAimPart(model, cam, center, cfg.AimFov * breakMultiplier)
    if visiblePart then
        aimTarget = visiblePart
        aimTargetVisible = true
        aimOccludedAt = nil
    elseif cfg.AimLosCheck then
        aimTargetVisible = false
        aimOccludedAt = aimOccludedAt or os.clock()
        local grace = cfg.AimRetention == "Hard" and 0.35 or 0.2
        if os.clock() - aimOccludedAt > grace then return false end
    end

    local screen, onScreen = cam:WorldToViewportPoint(currentAimPoint(aimTarget))
    if not onScreen then return false end
    local screenDistance = (Vector2.new(screen.X, screen.Y) - center).Magnitude
    if screenDistance > cfg.AimFov * breakMultiplier then return false end
    return true
end

-- Read-only weapon adaptation. The game exposes the equipped gun's recoil
-- profile through Storage.Modules.Weapons and its live spread through RateHeat.
-- We never write either value and never call a firing RemoteEvent.
local function equippedGun()
    local character = player.Character
    local tool = character and character:FindFirstChildWhichIsA("Tool")
    if not tool or tool:GetAttribute("Gun") ~= true then return nil end
    return tool
end

local function automaticGunProfile(tool)
    if not tool then return nil end
    local storage = ReplicatedStorage:FindFirstChild("Storage")
    local modules = storage and storage:FindFirstChild("Modules")
    local weapons = modules and modules:FindFirstChild("Weapons")
    local configModule = weapons and weapons:FindFirstChild(tool.Name, true)
    if not configModule or not configModule:IsA("ModuleScript") then return nil end

    local cached = gunProfileCache[configModule]
    if cached ~= nil then return cached or nil end

    local ok, data = pcall(require, configModule)
    if not ok or type(data) ~= "table" then
        gunProfileCache[configModule] = false
        return nil
    end

    local recoil = type(data.recoil) == "table" and data.recoil or {}
    local minPower = tonumber(recoil.minRecoilPower) or 1
    local maxPower = tonumber(recoil.maxRecoilPower) or minPower
    local punch = tonumber(recoil.recoilPunch) or 0
    local fireRate = tonumber(data.rate) or tonumber(tool:GetAttribute("FireRate")) or 600
    local damage = type(data.damage) == "table" and data.damage or {}
    local profile = {
        fireRate = math.max(fireRate, 1),
        recoveryTime = math.clamp(math.max(tonumber(recoil.punchRecover) or 0.15, 60 / math.max(fireRate, 1) * 1.35), 0.08, 0.55),
        recoilFactor = math.clamp(((minPower + maxPower) * 0.5) / 4 + punch * 0.65, 0.35, 2.5),
        aimRecoilReduction = math.max(tonumber(recoil.aimRecoilReduction) or 1, 1),
        penetrationDepth = math.max(tonumber(data.penetrate_depth) or 0, 0),
        pierceBudget = math.max(tonumber(damage[2] or damage[1]) or 0, 0) / 20,
        sniper = data.sniper == true,
        shotgun = data.shotgun == true or (tonumber(data.amountPerRound) or 1) > 1,
    }
    gunProfileCache[configModule] = profile
    return profile
end

getGunAimState = function()
    local tool = equippedGun()
    if not tool then return nil end
    local profile = automaticGunProfile(tool) or {
        fireRate = tonumber(tool:GetAttribute("FireRate")) or 600,
        recoveryTime = 0.16,
        recoilFactor = 1,
        penetrationDepth = 0,
        pierceBudget = 0,
        sniper = false,
        shotgun = false,
    }
    local heat = math.clamp(tonumber(tool:GetAttribute("RateHeat")) or 0, 0, 1)
    local character = player.Character
    local lastFired = tonumber(tool:GetAttribute("LastFired"))
    local runtime = gunRuntimeCache[tool]
    if not runtime then
        runtime = { heat = heat, lastFired = lastFired, firedAt = -math.huge }
        gunRuntimeCache[tool] = runtime
    end
    -- LastFired is not guaranteed to use os.clock's time domain. Detect a shot
    -- from attribute/heat changes and timestamp it locally instead.
    if (lastFired ~= nil and lastFired ~= runtime.lastFired) or heat > runtime.heat + 0.005 then
        runtime.firedAt = os.clock()
    end
    runtime.lastFired = lastFired
    runtime.heat = heat
    local shotAge = os.clock() - runtime.firedAt
    local sharedAim = type(shared) == "table" and shared.aim == true
    local ads = sharedAim
        or (character and (character:GetAttribute("aim") == true
            or character:GetAttribute("Aiming") == true
            or character:GetAttribute("ADS") == true))
        or tool:GetAttribute("aim") == true
        or tool:GetAttribute("Aiming") == true
        or tool:GetAttribute("ADS") == true
    local recoilFactor = profile.recoilFactor
    if cfg.AimTargetPart == "Smart" and ads then
        recoilFactor = recoilFactor / profile.aimRecoilReduction
    end
    return {
        tool = tool,
        heat = heat,
        recovering = shotAge >= 0 and shotAge <= profile.recoveryTime,
        recoilFactor = recoilFactor,
        penetrationDepth = profile.penetrationDepth,
        pierceBudget = profile.pierceBudget,
        ads = ads,
        sniper = profile.sniper,
        shotgun = profile.shotgun,
    }
end

-- Toggle the player nearest the crosshair in/out of the aim whitelist
local function whitelistNearestPlayer()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local best, bestSd = nil, cfg.AimFov
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local part = plr.Character:FindFirstChild("Head")
                or plr.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local d3 = myRoot and (part.Position - myRoot.Position).Magnitude or 0
                if d3 <= cfg.AimMaxDist then
                    local sc, on = cam:WorldToViewportPoint(part.Position)
                    if on then
                        local sd = (Vector2.new(sc.X, sc.Y) - center).Magnitude
                        if sd < bestSd then best, bestSd = plr, sd end
                    end
                end
            end
        end
    end
    if not best then
        if Window then pcall(function() Window:Notify({ Title = "Белый список", Description = "В текущем FOV игрок не найден", Lifetime = 3 }) end) end
        return
    end

    local id = best.UserId
    local msg
    if aimWhitelist[id] then
        aimWhitelist[id] = nil
        msg = best.DisplayName .. " удалён из белого списка"
    else
        aimWhitelist[id] = true
        msg = best.DisplayName .. " добавлен — прицел будет игнорировать"
    end
    saveWhitelist()
    if Window then
        pcall(function() Window:Notify({ Title = "Белый список", Description = msg, Lifetime = 3 }) end)
    end
end

local function updateAim(dt, cam, vpSize, myRoot)
    if cfg.AimEnabled and cfg.AimShowFov then
        fovCircle.Position = UDim2.fromOffset(vpSize.X / 2, vpSize.Y / 2)
        fovCircle.Size = UDim2.fromOffset(cfg.AimFov * 2, cfg.AimFov * 2)
        fovCircle.Visible = true
    else
        fovCircle.Visible = false
    end

    if not cfg.AimEnabled or not aimHolding then
        aimTarget = nil
        aimOccludedAt = nil
        aimTargetVisible = true
        aimLockedModel = nil
        aimLockedAt = 0
        return
    end
    if not mousemoverel then
        if not aimMouseWarningShown then
            aimMouseWarningShown = true
            if Window then pcall(function() Window:Notify({ Title = "Прицел", Description = "Исполнитель не поддерживает mousemoverel", Lifetime = 5 }) end) end
        end
        return
    end
    if not myRoot then
        aimTarget = nil
        aimOccludedAt = nil
        aimTargetVisible = true
        aimLockedModel = nil
        aimLockedAt = 0
        return
    end

    if cfg.AimRetention ~= "Off" and aimTarget then
        if not isTargetStillValid(cam, myRoot) then
            aimTarget = pickAimTarget(cam, vpSize, myRoot)
            aimTargetVisible = aimTarget ~= nil
            aimOccludedAt = nil
        end
    else
        aimTarget = pickAimTarget(cam, vpSize, myRoot)
        aimTargetVisible = aimTarget ~= nil
        aimOccludedAt = nil
    end

    if not aimTarget or not aimTarget.Parent then return end
    if cfg.AimLosCheck and not aimTargetVisible then return end

    -- Don't fight the menu cursor
    local menuOpen = false
    pcall(function() menuOpen = (Window and Window:GetState()) == true end)
    if menuOpen then return end

    -- Move the mouse toward the target. The game uses a Scriptable camera, so
    -- writing Camera.CFrame gets overwritten — instead we nudge the OS mouse and
    -- let the game's own camera turn. Closed loop: each frame we re-measure the
    -- gap and cover a fraction of it, so it converges regardless of sensitivity.
    local screen, onScreen = cam:WorldToViewportPoint(currentAimPoint(aimTarget))
    if not onScreen then return end
    local dx = screen.X - vpSize.X / 2
    local dy = screen.Y - vpSize.Y / 2
    local gunState = getGunAimState()
    local tuning = aimStyle()
    local deadzone = tuning.deadzone
    if cfg.AimTargetPart == "Smart" and gunState and not gunState.sniper then
        deadzone = deadzone + gunState.heat * tuning.spreadDeadzone
    end
    if math.sqrt(dx * dx + dy * dy) <= deadzone then return end
    -- Frame-rate independent: alpha is the fraction of the gap to cover this
    -- frame, normalised by dt so "Smoothness" feels the same at 30 or 144 FPS.
    local rate = 60 / math.max(tuning.smoothness, 1)
    local maxStep = tuning.maxStep
    if cfg.AimTargetPart == "Smart" and gunState and gunState.recovering then
        local strength = tuning.recoil * gunState.recoilFactor
        rate = rate * (1 + strength * 0.9)
        maxStep = math.min(maxStep * (1 + strength * 0.7), 120)
    end
    local alpha = 1 - math.exp(-(dt or 0.016) * rate)
    local moveX, moveY = dx * alpha, dy * alpha
    local moveMagnitude = math.sqrt(moveX * moveX + moveY * moveY)
    if moveMagnitude > maxStep and moveMagnitude > 0 then
        local scale = maxStep / moveMagnitude
        moveX, moveY = moveX * scale, moveY * scale
    end
    mousemoverel(moveX, moveY)
end

-- ============================================================
-- Scanning
-- ============================================================
local watchedEntityContainer = nil
local entityWatchConns = {}

local function watchEntityContainer(container)
    if not container or container == watchedEntityContainer then return end
    for _, c in ipairs(entityWatchConns) do pcall(function() c:Disconnect() end) end
    entityWatchConns = {}
    watchedEntityContainer = container
    entityWatchConns[#entityWatchConns + 1] = container.ChildAdded:Connect(function(child)
        task.defer(function()
            if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(child) then
                createEntry(child, true)
            end
        end)
    end)
    entityWatchConns[#entityWatchConns + 1] = container.ChildRemoved:Connect(function(child)
        if cache[child] then destroyEntry(child) end
    end)
end

local function scanEntities()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character and plr.Character:IsDescendantOf(workspace) then
            createEntry(plr.Character, false)
        end
    end
    local container = findEntityContainer()
    if container then
        watchEntityContainer(container)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                if not Players:GetPlayerFromCharacter(child) then
                    createEntry(child, true)
                end
            end
        end
    end
end

local function cleanStale()
    local toRemove = {}
    for model in pairs(cache) do
        local alive = false
        pcall(function() alive = model and model.Parent ~= nil end)
        if not alive then toRemove[#toRemove + 1] = model end
    end
    for _, model in ipairs(toRemove) do destroyEntry(model) end
end

-- ============================================================
-- Render loops
-- ============================================================
local renderConn
local scanTimer = 0
local questAccum = 0
local exfilRefreshAccum = 999
local intelAccum = 999
local doorAccum = 999

local function prepareEntityFrame(myRoot)
    local ranked = {}
    local playersNear, npcsNear = 0, 0
    local nearestSniper, sniperDist
    local nearestPlayerDist
    for model, d in pairs(cache) do
        d.highlightAllowed = false
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if entityTypeAllowed(model, d) and hrp and hum and hum.Health > 0 and model:IsDescendantOf(workspace) then
            local dist = myRoot and (hrp.Position - myRoot.Position).Magnitude or 0
            if dist <= entityMaxDistance(d) then
                ranked[#ranked + 1] = { d = d, dist = dist }
                if d.isNpc then
                    npcsNear = npcsNear + 1
                else
                    playersNear = playersNear + 1
                    if not nearestPlayerDist or dist < nearestPlayerDist then nearestPlayerDist = dist end
                end
                if d.isNpc and string.find(string.lower(model.Name), "sniper", 1, true) and (not sniperDist or dist < sniperDist) then
                    nearestSniper, sniperDist = model, dist
                end
            end
        end
    end
    table.sort(ranked, function(a, b) return a.dist < b.dist end)
    local lootHighlights = 0
    if cfg.LootEnabled then
        for _, highlight in ipairs(lootHlPool) do
            if highlight.Enabled then lootHighlights = lootHighlights + 1 end
        end
    end
    local budget = math.max(0, 30 - lootHighlights)
    for i = 1, math.min(#ranked, budget) do ranked[i].d.highlightAllowed = true end
    local threatParts = {string.format("Игроки: %d", playersNear), string.format("NPC: %d", npcsNear)}
    if nearestPlayerDist then threatParts[#threatParts + 1] = string.format("ближайший: %.0fм", nearestPlayerDist) end
    if nearestSniper then threatParts[#threatParts + 1] = string.format("⚠ снайпер: %.0fм", sniperDist) end
    nearbyLabel.Visible = cfg.Enabled and cfg.ThreatPanel
    nearbyLabel.Text = table.concat(threatParts, "  •  ")
    nearbyLabel.TextColor3 = (playersNear > 0 or nearestSniper) and Color3.fromRGB(255, 110, 90) or Color3.fromRGB(180, 220, 255)
end

local function onRender(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local vpSize = cam.ViewportSize

    scanTimer = scanTimer + dt
    if scanTimer >= 1.5 then
        scanTimer = 0
        if cfg.Enabled or cfg.AimEnabled then
            scanEntities()
            cleanStale()
        end
        if cfg.LootEnabled and lootDirty then rebuildLoot() end
        if not cfg.RaidTimer then detectContext() end
    end

    -- Update loot first so entity highlights receive only the actually free
    -- portion of Roblox's shared Highlight budget on this same frame.
    if cfg.LootEnabled then drawLoot(myRoot, cam, dt) else hideLoot() end

    if cfg.Enabled and myRoot then
        prepareEntityFrame(myRoot)
        for model, d in pairs(cache) do
            local s, drew = pcall(drawEntity, model, d, myRoot, cam, vpSize, dt)
            if not s or not drew then hideEntry(d) end
        end
    else
        for _, d in pairs(cache) do hideEntry(d) end
        nearbyLabel.Visible = false
    end

    if cfg.ExfilESP then
        exfilRefreshAccum = exfilRefreshAccum + dt
        if exfilRefreshAccum >= 0.5 then
            exfilRefreshAccum = 0
            findExfils()
        end
        drawExfils(myRoot, cam)
    else
        hideExfils()
    end
    if cfg.RaidTimer then updateRaidTimer(dt) else raidPill.Visible = false end

    local wantsIntel = cfg.InventoryHelper or cfg.QuestHelper
        or (cfg.LootEnabled and cfg.LootShowAdvice) or (cfg.DoorESP and cfg.DoorCheckKeys)
    if wantsIntel then
        intelAccum = intelAccum + dt
        if intelAccum >= 0.75 then
            intelAccum = 0
            if cfg.QuestHelper then
                pcall(rebuildQuestPlan)
            else
                activeQuestItems = {}
                questPlannerLabel.Visible = false
            end
            pcall(scanInventory)
        end
    else
        inventoryLabel.Visible = false
        questPlannerLabel.Visible = false
    end

    if cfg.DoorESP then
        doorAccum = doorAccum + dt
        if doorAccum >= 1 then
            doorAccum = 0
            pcall(refreshDoors)
        end
        drawDoors(myRoot, cam)
    else
        hideDoors()
    end

    if cfg.QuestHelper then
        questAccum = questAccum + dt
        if questAccum >= 0.35 then
            questAccum = 0
            pcall(scanQuestItems)
        end
    end
end

local AIM_BIND = "__hakoAimStep"
local aimBound = false

local function onAimStep(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    updateAim(dt, cam, cam.ViewportSize, myRoot)
end

local function bindAim()
    if aimBound then return end
    local ok = pcall(function()
        RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Character.Value + 1, onAimStep)
    end)
    if ok then aimBound = true end
end

local function unbindAim()
    if not aimBound then return end
    pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
    aimBound = false
    fovCircle.Visible = false
    aimTarget = nil
end

local function anyActive()
    return cfg.Enabled or cfg.AimEnabled or cfg.LootEnabled or cfg.QuestHelper or cfg.ExfilESP or cfg.RaidTimer
        or cfg.InventoryHelper or cfg.DoorESP
end

local function startRender()
    if renderConn then return end
    scanTimer = 0
    if cfg.Enabled or cfg.AimEnabled then scanEntities() end
    if cfg.LootEnabled then rebuildLoot() end
    renderConn = RunService.RenderStepped:Connect(onRender)
end

local function stopRender()
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
    for _, d in pairs(cache) do hideEntry(d) end
    hideExfils()
    hideLoot()
    hideDoors()
    raidPill.Visible = false
    nearbyLabel.Visible = false
    contextLabel.Visible = false
    inventoryLabel.Visible = false
    questPlannerLabel.Visible = false
end

local function ensureRender()
    if anyActive() then startRender() else stopRender() end
    if cfg.AimEnabled then bindAim() else unbindAim() end
end

-- ============================================================
-- Player tracking
-- ============================================================
local function onCharAdded(char)
    task.wait(1)
    if (cfg.Enabled or cfg.AimEnabled) and char and char.Parent and char:IsDescendantOf(workspace) then
        createEntry(char, false)
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= player then
        conns[#conns + 1] = plr.CharacterAdded:Connect(onCharAdded)
    end
end
conns[#conns + 1] = Players.PlayerAdded:Connect(function(plr)
    if plr ~= player then
        conns[#conns + 1] = plr.CharacterAdded:Connect(onCharAdded)
    end
end)
conns[#conns + 1] = Players.PlayerRemoving:Connect(function(plr)
    if plr.Character and cache[plr.Character] then
        destroyEntry(plr.Character)
    end
end)

-- ============================================================
-- Cleanup
-- ============================================================
local cleanedUp = false
local function cleanup(fromWindow)
    if cleanedUp then return end
    cleanedUp = true
    pcall(restoreMenuMouse)
    unbindAim()
    stopRender()
    restoreFullbright()
    clearQuestHL()
    pcall(function() espGui:Destroy() end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(entityWatchConns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(lootWatchConns) do pcall(function() c:Disconnect() end) end
    conns = {}
    entityWatchConns = {}
    lootWatchConns = {}
    cache = {}
    if getgenv then
        getgenv().__HAKO_CLEANUP = nil
        getgenv().__HAKO_CONFIG_API = nil
    end
    if Window and not fromWindow then pcall(function() Window:Unload() end) end
end

if getgenv then getgenv().__HAKO_CLEANUP = cleanup end

-- ============================================================
-- MacLib UI
-- ============================================================
local menuUIS = game:GetService("UserInputService")
local menuWasOpen = false
local savedMouseIcon = menuUIS.MouseIconEnabled
local savedMouseBehavior = menuUIS.MouseBehavior

Window = MacLib:Window({
    Title = "hako",
    Subtitle = "ESP • Прицел • Лут",
    Size = UDim2.fromOffset(780, 580),
    DragStyle = 1,
    ShowUserInfo = true,
    Keybind = Enum.KeyCode.RightControl,
    AcrylicBlur = false,  -- blur needs Plugin capability some executors' inject thread lacks
})
MacLib.SaveConfig = MacLib.__HakoSaveConfig or MacLib.SaveConfig
MacLib.LoadConfig = MacLib.__HakoLoadConfig or MacLib.LoadConfig
Window.onUnloaded(function()
    pcall(cleanup, true)
end)

-- Free the mouse while the menu is open (first-person games lock it to center)
do
    restoreMenuMouse = function()
        if menuWasOpen then
            pcall(function()
                menuUIS.MouseIconEnabled = savedMouseIcon
                menuUIS.MouseBehavior = savedMouseBehavior
            end)
        end
        menuWasOpen = false
    end

    conns[#conns + 1] = RunService.Heartbeat:Connect(function()
        local ok, open = pcall(function() return Window:GetState() end)
        open = ok and open == true
        if open then
            if not menuWasOpen then
                menuWasOpen = true
            end
            if not menuUIS.MouseIconEnabled then menuUIS.MouseIconEnabled = true end
            if menuUIS.MouseBehavior ~= Enum.MouseBehavior.Default then
                menuUIS.MouseBehavior = Enum.MouseBehavior.Default
            end
        elseif menuWasOpen then
            restoreMenuMouse()
        else
            -- Keep the snapshot current while the game owns the mouse. This
            -- preserves lobby cursor state as well as raid LockCenter state.
            savedMouseIcon = menuUIS.MouseIconEnabled
            savedMouseBehavior = menuUIS.MouseBehavior
        end
    end)
end

local Tabs = Window:TabGroup()

-- ---------- ESP TAB ----------
do
local espTab = Tabs:Tab({ Name = "ESP" })
local espL = espTab:Section({ Side = "Left" })
local espR = espTab:Section({ Side = "Right" })

espL:Header({ Name = "Основное" })
espL:Toggle({ Name = "Включить ESP", Default = guiDefault("Enabled", false),
    Callback = function(v) cfg.Enabled = v; ensureRender() end }, "espEnabled")
espL:Header({ Name = "Цели" })
espL:Toggle({ Name = "ESP игроков", Default = guiDefault("PlayerESP", true),
    Callback = function(v) cfg.PlayerESP = v end }, "espPlayers")
espL:Toggle({ Name = "ESP NPC", Default = guiDefault("NpcESP", true),
    Callback = function(v) cfg.NpcESP = v end }, "espNpcs")
espL:Toggle({ Name = "Команда игроков", Default = guiDefault("TeamCheck", false),
    Callback = function(v) cfg.TeamCheck = v end }, "espTeam")
espL:Toggle({ Name = "Видимость NPC", Default = guiDefault("NpcVisibleCheck", true),
    Callback = function(v) cfg.NpcVisibleCheck = v end }, "espNpcVis")
guiDefault("NpcNameFilter", "")
espL:Input({ Name = "Фильтр имени NPC", Placeholder = "пусто = все", AcceptedCharacters = "All",
    Callback = function(v) cfg.NpcNameFilter = tostring(v or "") end,
    onChanged = function(v) cfg.NpcNameFilter = tostring(v or "") end }, "espNpcFilter")
espL:Header({ Name = "Дальность" })
espL:Toggle({ Name = "Раздельная дальность", Default = guiDefault("SeparateRanges", false),
    Callback = function(v) cfg.SeparateRanges = v end }, "espSeparateRange")
espL:Slider({ Name = "Общая дистанция", Default = guiDefault("MaxDistance", 500),
    Minimum = 50, Maximum = 1000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.MaxDistance = v end }, "espMaxDist")
espL:Slider({ Name = "Дистанция игроков", Default = guiDefault("PlayerMaxDistance", 500),
    Minimum = 50, Maximum = 1000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.PlayerMaxDistance = v end }, "espPlayerMaxDist")
espL:Slider({ Name = "Дистанция NPC", Default = guiDefault("NpcMaxDistance", 250),
    Minimum = 50, Maximum = 1000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.NpcMaxDistance = v end }, "espNpcMaxDist")

espR:Header({ Name = "Отображение" })
guiDefault("VisualMode", "Outline")
espR:Dropdown({ Name = "Режим подсветки", Options = { "Выключено", "Контур", "Заливка", "Контур + заливка" },
    Default = 2, Multi = false, Callback = function(v)
        cfg.VisualMode = ({["Выключено"]="Off", ["Контур"]="Outline", ["Заливка"]="Fill", ["Контур + заливка"]="Both", ["Off"]="Off", ["Outline"]="Outline", ["Fill"]="Fill", ["Both"]="Both"})[v] or "Outline"
    end }, "espVisualMode")
espR:Slider({ Name = "Прозрачность заливки", Default = guiDefault("ChamsOpacity", 55),
    Minimum = 0, Maximum = 100, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.ChamsOpacity = v end }, "espChamsOp")
guiDefault("DetailMode", "Full")
espR:Dropdown({ Name = "Уровень информации", Options = { "Минимальный", "Боевой", "Полный" },
    Default = 3, Multi = false, Callback = function(v)
        cfg.DetailMode = ({["Минимальный"]="Minimal", ["Боевой"]="Combat", ["Полный"]="Full", ["Minimal"]="Minimal", ["Combat"]="Combat", ["Full"]="Full"})[v] or "Full"
    end }, "espDetailMode")
espR:Toggle({ Name = "Линии до игроков", Default = guiDefault("Tracers", false),
    Callback = function(v) cfg.Tracers = v end }, "espTracers")
espR:Toggle({ Name = "Затухание по дистанции", Default = guiDefault("DistanceFade", true),
    Callback = function(v) cfg.DistanceFade = v end }, "espFade")
espR:Header({ Name = "Цвета" })
espR:Colorpicker({ Name = "Видимая цель", Default = guiDefault("VisibleColor", Color3.fromRGB(70, 255, 120)),
    Callback = function(c) cfg.VisibleColor = c end }, "colVisible")
espR:Colorpicker({ Name = "Цель за стеной", Default = guiDefault("HiddenColor", Color3.fromRGB(255, 55, 55)),
    Callback = function(c) cfg.HiddenColor = c end }, "colHidden")
espR:Colorpicker({ Name = "NPC", Default = guiDefault("NpcColor", Color3.fromRGB(255, 150, 50)),
    Callback = function(c) cfg.NpcColor = c end }, "colNpc")
end

-- ---------- LOOT TAB ----------
do
local lootTab = Tabs:Tab({ Name = "Лут" })
local lootL = lootTab:Section({ Side = "Left" })
local lootR = lootTab:Section({ Side = "Right" })

lootL:Header({ Name = "ESP лута" })
lootL:Toggle({ Name = "Включить ESP лута", Default = guiDefault("LootEnabled", false),
    Callback = function(v) cfg.LootEnabled = v; if v then rebuildLoot() end; ensureRender() end }, "lootEnabled")
lootL:Slider({ Name = "Максимальная дистанция", Default = guiDefault("LootMaxDist", 120),
    Minimum = 20, Maximum = 300, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.LootMaxDist = v end }, "lootMaxDist")
lootL:Toggle({ Name = "Названия и дистанция", Default = guiDefault("LootNames", true),
    Callback = function(v) cfg.LootNames = v end }, "lootNames")
guiDefault("LootSort", "Distance")
lootL:Dropdown({ Name = "Сортировка", Options = { "Расстояние", "Цена", "Цена/кг" },
    Default = 1, Multi = false, Callback = function(v) cfg.LootSort = ({["Расстояние"]="Distance", ["Цена"]="Price", ["Цена/кг"]="Price/kg", ["Distance"]="Distance", ["Price"]="Price", ["Price/kg"]="Price/kg"})[v] or "Distance" end }, "lootSort")
lootL:Header({ Name = "Ценовые фильтры" })
lootL:Slider({ Name = "Минимальная цена", Default = guiDefault("LootMinPrice", 0),
    Minimum = 0, Maximum = 50000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.LootMinPrice = v end }, "lootMinPrice")
lootL:Slider({ Name = "Минимальная цена за кг", Default = guiDefault("LootMinPricePerKg", 0),
    Minimum = 0, Maximum = 25000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.LootMinPricePerKg = v end }, "lootMinPpk")

lootR:Header({ Name = "Контейнеры" })
lootR:Toggle({ Name = "Элитные: сейфы/военные", Default = guiDefault("LootElite", true),
    Callback = function(v) cfg.LootElite = v end }, "lootElite")
lootR:Toggle({ Name = "Ценные: оружие/мед.", Default = guiDefault("LootHigh", true),
    Callback = function(v) cfg.LootHigh = v end }, "lootHigh")
lootR:Toggle({ Name = "Средние: кейсы/разное", Default = guiDefault("LootMid", false),
    Callback = function(v) cfg.LootMid = v end }, "lootMid")
lootR:Toggle({ Name = "Обычные (мебель)", Default = guiDefault("LootTrash", false),
    Callback = function(v) cfg.LootTrash = v end }, "lootTrash")
lootR:Header({ Name = "Прочее" })
lootR:Toggle({ Name = "Предметы на земле", Default = guiDefault("LootItems", true),
    Callback = function(v) cfg.LootItems = v end }, "lootItems")
lootR:Toggle({ Name = "Тела", Default = guiDefault("LootBodies", true),
    Callback = function(v) cfg.LootBodies = v end }, "lootBodies")
lootR:Toggle({ Name = "Показывать цену", Default = guiDefault("LootShowPrice", true),
    Callback = function(v) cfg.LootShowPrice = v end }, "lootPrice")
lootR:Toggle({ Name = "Показывать категорию", Default = guiDefault("LootShowCategory", false),
    Callback = function(v) cfg.LootShowCategory = v end }, "lootCategory")
end

-- ---------- HELPERS TAB ----------
do
local helperTab = Tabs:Tab({ Name = "Помощники" })
local helperL = helperTab:Section({ Side = "Left" })
local helperR = helperTab:Section({ Side = "Right" })

helperL:Header({ Name = "Рейд" })
helperL:Toggle({ Name = "Помощник по инвентарю", Default = guiDefault("InventoryHelper", true),
    Callback = function(v)
        cfg.InventoryHelper = v
        if not v then inventoryLabel.Visible = false end
        ensureRender()
    end }, "inventoryHelper")
helperL:Toggle({ Name = "Квестовый помощник", Default = guiDefault("QuestHelper", true),
    Callback = function(v)
        cfg.QuestHelper = v
        if not v then
            activeQuestItems = {}
            questPlannerLabel.Visible = false
            clearQuestHL()
        end
        ensureRender()
    end }, "questHelper")
helperL:Toggle({ Name = "Панель угроз", Default = guiDefault("ThreatPanel", true),
    Callback = function(v) cfg.ThreatPanel = v end }, "espThreatPanel")

helperR:Header({ Name = "Информация о луте" })
helperR:Toggle({ Name = "Список ценного лута", Default = guiDefault("LootList", true),
    Callback = function(v) cfg.LootList = v end }, "lootList")
helperR:Toggle({ Name = "Советы над предметами", Default = guiDefault("LootShowAdvice", false),
    Callback = function(v) cfg.LootShowAdvice = v; ensureRender() end }, "lootAdvice")
helperR:Label({ Text = "Подсказки появляются только при включённом ESP лута." })
end

-- ---------- WORLD TAB ----------
do
local worldTab = Tabs:Tab({ Name = "Мир" })
local worldL = worldTab:Section({ Side = "Left" })
local worldR = worldTab:Section({ Side = "Right" })

worldL:Header({ Name = "Выходы" })
worldL:Toggle({ Name = "ESP выходов", Default = guiDefault("ExfilESP", true),
    Callback = function(v) cfg.ExfilESP = v; ensureRender() end }, "worldExfil")
worldL:Toggle({ Name = "Доступные выходы", Default = guiDefault("ExfilOnlyAvailable", true),
    Callback = function(v) cfg.ExfilOnlyAvailable = v end }, "worldExfilAvailable")
worldL:Toggle({ Name = "Закрытые выходы", Default = guiDefault("ExfilShowLocked", true),
    Callback = function(v) cfg.ExfilShowLocked = v end }, "worldExfilLocked")
worldL:Toggle({ Name = "Ближайший выход", Default = guiDefault("ExfilNearest", true),
    Callback = function(v) cfg.ExfilNearest = v end }, "worldExfilNearest")
worldL:Header({ Name = "Рейд" })
worldL:Toggle({ Name = "Таймер рейда", Default = guiDefault("RaidTimer", true),
    Callback = function(v) cfg.RaidTimer = v; ensureRender() end }, "worldTimer")
worldL:Toggle({ Name = "Предупреждения таймера", Default = guiDefault("RaidWarnings", true),
    Callback = function(v) cfg.RaidWarnings = v end }, "worldWarnings")
worldL:Toggle({ Name = "К/С сервера и 2XP", Default = guiDefault("ServerInfo", true),
    Callback = function(v)
        cfg.ServerInfo = v
        if not v then contextLabel.Visible = false end
    end }, "worldServerInfo")
worldL:Toggle({ Name = "Авто: лобби / рейд", Default = guiDefault("ContextAuto", true),
    Callback = function(v) cfg.ContextAuto = v end }, "worldContext")

worldR:Header({ Name = "Двери" })
worldR:Toggle({ Name = "ESP дверей", Default = guiDefault("DoorESP", true),
    Callback = function(v) cfg.DoorESP = v; if not v then hideDoors() end; ensureRender() end }, "doorEsp")
worldR:Slider({ Name = "Дальность дверей", Default = guiDefault("DoorMaxDist", 90),
    Minimum = 20, Maximum = 200, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.DoorMaxDist = v end }, "doorDistance")
worldR:Toggle({ Name = "Только важные двери", Default = guiDefault("DoorOnlyInteresting", true),
    Callback = function(v) cfg.DoorOnlyInteresting = v end }, "doorInteresting")
worldR:Toggle({ Name = "Проверять ключи", Default = guiDefault("DoorCheckKeys", true),
    Callback = function(v) cfg.DoorCheckKeys = v; ensureRender() end }, "doorKeys")
worldR:Header({ Name = "Окружение" })
worldR:Toggle({ Name = "Полная яркость", Default = guiDefault("Fullbright", false),
    Callback = function(v) cfg.Fullbright = v; if v then applyFullbright() else restoreFullbright() end end }, "worldFullbright")
end

-- ---------- AIM TAB ----------
do
local aimTab = Tabs:Tab({ Name = "Прицел" })
local aimLft = aimTab:Section({ Side = "Left" })
local aimRgt = aimTab:Section({ Side = "Right" })

aimLft:Header({ Name = "Основное" })
aimLft:Toggle({ Name = "Включить помощь", Default = guiDefault("AimEnabled", false),
    Callback = function(v) cfg.AimEnabled = v; ensureRender() end }, "aimEnabled")
aimLft:Keybind({ Name = "Клавиша Aim (удерж.)", Default = Enum.UserInputType.MouseButton2,
    onBindHeld = function(held) aimHolding = held end }, "aimKey")
aimLft:Header({ Name = "Область наведения" })
aimLft:Toggle({ Name = "Показывать круг FOV", Default = guiDefault("AimShowFov", true),
    Callback = function(v) cfg.AimShowFov = v end }, "aimShowFov")
aimLft:Slider({ Name = "Радиус FOV", Default = guiDefault("AimFov", 80),
    Minimum = 10, Maximum = 300, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.AimFov = v end }, "aimFov")
aimLft:Slider({ Name = "Дальность Aim", Default = guiDefault("AimMaxDist", 1500),
    Minimum = 50, Maximum = 5000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.AimMaxDist = v end }, "aimMaxDist")
aimLft:Header({ Name = "Стиль наведения" })
guiDefault("AimStyle", "Legit")
aimLft:Dropdown({ Name = "Режим Aim", Options = { "Legit", "Rage", "Super Rage" },
    Default = 1, Multi = false, Callback = function(v)
        cfg.AimStyle = ({["Legit"]="Legit", ["Rage"]="Rage", ["Super Rage"]="SuperRage", ["SuperRage"]="SuperRage"})[v] or "Legit"
    end }, "aimStyle")
aimLft:Label({ Text = "Legit — плавно и естественно" })
aimLft:Label({ Text = "Rage — быстро и жёстко" })
aimLft:Label({ Text = "Super Rage — максимально резко" })

aimRgt:Header({ Name = "Выбор цели" })
guiDefault("AimTargetPart", "Smart")
aimRgt:Dropdown({ Name = "Точка Aim", Options = { "Умная", "Голова", "Корпус", "Центр тела" },
    Default = 1, Multi = false, Callback = function(v) cfg.AimTargetPart = ({["Умная"]="Smart", ["Голова"]="Head", ["Корпус"]="Body", ["Центр тела"]="Center", ["Smart"]="Smart", ["Head"]="Head", ["Body"]="Body", ["Torso"]="Body", ["Center"]="Center", ["HumanoidRootPart"]="Center"})[v] or "Smart" end }, "aimPart")
guiDefault("AimPriority", "Crosshair")
aimRgt:Dropdown({ Name = "Приоритет", Options = { "Ближе к прицелу", "По дистанции", "Меньше здоровья" },
    Default = 1, Multi = false, Callback = function(v) cfg.AimPriority = ({["Ближе к прицелу"]="Crosshair", ["По дистанции"]="Distance", ["Меньше здоровья"]="Lowest HP", ["Crosshair"]="Crosshair", ["Distance"]="Distance", ["Lowest HP"]="Lowest HP"})[v] or "Crosshair" end }, "aimPriority")
aimRgt:Toggle({ Name = "Целиться в игроков", Default = guiDefault("AimTargetPlayers", true),
    Callback = function(v) cfg.AimTargetPlayers = v end }, "aimTgtPlr")
aimRgt:Toggle({ Name = "Целиться в NPC", Default = guiDefault("AimTargetNpcs", true),
    Callback = function(v) cfg.AimTargetNpcs = v end }, "aimTgtNpc")
aimRgt:Toggle({ Name = "Игроки важнее NPC", Default = guiDefault("AimPreferPlayers", true),
    Callback = function(v) cfg.AimPreferPlayers = v end }, "aimPreferPlayers")
aimRgt:Header({ Name = "Проверки и удержание" })
aimRgt:Toggle({ Name = "Проверять команду", Default = guiDefault("AimTeamCheck", true),
    Callback = function(v) cfg.AimTeamCheck = v end }, "aimTeam")
aimRgt:Toggle({ Name = "Проверка видимости", Default = guiDefault("AimLosCheck", true),
    Callback = function(v) cfg.AimLosCheck = v end }, "aimLos")
guiDefault("AimRetention", "Soft")
aimRgt:Dropdown({ Name = "Удержание цели", Options = { "Выключено", "Мягкое", "Жёсткое" },
    Default = 2, Multi = false, Callback = function(v) cfg.AimRetention = ({["Выключено"]="Off", ["Мягкое"]="Soft", ["Жёсткое"]="Hard", ["Off"]="Off", ["Soft"]="Soft", ["Hard"]="Hard"})[v] or "Soft" end }, "aimRetention")

aimRgt:Header({ Name = "Белый список" })
aimRgt:Keybind({ Name = "Игнорировать цель", Default = Enum.UserInputType.MouseButton3,
    Callback = function() whitelistNearestPlayer() end }, "aimWlKey")
aimRgt:Button({ Name = "Очистить белый список", Callback = function()
    aimWhitelist = {}
    saveWhitelist()
    if Window then pcall(function() Window:Notify({ Title = "Белый список", Description = "Очищен", Lifetime = 3 }) end) end
end })
end

-- ---------- CONFIG TAB ----------
do
local cfgTab = Tabs:Tab({ Name = "Настройки" })
cfgTab:InsertConfigSection("Left")
local cfgR = cfgTab:Section({ Side = "Right" })
cfgR:Header({ Name = "Скрипт" })
cfgR:Label({ Text = "Визуалы не меняют workspace; гарантии обхода античита нет." })
cfgR:Label({ Text = "Прицел двигает мышь. Без хуков и вызова RemoteEvent." })
cfgR:Divider()
cfgR:Button({ Name = "Выгрузить скрипт", Callback = function() cleanup() end })
end

if getgenv then
    getgenv().__HAKO_CONFIG_API = {
        Save = function(name) return MacLib:SaveConfig(name) end,
        Load = function(name) return MacLib:LoadConfig(name) end,
        List = function() return MacLib:RefreshConfigList() end,
        Delete = function(name)
            if not (delfile and isfile) then return false, "Delete API unavailable" end
            local path = MacLib.Folder .. "/settings/" .. tostring(name) .. ".json"
            if not isfile(path) then return true end
            local ok, err = pcall(delfile, path)
            return ok, ok and nil or tostring(err)
        end,
        Count = function()
            local count = 0
            for _ in pairs(MacLib.Options or {}) do count = count + 1 end
            return count
        end,
        Get = function(flag)
            local option = MacLib.Options and MacLib.Options[flag]
            if not option then return nil end
            if option.Class == "Toggle" then return option:GetState() end
            if option.Class == "Slider" then return option:GetValue() end
            if option.Class == "Input" then return option.GetInput and option:GetInput() or option.Text end
            if option.Class == "Keybind" then
                local bind = option:GetBind()
                return bind and bind.Name or nil
            end
            return option.Value
        end,
        Set = function(flag, value)
            local option = MacLib.Options and MacLib.Options[flag]
            if not option then return false, "Unknown option" end
            if option.Class == "Toggle" then
                option:UpdateState(value == true)
            elseif option.Class == "Slider" then
                option:UpdateValue(tonumber(value))
                if option.Settings and option.Settings.Callback then
                    option.Settings.Callback(option:GetValue())
                end
            elseif option.Class == "Input" then
                option:UpdateText(tostring(value or ""))
            elseif option.Class == "Dropdown" then
                option:UpdateSelection(value)
            else
                return false, "Unsupported option class"
            end
            return true
        end,
    }
end

Window:Notify({
    Title = "hako",
    Description = "Загружено. RightCtrl открывает и закрывает меню.",
    Lifetime = 5,
})

task.spawn(function()
    pcall(function() MacLib:LoadAutoLoadConfig() end)
    if cfg.Fullbright then applyFullbright() end
    ensureRender()
end)
