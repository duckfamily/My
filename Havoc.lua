--[[
    hako  —  Beautiful GUI ESP + Aim + Loot  (MacLib)
    Extraction shooter build.

    Rendering: instance-based GUI parented into gethui() (the executor's hidden
    UI container). The game's anti-cheat is an ordinary game LocalScript — it
    has no executor functions and cannot read gethui() or CoreGui, so this UI is
    invisible to it (verified: our ScreenGui is NOT under workspace). This lets
    us use full Roblox UI — Highlight outline/chams, floating billboard labels
    and a gradient health bar — while staying unscannable.

    Safety:
      * Visuals live in gethui(), never under workspace / the enemy character.
      * No hooks (the "/" hook-detector stays quiet).
      * Aim nudges the OS mouse (mousemoverel) — no camera/CFrame writes, no
        remotes; the game's own Scriptable camera turns naturally.
      * Never touches WalkSpeed / JumpPower / position (server MovementAnticheat).
      * Chams use a Highlight in gethui() adorneed to the target — the character
        itself gets no new instances, so a descendant scan finds nothing.
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

local player = Players.LocalPlayer
local Window  -- forward declaration (used by aim + cleanup)

-- ============================================================
-- Library
-- ============================================================
local okLib, MacLib = pcall(function()
    return loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()
end)
if not okLib or not MacLib then
    warn("[HAKO] Failed to load MacLib: " .. tostring(MacLib))
    return
end
pcall(function() MacLib:SetFolder("hako") end)

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
-- Config
-- ============================================================
local cfg = {
    -- ESP
    Enabled = false,
    PlayerESP = true,
    NpcESP = true,
    Outline = true,
    Names = true,
    HealthBar = true,
    Distance = true,
    Weapon = true,
    Tracers = false,
    Chams = false,
    ChamsOpacity = 55,     -- % fill opacity
    TeamCheck = false,
    MaxDistance = 500,
    VisibleColor = Color3.fromRGB(70, 255, 120),
    HiddenColor = Color3.fromRGB(255, 55, 55),
    NpcColor = Color3.fromRGB(255, 150, 50),
    -- Loot
    LootEnabled = false,
    LootElite = true,
    LootHigh = true,
    LootMid = false,
    LootTrash = false,
    LootItems = true,
    LootBodies = true,
    LootNames = true,
    LootMaxDist = 120,
    -- World
    ExfilESP = true,
    RaidTimer = true,
    Fullbright = false,
    QuestHL = true,
    -- Aim
    AimEnabled = false,
    AimFov = 80,
    AimSmoothness = 5,
    AimTargetPart = "Head",
    AimTargetPlayers = true,
    AimTargetNpcs = true,
    AimTeamCheck = true,
    AimLosCheck = true,
    AimStickyTarget = true,
    AimShowFov = true,
    AimMaxDist = 300,
}

local aimHolding = false

-- ============================================================
-- Colors
-- ============================================================
local WHITE     = Color3.new(1, 1, 1)
local BLACK     = Color3.new(0, 0, 0)
local EXFIL_COL = Color3.fromRGB(0, 255, 128)
local EXFIL_SUB = Color3.fromRGB(160, 255, 190)
local TIMER_COL = Color3.fromRGB(255, 220, 100)
local FOV_COL   = Color3.fromRGB(255, 255, 255)

local LOOT_COL = {
    Elite = Color3.fromRGB(255, 215, 0),
    High  = Color3.fromRGB(200, 120, 255),
    Mid   = Color3.fromRGB(90, 200, 255),
    Trash = Color3.fromRGB(150, 150, 150),
}
local ITEM_COL = Color3.fromRGB(120, 255, 130)
local BODY_COL = Color3.fromRGB(230, 230, 230)

-- Health -> color (green full, yellow half, red low). Color indicates HP level.
local HP_RED = Color3.fromRGB(255, 45, 45)
local HP_YEL = Color3.fromRGB(255, 210, 50)
local HP_GRN = Color3.fromRGB(60, 255, 70)
local function hpColor(frac)
    if frac >= 0.5 then return HP_YEL:Lerp(HP_GRN, (frac - 0.5) * 2) end
    return HP_RED:Lerp(HP_YEL, frac * 2)
end

-- ============================================================
-- GUI factory helpers
-- ============================================================
local function mkCorner(parent, r)
    return newInst("UICorner", { CornerRadius = UDim.new(0, r or 5) }, parent)
end

local function mkStroke(parent, color, thick, transparency)
    return newInst("UIStroke", {
        Color = color or BLACK,
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
        TextColor3 = WHITE,
        TextStrokeColor3 = BLACK,       -- glyph outline (no border box)
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
        FillColor = WHITE,
        OutlineColor = WHITE,
        FillTransparency = 1,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, espGui)

    -- Info billboard: name / distance+hp / weapon (auto-tracks the head in 3D)
    local infoBB = newInst("BillboardGui", {
        Size = UDim2.fromOffset(240, 54),
        StudsOffset = Vector3.new(0, 2.7, 0),
        AlwaysOnTop = true,
        MaxDistance = 6000,
        Enabled = false,
    }, espGui)
    d.infoBB = infoBB
    d.nameLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 0),
        Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = WHITE, Text = "",
        TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.15,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoBB)
    d.detailLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Position = UDim2.fromOffset(0, 19),
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(215, 215, 215), Text = "",
        TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.2,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, infoBB)
    d.weapLabel = newInst("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Position = UDim2.fromOffset(0, 35),
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(255, 200, 90), Text = "",
        TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.2,
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
    mkStroke(hpBg, BLACK, 1.4, 0.4)
    local hpFill = newInst("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0, BackgroundColor3 = WHITE,
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
        BackgroundColor3 = WHITE, BorderSizePixel = 0,
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
-- Line-of-sight raycasting (shared: visibility check + aim)
-- ============================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local _rayFilter = {}
local function refreshRayFilter()
    local n = 0
    local ch = player.Character
    if ch then n = n + 1; _rayFilter[n] = ch end
    local cam = workspace.CurrentCamera
    if cam then n = n + 1; _rayFilter[n] = cam end
    for i = n + 1, #_rayFilter do _rayFilter[i] = nil end
    rayParams.FilterDescendantsInstances = _rayFilter
end

local function hasLineOfSight(cam, targetPart)
    refreshRayFilter()
    local origin = cam.CFrame.Position
    local result = workspace:Raycast(origin, targetPart.Position - origin, rayParams)
    if not result then return true end
    if result.Instance and result.Instance:IsDescendantOf(targetPart.Parent) then return true end
    return false
end

-- Visible if head OR torso is unobstructed (behind full cover => false)
local function computeVisible(model, cam)
    local head = model:FindFirstChild("Head")
    if head and hasLineOfSight(cam, head) then return true end
    local torso = model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
    if torso and hasLineOfSight(cam, torso) then return true end
    return false
end

-- ============================================================
-- Draw one entity
-- ============================================================
local function drawEntity(model, d, myRoot, cam, vpSize, dt)
    local typeEnabled
    if d.isNpc then typeEnabled = cfg.NpcESP else typeEnabled = cfg.PlayerESP end
    if not typeEnabled then return false end

    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end
    if not model:IsDescendantOf(workspace) then return false end
    local head = model:FindFirstChild("Head") or hrp

    if not d.isNpc and cfg.TeamCheck then
        local plr = Players:GetPlayerFromCharacter(model)
        if plr and plr.Team and plr.Team == player.Team then return false end
    end

    local dist = myRoot and (hrp.Position - myRoot.Position).Magnitude or 0
    if dist > cfg.MaxDistance then return false end

    local hrpS, onScreen = cam:WorldToViewportPoint(hrp.Position)
    -- Off-screen (behind us / outside viewport): nothing renders anyway, so skip
    -- the raycasts, billboard updates and projections entirely.
    if not onScreen then
        hideEntry(d)
        return true
    end

    local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
    local col
    if d.isNpc then
        col = cfg.NpcColor
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
    if cfg.Outline or cfg.Chams then
        d.hl.OutlineColor = col
        d.hl.OutlineTransparency = cfg.Outline and 0 or 1
        d.hl.FillColor = col
        d.hl.FillTransparency = cfg.Chams and (1 - cfg.ChamsOpacity / 100) or 1
        d.hl.Enabled = true
    else
        d.hl.Enabled = false
    end

    -- Info billboard
    if cfg.Names or cfg.Distance or cfg.HealthBar or cfg.Weapon then
        d.infoBB.Adornee = head
        d.infoBB.Enabled = true

        if cfg.Names then
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

        if cfg.Distance or cfg.HealthBar then
            local parts = {}
            if cfg.Distance then parts[#parts + 1] = string.format("%.0fm", dist) end
            if cfg.HealthBar then parts[#parts + 1] = string.format("%d hp", math.floor(hum.Health)) end
            d.detailLabel.Text = table.concat(parts, "  ")
            d.detailLabel.Visible = true
        else
            d.detailLabel.Visible = false
        end

        if cfg.Weapon then
            local tool = model:FindFirstChildOfClass("Tool")
            if tool then
                d.weapLabel.Text = "[" .. tool.Name .. "]"
                d.weapLabel.Visible = true
            else
                d.weapLabel.Visible = false
            end
        else
            d.weapLabel.Visible = false
        end
    else
        d.infoBB.Enabled = false
    end

    -- Health bar billboard (size matched to character height)
    if cfg.HealthBar then
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
local exfilScanned = false

local raidPill = newInst("Frame", {
    BackgroundColor3 = Color3.fromRGB(15, 15, 18),
    BackgroundTransparency = 0.25,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 14),
    Size = UDim2.fromOffset(150, 30),
    Visible = false,
}, espGui)
mkCorner(raidPill, 8)
mkStroke(raidPill, Color3.fromRGB(255, 220, 100), 1, 0.4)
local raidLabel = newInst("TextLabel", {
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = TIMER_COL,
    Text = "RAID",
}, raidPill)

local function findExfils()
    local ignored = workspace:FindFirstChild("Ignored")
    if not ignored then return end
    local exfils = ignored:FindFirstChild("Exfils")
    if not exfils then return end
    for _, exfil in ipairs(exfils:GetChildren()) do
        local hitbox = exfil:FindFirstChild("hitbox")
        if hitbox and hitbox:IsA("BasePart") and not exfilCache[hitbox] then
            local text = mkText(espGui, 14, true)
            text.TextColor3 = EXFIL_COL
            local sub = mkText(espGui, 12, false)
            sub.TextColor3 = EXFIL_SUB
            exfilCache[hitbox] = { text = text, sub = sub, ename = exfil.Name }
        end
    end
    exfilScanned = true
end

local function drawExfils(myRoot, cam)
    for part, d in pairs(exfilCache) do
        local ok2, vis2 = pcall(function()
            if not part or not part.Parent then return false end
            local sPos, onScreen = cam:WorldToViewportPoint(part.Position)
            if not onScreen then return false end
            local dist = myRoot and (part.Position - myRoot.Position).Magnitude or 0
            d.text.Text = "◆ " .. d.ename
            d.text.Position = UDim2.fromOffset(sPos.X, sPos.Y - 8)
            d.text.Visible = true
            d.sub.Text = string.format("%.0fm", dist)
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
local function updateRaidTimer(dt)
    raidCounter = raidCounter + dt
    if raidCounter < 1 then return end
    raidCounter = 0
    local s, val = pcall(function()
        local srv = ReplicatedStorage:FindFirstChild("__server")
        local rt = srv and srv:FindFirstChild("RaidTimer")
        return rt and rt.Value
    end)
    if not s or type(val) ~= "number" then
        raidPill.Visible = false
        return
    end
    raidLabel.Text = string.format("RAID  %02d:%02d", math.floor(val / 60), math.floor(val % 60))
    raidPill.Visible = true
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

local LOOT_POOL = 45
local LOOT_HL = 16   -- Highlights are engine-limited (~31 total); cap loot glow low
local lootPool = {}
local lootHlPool = {}
for i = 1, LOOT_POOL do
    lootPool[i] = mkText(espGui, 11, true)
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

local function rebuildLoot()
    local new = {}
    local buildings = workspace:FindFirstChild("Buildings")
    local loots = buildings and buildings:FindFirstChild("Loots")
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
                        new[#new + 1] = { inst = cc, pos = piv, top = piv + Vector3.new(0, 2, 0), label = cc.Name, cat = "container", tier = tier, color = LOOT_COL[tier] }
                    end
                end
            end
        end
        local chars = inner:FindFirstChild("Characters")
        if chars then
            for _, cc in ipairs(chars:GetChildren()) do
                local ok, piv = pcall(function() return cc:GetPivot().Position end)
                if ok and piv then
                    new[#new + 1] = { inst = cc, pos = piv, top = piv + Vector3.new(0, 2, 0), label = "☠ Body", cat = "body", color = BODY_COL }
                end
            end
        end
    end

    local items = loots:FindFirstChild("Items")
    if items then
        for _, cc in ipairs(items:GetChildren()) do
            local ok, piv = pcall(function() return cc:GetPivot().Position end)
            if ok and piv then
                new[#new + 1] = { inst = cc, pos = piv, top = piv + Vector3.new(0, 2, 0), label = cc.Name, cat = "item", color = ITEM_COL }
            end
        end
    end

    lootEntries = new
end

local function lootCatEnabled(e)
    if e.cat == "item" then return cfg.LootItems end
    if e.cat == "body" then return cfg.LootBodies end
    if e.tier == "Elite" then return cfg.LootElite end
    if e.tier == "High" then return cfg.LootHigh end
    if e.tier == "Mid" then return cfg.LootMid end
    return cfg.LootTrash
end

local function hideLoot()
    for i = 1, LOOT_POOL do lootPool[i].Visible = false end
    for i = 1, LOOT_HL do lootHlPool[i].Enabled = false end
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
            local dd = (e.pos - myPos).Magnitude
            if dd <= maxd then
                shown[#shown + 1] = { e = e, d = dd }
            end
        end
    end
    table.sort(shown, function(a, b) return a.d < b.d end)
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
                txt.Text = string.format("%s  <font transparency='0.4'>%.0fm</font>", e.label, (e.pos - myPos).Magnitude)
                txt.Position = UDim2.fromOffset(sc.X, sc.Y)
                txt.TextColor3 = e.color
                txt.Visible = true
            else
                txt.Visible = false
            end
        else
            txt.Visible = false
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

local function backpackRoot()
    local gui = player:FindFirstChild("PlayerGui")
    local ui = gui and gui:FindFirstChild("UI")
    local hud = ui and ui:FindFirstChild("HUD")
    return hud and hud:FindFirstChild("backpackFrame")
end

local function clearQuestHL()
    local bp = backpackRoot()
    if not bp then return end
    for _, f in ipairs(bp:GetDescendants()) do
        if f.Name == QUEST_HL then pcall(function() f:Destroy() end) end
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
            elseif not isQuest and hl then
                pcall(function() hl:Destroy() end)
            end
        end
    end
end

-- ============================================================
-- Aim Assist
-- ============================================================
local aimTarget = nil
local aimWhitelist = {}  -- [UserId] = true; aim ignores these players

local fovCircle = newInst("Frame", {
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Visible = false,
}, espGui)
mkCorner(fovCircle, 999)
mkStroke(fovCircle, FOV_COL, 1.5, 0.4)

local function pickAimTarget(cam, vpSize, myRoot)
    local center = Vector2.new(vpSize.X / 2, vpSize.Y / 2)
    local best, bestScreenDist = nil, cfg.AimFov
    local partName = cfg.AimTargetPart

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
                local part = model:FindFirstChild(partName)
                    or model:FindFirstChild("Torso")
                    or model:FindFirstChild("HumanoidRootPart")
                if not part then skip = true end
                if not skip then
                    local d3 = myRoot and (part.Position - myRoot.Position).Magnitude or 0
                    if d3 > cfg.AimMaxDist then skip = true end
                    if not skip then
                        local screen, onScreen = cam:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local sd = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                            if sd < bestScreenDist then
                                if not cfg.AimLosCheck or hasLineOfSight(cam, part) then
                                    best = part
                                    bestScreenDist = sd
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function isTargetStillValid(cam, myRoot)
    if not aimTarget or not aimTarget.Parent then return false end
    local model = aimTarget:FindFirstAncestorOfClass("Model")
    if not model or not cache[model] then return false end
    local wp = Players:GetPlayerFromCharacter(model)
    if wp and aimWhitelist[wp.UserId] then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local d3 = myRoot and (aimTarget.Position - myRoot.Position).Magnitude or 0
    if d3 > cfg.AimMaxDist then return false end
    if cfg.AimLosCheck and not hasLineOfSight(cam, aimTarget) then return false end
    return true
end

-- Toggle the player nearest the crosshair in/out of the aim whitelist
local function whitelistNearestPlayer()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

    local best, bestSd = nil, 220
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local part = plr.Character:FindFirstChild("Head")
                or plr.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local d3 = myRoot and (part.Position - myRoot.Position).Magnitude or 0
                if d3 <= 500 then
                    local sc, on = cam:WorldToViewportPoint(part.Position)
                    if on then
                        local sd = (Vector2.new(sc.X, sc.Y) - center).Magnitude
                        if sd < bestSd then best, bestSd = plr, sd end
                    end
                end
            end
        end
    end
    if not best then return end

    local id = best.UserId
    local msg
    if aimWhitelist[id] then
        aimWhitelist[id] = nil
        msg = best.DisplayName .. " removed from whitelist"
    else
        aimWhitelist[id] = true
        msg = best.DisplayName .. " added — aim will ignore"
    end
    if Window then
        pcall(function() Window:Notify({ Title = "Whitelist", Description = msg, Lifetime = 3 }) end)
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
        return
    end

    if cfg.AimStickyTarget and aimTarget then
        if not isTargetStillValid(cam, myRoot) then
            aimTarget = pickAimTarget(cam, vpSize, myRoot)
        end
    else
        aimTarget = pickAimTarget(cam, vpSize, myRoot)
    end

    if not aimTarget or not aimTarget.Parent then return end

    -- Don't fight the menu cursor
    local menuOpen = false
    pcall(function() menuOpen = (Window and Window:GetState()) == true end)
    if menuOpen then return end

    -- Move the mouse toward the target. The game uses a Scriptable camera, so
    -- writing Camera.CFrame gets overwritten — instead we nudge the OS mouse and
    -- let the game's own camera turn. Closed loop: each frame we re-measure the
    -- gap and cover a fraction of it, so it converges regardless of sensitivity.
    local screen, onScreen = cam:WorldToViewportPoint(aimTarget.Position)
    if not onScreen then return end
    local dx = screen.X - vpSize.X / 2
    local dy = screen.Y - vpSize.Y / 2
    -- Frame-rate independent: alpha is the fraction of the gap to cover this
    -- frame, normalised by dt so "Smoothness" feels the same at 30 or 144 FPS.
    local rate = 60 / math.max(cfg.AimSmoothness, 1)
    local alpha = 1 - math.exp(-(dt or 0.016) * rate)
    if mousemoverel then
        mousemoverel(dx * alpha, dy * alpha)
    end
end

-- ============================================================
-- Scanning
-- ============================================================
local function scanEntities()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character and plr.Character:IsDescendantOf(workspace) then
            createEntry(plr.Character, false)
        end
    end
    local container = findEntityContainer()
    if container then
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                if not Players:GetPlayerFromCharacter(child) then
                    createEntry(child, true)
                end
            end
        end
    end
    if not exfilScanned then findExfils() end
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
        if cfg.LootEnabled then rebuildLoot() end
    end

    if cfg.Enabled then
        for model, d in pairs(cache) do
            local s, drew = pcall(drawEntity, model, d, myRoot, cam, vpSize, dt)
            if not s or not drew then hideEntry(d) end
        end
        if cfg.ExfilESP then drawExfils(myRoot, cam) else hideExfils() end
        if cfg.RaidTimer then updateRaidTimer(dt) else raidPill.Visible = false end
    else
        for _, d in pairs(cache) do hideEntry(d) end
        hideExfils()
        raidPill.Visible = false
    end

    if cfg.LootEnabled then drawLoot(myRoot, cam, dt) else hideLoot() end
    if cfg.Fullbright then applyFullbright() end

    if cfg.QuestHL then
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
    return cfg.Enabled or cfg.AimEnabled or cfg.LootEnabled or cfg.Fullbright or cfg.QuestHL
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
    raidPill.Visible = false
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
local function cleanup()
    unbindAim()
    stopRender()
    restoreFullbright()
    clearQuestHL()
    pcall(function() espGui:Destroy() end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    cache = {}
    if Window then pcall(function() Window:Unload() end) end
end

if getgenv then getgenv().__HAKO_CLEANUP = cleanup end

-- ============================================================
-- MacLib UI
-- ============================================================
Window = MacLib:Window({
    Title = "hako",
    Subtitle = "ESP • Aim • Loot",
    Size = UDim2.fromOffset(780, 580),
    DragStyle = 1,
    ShowUserInfo = true,
    Keybind = Enum.KeyCode.RightControl,
    AcrylicBlur = false,  -- blur needs Plugin capability some executors' inject thread lacks
})
Window.onUnloaded(function()
    pcall(function()
        unbindAim()
        stopRender()
        restoreFullbright()
        clearQuestHL()
        espGui:Destroy()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    end)
end)

-- Free the mouse while the menu is open (first-person games lock it to center)
do
    local UIS = game:GetService("UserInputService")
    conns[#conns + 1] = RunService.Heartbeat:Connect(function()
        local ok, open = pcall(function() return Window:GetState() end)
        if ok and open == true then
            if not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
            if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
                UIS.MouseBehavior = Enum.MouseBehavior.Default
            end
        end
    end)
end

local Tabs = Window:TabGroup()

-- ---------- ESP TAB ----------
local espTab = Tabs:Tab({ Name = "ESP" })
local espL = espTab:Section({ Side = "Left" })
local espR = espTab:Section({ Side = "Right" })

espL:Header({ Name = "Main" })
espL:Toggle({ Name = "Enable ESP", Default = false,
    Callback = function(v) cfg.Enabled = v; ensureRender() end }, "espEnabled")
espL:Toggle({ Name = "Player ESP", Default = cfg.PlayerESP,
    Callback = function(v) cfg.PlayerESP = v end }, "espPlayers")
espL:Toggle({ Name = "NPC ESP", Default = cfg.NpcESP,
    Callback = function(v) cfg.NpcESP = v end }, "espNpcs")
espL:Toggle({ Name = "Team Check (players)", Default = cfg.TeamCheck,
    Callback = function(v) cfg.TeamCheck = v end }, "espTeam")
espL:Label({ Text = "Players: green = visible, red = behind wall" })
espL:Header({ Name = "Outline / Chams" })
espL:Toggle({ Name = "Outline (glowing edge)", Default = cfg.Outline,
    Callback = function(v) cfg.Outline = v end }, "espOutline")
espL:Toggle({ Name = "Chams (fill through walls)", Default = cfg.Chams,
    Callback = function(v) cfg.Chams = v end }, "espChams")
espL:Slider({ Name = "Chams Opacity", Default = cfg.ChamsOpacity,
    Minimum = 0, Maximum = 100, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.ChamsOpacity = v end }, "espChamsOp")
espL:Header({ Name = "Range" })
espL:Slider({ Name = "Max Distance", Default = cfg.MaxDistance,
    Minimum = 50, Maximum = 1000, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.MaxDistance = v end }, "espMaxDist")

espR:Header({ Name = "Details" })
espR:Toggle({ Name = "Names", Default = cfg.Names,
    Callback = function(v) cfg.Names = v end }, "espNames")
espR:Toggle({ Name = "Health Bar", Default = cfg.HealthBar,
    Callback = function(v) cfg.HealthBar = v end }, "espHealth")
espR:Toggle({ Name = "Distance / HP", Default = cfg.Distance,
    Callback = function(v) cfg.Distance = v end }, "espDist")
espR:Toggle({ Name = "Weapon (enemy gear)", Default = cfg.Weapon,
    Callback = function(v) cfg.Weapon = v end }, "espWeapon")
espR:Toggle({ Name = "Tracers", Default = cfg.Tracers,
    Callback = function(v) cfg.Tracers = v end }, "espTracers")
espR:Header({ Name = "Colors" })
espR:Colorpicker({ Name = "Visible", Default = cfg.VisibleColor,
    Callback = function(c) cfg.VisibleColor = c end }, "colVisible")
espR:Colorpicker({ Name = "Behind Wall", Default = cfg.HiddenColor,
    Callback = function(c) cfg.HiddenColor = c end }, "colHidden")
espR:Colorpicker({ Name = "NPC", Default = cfg.NpcColor,
    Callback = function(c) cfg.NpcColor = c end }, "colNpc")

-- ---------- LOOT TAB ----------
local lootTab = Tabs:Tab({ Name = "Loot" })
local lootL = lootTab:Section({ Side = "Left" })
local lootR = lootTab:Section({ Side = "Right" })

lootL:Header({ Name = "Loot ESP" })
lootL:Toggle({ Name = "Enable Loot ESP", Default = false,
    Callback = function(v) cfg.LootEnabled = v; if v then rebuildLoot() end; ensureRender() end }, "lootEnabled")
lootL:Slider({ Name = "Max Distance", Default = cfg.LootMaxDist,
    Minimum = 20, Maximum = 300, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.LootMaxDist = v end }, "lootMaxDist")
lootL:Toggle({ Name = "Show Names / Distance", Default = cfg.LootNames,
    Callback = function(v) cfg.LootNames = v end }, "lootNames")
lootL:Label({ Text = "Nearest models glow + get small labels." })
lootL:Label({ Text = "Gold=Elite  Purple=High  Blue=Mid" })

lootR:Header({ Name = "Containers" })
lootR:Toggle({ Name = "Elite (safes / military)", Default = cfg.LootElite,
    Callback = function(v) cfg.LootElite = v end }, "lootElite")
lootR:Toggle({ Name = "High (weapon / med / ammo)", Default = cfg.LootHigh,
    Callback = function(v) cfg.LootHigh = v end }, "lootHigh")
lootR:Toggle({ Name = "Mid (cases / misc)", Default = cfg.LootMid,
    Callback = function(v) cfg.LootMid = v end }, "lootMid")
lootR:Toggle({ Name = "Trash (furniture)", Default = cfg.LootTrash,
    Callback = function(v) cfg.LootTrash = v end }, "lootTrash")
lootR:Header({ Name = "Other" })
lootR:Toggle({ Name = "Dropped Items", Default = cfg.LootItems,
    Callback = function(v) cfg.LootItems = v end }, "lootItems")
lootR:Toggle({ Name = "Bodies", Default = cfg.LootBodies,
    Callback = function(v) cfg.LootBodies = v end }, "lootBodies")

-- ---------- WORLD TAB ----------
local worldTab = Tabs:Tab({ Name = "World" })
local worldL = worldTab:Section({ Side = "Left" })

worldL:Header({ Name = "Map" })
worldL:Toggle({ Name = "Exfil ESP", Default = cfg.ExfilESP,
    Callback = function(v) cfg.ExfilESP = v end }, "worldExfil")
worldL:Toggle({ Name = "Raid Timer", Default = cfg.RaidTimer,
    Callback = function(v) cfg.RaidTimer = v end }, "worldTimer")
worldL:Label({ Text = "Exfils / timer show while ESP is on." })
worldL:Toggle({ Name = "Quest Item Highlight", Default = cfg.QuestHL,
    Callback = function(v) cfg.QuestHL = v; if not v then clearQuestHL() end; ensureRender() end }, "worldQuestHL")
worldL:Header({ Name = "Environment" })
worldL:Toggle({ Name = "Fullbright", Default = false,
    Callback = function(v) cfg.Fullbright = v; if not v then restoreFullbright() end; ensureRender() end }, "worldFullbright")

-- ---------- AIM TAB ----------
local aimTab = Tabs:Tab({ Name = "Aim" })
local aimLft = aimTab:Section({ Side = "Left" })
local aimRgt = aimTab:Section({ Side = "Right" })

aimLft:Header({ Name = "Aim Assist" })
aimLft:Toggle({ Name = "Enable Aim Assist", Default = false,
    Callback = function(v) cfg.AimEnabled = v; ensureRender() end }, "aimEnabled")
aimLft:Keybind({ Name = "Aim Key (hold)", Default = Enum.UserInputType.MouseButton2,
    onBindHeld = function(held) aimHolding = held end }, "aimKey")
aimLft:Toggle({ Name = "Show FOV Circle", Default = cfg.AimShowFov,
    Callback = function(v) cfg.AimShowFov = v end }, "aimShowFov")
aimLft:Header({ Name = "Behavior" })
aimLft:Slider({ Name = "FOV Radius", Default = cfg.AimFov,
    Minimum = 10, Maximum = 300, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.AimFov = v end }, "aimFov")
aimLft:Slider({ Name = "Smoothness (higher = softer)", Default = cfg.AimSmoothness,
    Minimum = 1, Maximum = 20, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.AimSmoothness = v end }, "aimSmooth")
aimLft:Slider({ Name = "Max Distance", Default = cfg.AimMaxDist,
    Minimum = 50, Maximum = 800, DisplayMethod = "Round", Precision = 0,
    Callback = function(v) cfg.AimMaxDist = v end }, "aimMaxDist")

aimRgt:Header({ Name = "Targeting" })
aimRgt:Dropdown({ Name = "Target Part", Options = { "Torso", "HumanoidRootPart", "Head" },
    Default = 1, Multi = false, Callback = function(v) cfg.AimTargetPart = v end }, "aimPart")
aimRgt:Toggle({ Name = "Target Players", Default = cfg.AimTargetPlayers,
    Callback = function(v) cfg.AimTargetPlayers = v end }, "aimTgtPlr")
aimRgt:Toggle({ Name = "Target NPCs", Default = cfg.AimTargetNpcs,
    Callback = function(v) cfg.AimTargetNpcs = v end }, "aimTgtNpc")
aimRgt:Toggle({ Name = "Team Check", Default = cfg.AimTeamCheck,
    Callback = function(v) cfg.AimTeamCheck = v end }, "aimTeam")
aimRgt:Toggle({ Name = "Line-of-Sight Check", Default = cfg.AimLosCheck,
    Callback = function(v) cfg.AimLosCheck = v end }, "aimLos")
aimRgt:Toggle({ Name = "Sticky Target", Default = cfg.AimStickyTarget,
    Callback = function(v) cfg.AimStickyTarget = v end }, "aimSticky")

aimRgt:Header({ Name = "Whitelist" })
aimRgt:Keybind({ Name = "Whitelist target (toggle)", Default = Enum.UserInputType.MouseButton3,
    Callback = function() whitelistNearestPlayer() end }, "aimWlKey")
aimRgt:Button({ Name = "Clear Whitelist", Callback = function()
    aimWhitelist = {}
    if Window then pcall(function() Window:Notify({ Title = "Whitelist", Description = "Cleared", Lifetime = 3 }) end) end
end })

-- ---------- CONFIG TAB ----------
local cfgTab = Tabs:Tab({ Name = "Config" })
cfgTab:InsertConfigSection("Left")
local cfgR = cfgTab:Section({ Side = "Right" })
cfgR:Header({ Name = "Script" })
cfgR:Label({ Text = "GUI visuals hidden in gethui() — unscannable." })
cfgR:Label({ Text = "Aim = mouse nudge. No hooks, no remotes." })
cfgR:Divider()
cfgR:Button({ Name = "Unload Script", Callback = function() cleanup() end })

Window:Notify({
    Title = "hako",
    Description = "Loaded. RightCtrl toggles the menu.",
    Lifetime = 5,
})

task.spawn(function()
    pcall(function() MacLib:LoadAutoLoadConfig() end)
end)
