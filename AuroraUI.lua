--[[
╔══════════════════════════════════════════════════════════════════════╗
║   A U R O R A   U I                                          v1.0    ║
║   Горизонтальная UI-библиотека для Roblox в стиле десктоп-приложения  ║
╠══════════════════════════════════════════════════════════════════════╣
║   local UI  = loadstring(game:HttpGet("<ссылка>"))()                  ║
║                                                                      ║
║   local Win = UI:Window{                                             ║
║       Title    = "Aurora",                                           ║
║       Subtitle = "v1.0",                                             ║
║       Size     = UDim2.fromOffset(760, 500),                         ║
║       Config   = "MyScript",   -- папка сохранения настроек          ║
║   }                                                                  ║
║                                                                      ║
║   local Main = Win:Tab{ Name = "Главная", Icon = "◆" }               ║
║                                                                      ║
║   Main:Section{ Text = "Персонаж" }                                  ║
║   Main:Toggle{                                                       ║
║       Flag = "fly", Text = "Полёт", Desc = "Пробел — вверх",         ║
║       Default = false,                                               ║
║       Callback = function(v) print(v) end,                           ║
║   }                                                                  ║
║   Main:Slider{ Flag = "ws", Text = "Скорость", Min = 16, Max = 300 } ║
║                                                                      ║
║   -- значения доступны отовсюду:  UI.Flags.fly                       ║
╚══════════════════════════════════════════════════════════════════════╝
]]

--═══════════════════════════════════════════════════════════════════════
--  0. ОКРУЖЕНИЕ
--═══════════════════════════════════════════════════════════════════════

local function service(name)
	local ok, s = pcall(game.GetService, game, name)
	return ok and s or nil
end

local Players      = service("Players")
local RunService    = service("RunService")
local TweenService  = service("TweenService")
local UserInput     = service("UserInputService")
local HttpService   = service("HttpService")
local Lighting      = service("Lighting")
local TextService   = service("TextService")

local LocalPlayer = Players and Players.LocalPlayer
local ENV = (typeof(getgenv) == "function") and getgenv() or _G

-- Файловая система исполнителя (может отсутствовать)
local FS = {
	write  = (typeof(writefile)  == "function") and writefile  or nil,
	read   = (typeof(readfile)   == "function") and readfile   or nil,
	isfile = (typeof(isfile)     == "function") and isfile     or nil,
	isdir  = (typeof(isfolder)   == "function") and isfolder   or nil,
	mkdir  = (typeof(makefolder) == "function") and makefolder or nil,
	list   = (typeof(listfiles)  == "function") and listfiles  or nil,
	delete = (typeof(delfile)    == "function") and delfile    or nil,
}
local HAS_FS = FS.write and FS.read and FS.isfile and true or false

-- Гасим предыдущую копию библиотеки, если она уже висит в памяти
if ENV.AuroraUI and type(ENV.AuroraUI.Destroy) == "function" then
	pcall(ENV.AuroraUI.Destroy, ENV.AuroraUI)
end

--═══════════════════════════════════════════════════════════════════════
--  1. ТЕМЫ
--═══════════════════════════════════════════════════════════════════════

local THEMES = {
	Aurora = {
		Backdrop   = Color3.fromRGB(11, 12, 17),   -- корпус окна
		Sidebar    = Color3.fromRGB(15, 16, 23),   -- левая панель
		Content    = Color3.fromRGB(19, 21, 29),   -- рабочая область
		Card       = Color3.fromRGB(26, 29, 39),   -- строка элемента
		CardHover  = Color3.fromRGB(32, 36, 48),
		Inset      = Color3.fromRGB(14, 15, 21),   -- утопленные поля
		Stroke     = Color3.fromRGB(38, 42, 56),
		Text       = Color3.fromRGB(236, 239, 247),
		SubText    = Color3.fromRGB(139, 147, 168),
		Muted      = Color3.fromRGB(94, 101, 120),
		Accent     = Color3.fromRGB(122, 140, 255),
		Accent2    = Color3.fromRGB(190, 122, 255),
		Good       = Color3.fromRGB(64, 214, 148),
		Warn       = Color3.fromRGB(255, 186, 84),
		Bad        = Color3.fromRGB(255, 92, 112),
	},
	Midnight = {
		Backdrop   = Color3.fromRGB(10, 12, 16),
		Sidebar    = Color3.fromRGB(14, 17, 22),
		Content    = Color3.fromRGB(18, 22, 28),
		Card       = Color3.fromRGB(25, 30, 38),
		CardHover  = Color3.fromRGB(31, 37, 47),
		Inset      = Color3.fromRGB(13, 16, 21),
		Stroke     = Color3.fromRGB(36, 43, 54),
		Text       = Color3.fromRGB(232, 238, 245),
		SubText    = Color3.fromRGB(134, 146, 163),
		Muted      = Color3.fromRGB(90, 100, 116),
		Accent     = Color3.fromRGB(56, 189, 248),
		Accent2    = Color3.fromRGB(45, 212, 191),
		Good       = Color3.fromRGB(52, 211, 153),
		Warn       = Color3.fromRGB(251, 191, 36),
		Bad        = Color3.fromRGB(248, 113, 113),
	},
	Ember = {
		Backdrop   = Color3.fromRGB(16, 12, 12),
		Sidebar    = Color3.fromRGB(21, 16, 16),
		Content    = Color3.fromRGB(26, 20, 20),
		Card       = Color3.fromRGB(35, 27, 27),
		CardHover  = Color3.fromRGB(43, 33, 33),
		Inset      = Color3.fromRGB(19, 14, 14),
		Stroke     = Color3.fromRGB(52, 40, 40),
		Text       = Color3.fromRGB(245, 238, 236),
		SubText    = Color3.fromRGB(168, 145, 140),
		Muted      = Color3.fromRGB(118, 100, 96),
		Accent     = Color3.fromRGB(255, 138, 76),
		Accent2    = Color3.fromRGB(255, 94, 120),
		Good       = Color3.fromRGB(120, 205, 140),
		Warn       = Color3.fromRGB(255, 190, 100),
		Bad        = Color3.fromRGB(255, 96, 96),
	},
}

local Theme = {}
for k, v in next, THEMES.Aurora do Theme[k] = v end

-- Реестр «инстанс → свойство → ключ темы».
-- Смена темы проходит по нему и твинит всё разом.
local ThemeRegistry = {}

local GradientRegistry = {}

local function register(inst, prop, key)
	table.insert(ThemeRegistry, { inst = inst, prop = prop, key = key })
	pcall(function() inst[prop] = Theme[key] end)
end

-- ColorSequence нельзя твинить как обычное свойство, поэтому градиенты
-- живут в отдельном реестре и пересобираются при смене темы.
local function registerGradient(gradient, keyA, keyB)
	table.insert(GradientRegistry, { inst = gradient, a = keyA, b = keyB })
	pcall(function()
		gradient.Color = ColorSequence.new(Theme[keyA], Theme[keyB])
	end)
	return gradient
end

--═══════════════════════════════════════════════════════════════════════
--  2. УТИЛИТЫ
--═══════════════════════════════════════════════════════════════════════

local FONT   = Enum.Font.Gotham
local FONT_M = Enum.Font.GothamMedium
local FONT_B = Enum.Font.GothamBold

local EASE      = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local EASE_FAST  = TweenInfo.new(0.12, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local EASE_SLOW  = TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local function tween(inst, info, props)
	local ok, t = pcall(function() return TweenService:Create(inst, info, props) end)
	if ok and t then t:Play() end
	return t
end

-- Универсальный конструктор. Ключ `Theme = { Свойство = "КлючТемы" }`
-- сразу применяет цвет и подписывает инстанс на смену темы.
local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in next, props or {} do
		if k == "Parent" then
			parent = v
		elseif k == "Theme" then
			for prop, key in next, v do register(inst, prop, key) end
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end

local function stroke(key, thickness, transparency)
	return new("UIStroke", {
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Theme = { Color = key or "Stroke" },
	})
end

local function padding(t, b, l, r)
	return new("UIPadding", {
		PaddingTop    = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or t or 0),
		PaddingLeft   = UDim.new(0, l or 0),
		PaddingRight  = UDim.new(0, r or l or 0),
	})
end

local function list(pad, dir)
	return new("UIListLayout", {
		Padding = UDim.new(0, pad or 6),
		FillDirection = dir or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function label(props)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT_M,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Theme = { TextColor3 = "Text" },
	}
	for k, v in next, props do base[k] = v end
	return new("TextLabel", base)
end

local function round(value, decimals)
	local m = 10 ^ (decimals or 0)
	return math.floor(value * m + 0.5) / m
end

local function clamp01(v) return math.clamp(v, 0, 1) end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then warn("[AuroraUI] ошибка в коллбэке: " .. tostring(err)) end
	end)
end

--═══════════════════════════════════════════════════════════════════════
--  3. БИБЛИОТЕКА
--═══════════════════════════════════════════════════════════════════════

local Library = {
	Version    = "1.0",
	Flags      = {},   -- flag -> текущее значение
	Options    = {},   -- flag -> объект элемента
	Windows    = {},
	SearchIndex = {},  -- для командной палитры
	ThemeName  = "Aurora",
	Alive      = true,
	_conns     = {},
	_render    = {},
	_unloadFns = {},
}

local function track(conn)
	if conn then table.insert(Library._conns, conn) end
	return conn
end

--── единый рендер-тик: один RenderStepped на всю библиотеку ──
do
	local hooks = Library._render
	track(RunService.RenderStepped:Connect(function(dt)
		if not Library.Alive then return end
		for i = #hooks, 1, -1 do
			local hook = hooks[i]
			local ok = pcall(hook, dt)
			if not ok then table.remove(hooks, i) end
		end
	end))
end

local function onRender(fn)
	table.insert(Library._render, fn)
	return function()
		for i, f in ipairs(Library._render) do
			if f == fn then table.remove(Library._render, i) break end
		end
	end
end

--═══════════════════════════════════════════════════════════════════════
--  4. ЕДИНЫЙ ДИСПЕТЧЕР ВВОДА
--  Вместо коннекта на каждый элемент — три коннекта на всю библиотеку.
--═══════════════════════════════════════════════════════════════════════

local Dispatch = { Began = {}, Changed = {}, Ended = {} }

local function onInput(kind, fn)
	table.insert(Dispatch[kind], fn)
	return fn
end

local activeDrag = nil       -- функция обновления текущего перетаскивания
local captureTarget = nil    -- элемент, ожидающий нажатия клавиши
local keybinds = {}          -- список активных кейбиндов

local function fire(kind, input, processed)
	for _, fn in ipairs(Dispatch[kind]) do
		local ok, err = pcall(fn, input, processed)
		if not ok then warn("[AuroraUI] ввод: " .. tostring(err)) end
	end
end

track(UserInput.InputBegan:Connect(function(input, processed)
	if not Library.Alive then return end
	-- перехват записи кейбинда идёт раньше всего остального
	if captureTarget then
		local target = captureTarget
		captureTarget = nil
		pcall(target, input)
		return
	end
	if not processed then
		for _, kb in ipairs(keybinds) do
			if kb.key and (input.KeyCode == kb.key or input.UserInputType == kb.key) then
				safeCall(kb.fire)
			end
		end
	end
	fire("Began", input, processed)
end))

track(UserInput.InputChanged:Connect(function(input, processed)
	if not Library.Alive then return end
	if activeDrag and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		pcall(activeDrag, input)
	end
	fire("Changed", input, processed)
end))

track(UserInput.InputEnded:Connect(function(input, processed)
	if not Library.Alive then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		activeDrag = nil
	end
	fire("Ended", input, processed)
end))

local function isPressStart(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Перетаскивание: handle тянет target. Один общий обработчик движения.
local function draggable(handle, target, onMove)
	handle.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		local origin, startPos = input.Position, target.Position
		activeDrag = function(i)
			local d = i.Position - origin
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
			if onMove then onMove() end
		end
	end)
end

--═══════════════════════════════════════════════════════════════════════
--  5. КОРНЕВОЙ GUI + СЛОЙ ОВЕРЛЕЯ
--  Выпадающие списки и пикеры рисуются в отдельном верхнем слое,
--  иначе их обрезал бы ScrollingFrame.
--═══════════════════════════════════════════════════════════════════════

local Gui = new("ScreenGui", {
	Name = "Aurora_" .. tostring(math.random(100000, 999999)),
	ResetOnSpawn = false,
	IgnoreGuiInset = true,     -- AbsolutePosition совпадает с координатами ввода
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 9999,
})

do
	local placed = false
	if typeof(gethui) == "function" then
		placed = pcall(function() Gui.Parent = gethui() end)
	end
	if not placed and typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
		placed = pcall(function()
			syn.protect_gui(Gui)
			Gui.Parent = game:GetService("CoreGui")
		end)
	end
	if not placed then
		placed = pcall(function() Gui.Parent = game:GetService("CoreGui") end)
	end
	if not placed and LocalPlayer then
		Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

local Overlay = new("Frame", {
	Parent = Gui,
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 500,
})

local function viewport()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

-- Единственный открытый поп-ап за раз: клик мимо закрывает его.
local openPopup = nil
local popupGuard = false

local function closePopup()
	if openPopup then
		local fn = openPopup
		openPopup = nil
		pcall(fn)
	end
end

-- Поп-ап вызывает это из своего InputBegan, чтобы клик внутри него
-- не был воспринят как «клик мимо».
local function guardPopup() popupGuard = true end

onInput("Began", function(input)
	if not openPopup or not isPressStart(input) then return end
	-- Запоминаем, какой именно поп-ап был открыт в момент нажатия.
	-- Если за этот кадр открылся другой (клик по соседнему дропдауну) —
	-- закрывать уже нечего, иначе схлопнем только что открытое меню.
	local snapshot = openPopup
	task.defer(function()
		if popupGuard then popupGuard = false return end
		if openPopup == snapshot then closePopup() end
	end)
end)

--═══════════════════════════════════════════════════════════════════════
--  6. АКРИЛОВОЕ РАЗМЫТИЕ ФОНА
--═══════════════════════════════════════════════════════════════════════

local Blur
local function setBlur(amount)
	if not Lighting then return end
	if not Blur or not Blur.Parent then
		local ok = pcall(function()
			Blur = Instance.new("BlurEffect")
			Blur.Name = "AuroraBlur"
			Blur.Size = 0
			Blur.Parent = Lighting
		end)
		if not ok then return end
	end
	tween(Blur, EASE_SLOW, { Size = amount })
end

--═══════════════════════════════════════════════════════════════════════
--  7. УВЕДОМЛЕНИЯ
--═══════════════════════════════════════════════════════════════════════

local ToastLayer = new("Frame", {
	Parent = Gui,
	Name = "Toasts",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 20),
	Size = UDim2.fromOffset(320, 600),
	BackgroundTransparency = 1,
	ZIndex = 900,
}, {
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

function Library:Notify(opts)
	opts = opts or {}
	local title    = opts.Title or "Уведомление"
	local content  = opts.Content or opts.Text or ""
	local duration = opts.Duration or 4
	local accent   = Theme[opts.Type == "error" and "Bad"
		or opts.Type == "warn" and "Warn"
		or opts.Type == "success" and "Good"
		or "Accent"]

	local card = new("Frame", {
		Parent = ToastLayer,
		Size = UDim2.fromOffset(320, content ~= "" and 74 or 54),
		BackgroundTransparency = 1,
		ZIndex = 901,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(12), stroke("Stroke", 1, 1) })

	local shell = new("Frame", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 902,
	})

	new("Frame", {
		Parent = shell,
		Size = UDim2.new(0, 3, 1, -22),
		Position = UDim2.fromOffset(11, 11),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 903,
	}, { corner(2) })

	local titleLbl = label({
		Parent = shell,
		Position = UDim2.fromOffset(24, 11),
		Size = UDim2.new(1, -36, 0, 16),
		Font = FONT_B,
		TextSize = 13,
		Text = title,
		ZIndex = 903,
	})

	local bodyLbl
	if content ~= "" then
		bodyLbl = label({
			Parent = shell,
			Position = UDim2.fromOffset(24, 30),
			Size = UDim2.new(1, -36, 0, 32),
			TextSize = 12,
			Text = content,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 903,
			Theme = { TextColor3 = "SubText" },
		})
	end

	local bar = new("Frame", {
		Parent = shell,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -6),
		Size = UDim2.new(1, -24, 0, 2),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 903,
	}, { corner(1) })

	-- въезд справа
	card.Position = UDim2.fromOffset(40, 0)
	tween(card, EASE, { BackgroundTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	tween(card:FindFirstChildOfClass("UIStroke"), EASE, { Transparency = 0.4 })
	tween(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })

	task.delay(duration, function()
		if not card.Parent then return end
		tween(card, EASE_FAST, { BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 0) })
		tween(titleLbl, EASE_FAST, { TextTransparency = 1 })
		if bodyLbl then tween(bodyLbl, EASE_FAST, { TextTransparency = 1 }) end
		local s = card:FindFirstChildOfClass("UIStroke")
		if s then tween(s, EASE_FAST, { Transparency = 1 }) end
		task.delay(0.18, function() card:Destroy() end)
	end)

	return card
end

--═══════════════════════════════════════════════════════════════════════
--  8. МОДАЛЬНОЕ ОКНО
--═══════════════════════════════════════════════════════════════════════

function Library:Dialog(opts)
	opts = opts or {}
	local shade = new("Frame", {
		Parent = Gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 950,
	})
	tween(shade, EASE, { BackgroundTransparency = 0.45 })

	local box = new("Frame", {
		Parent = shade,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 0),
		ZIndex = 951,
		Theme = { BackgroundColor3 = "Content" },
	}, { corner(14), stroke("Stroke", 1, 0.25) })

	local inner = new("Frame", {
		Parent = box,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 952,
		ClipsDescendants = true,
	}, { padding(20, 16, 20, 20) })

	label({
		Parent = inner,
		Size = UDim2.new(1, 0, 0, 20),
		Font = FONT_B,
		TextSize = 15,
		Text = opts.Title or "Подтверждение",
		ZIndex = 953,
	})

	label({
		Parent = inner,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 12,
		Text = opts.Content or "",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 953,
		Theme = { TextColor3 = "SubText" },
	})

	local row = new("Frame", {
		Parent = inner,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 953,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 8),
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function close()
		tween(shade, EASE_FAST, { BackgroundTransparency = 1 })
		tween(box, EASE_FAST, { Size = UDim2.fromOffset(380, 0) })
		task.delay(0.2, function() shade:Destroy() end)
	end

	for i, def in ipairs(opts.Buttons or { { Text = "OK" } }) do
		local primary = def.Primary or (i == 1 and #(opts.Buttons or {}) <= 1)
		local btn = new("TextButton", {
			Parent = row,
			Size = UDim2.fromOffset(math.max(84, #(def.Text or "") * 9 + 28), 34),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = FONT_M,
			TextSize = 12.5,
			Text = def.Text or "OK",
			LayoutOrder = i,
			ZIndex = 954,
			BackgroundColor3 = primary and Theme.Accent or Theme.Card,
			TextColor3 = primary and Theme.Backdrop or Theme.Text,
		}, { corner(9) })
		if not primary then
			stroke("Stroke", 1, 0.3).Parent = btn
			register(btn, "BackgroundColor3", "Card")
			register(btn, "TextColor3", "Text")
		end
		btn.MouseButton1Click:Connect(function()
			close()
			safeCall(def.Callback)
		end)
	end

	tween(box, EASE, { Size = UDim2.fromOffset(380, 150) })
	return { Close = close }
end

--═══════════════════════════════════════════════════════════════════════
--  9. ОБЩИЙ КАРКАС ЭЛЕМЕНТА (строка-карточка)
--═══════════════════════════════════════════════════════════════════════

local function makeCard(parent, opts, order)
	local hasDesc = opts.Desc and opts.Desc ~= ""
	local height = opts.Height or (hasDesc and 54 or 42)

	local card = new("Frame", {
		Parent = parent,
		Name = "Item",
		Size = UDim2.new(1, 0, 0, height),
		BorderSizePixel = 0,
		LayoutOrder = order or 1,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(10), stroke("Stroke", 1, 0.55) })

	local title = label({
		Parent = card,
		Position = UDim2.fromOffset(14, hasDesc and 9 or 0),
		Size = UDim2.new(1, -170, 0, hasDesc and 16 or height),
		TextSize = 13,
		Text = opts.Text or opts.Name or "Элемент",
	})

	if hasDesc then
		label({
			Parent = card,
			Position = UDim2.fromOffset(14, 27),
			Size = UDim2.new(1, -170, 0, 15),
			Font = FONT,
			TextSize = 11.5,
			Text = opts.Desc,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "SubText" },
		})
	end

	-- правая зона под сам контрол
	local slot = new("Frame", {
		Parent = card,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(opts.SlotWidth or 140, height - 16),
		BackgroundTransparency = 1,
	})

	-- подсветка при наведении
	card.MouseEnter:Connect(function()
		tween(card, EASE_FAST, { BackgroundColor3 = Theme.CardHover })
	end)
	card.MouseLeave:Connect(function()
		tween(card, EASE_FAST, { BackgroundColor3 = Theme.Card })
	end)

	return card, slot, title
end

-- Подсветка карточки при переходе из поиска
local function flashCard(card)
	local s = card:FindFirstChildOfClass("UIStroke")
	if not s then return end
	local base = s.Color
	for i = 1, 2 do
		tween(s, TweenInfo.new(0.18), { Color = Theme.Accent, Transparency = 0 })
		task.wait(0.2)
		tween(s, TweenInfo.new(0.18), { Color = base, Transparency = 0.55 })
		task.wait(0.2)
	end
end

--═══════════════════════════════════════════════════════════════════════
--  10. ОКНО
--═══════════════════════════════════════════════════════════════════════

local Window = {}
Window.__index = Window

function Library:Window(opts)
	opts = opts or {}
	local self = setmetatable({}, Window)

	self.Title      = opts.Title or "Aurora"
	self.Subtitle   = opts.Subtitle or ("v" .. Library.Version)
	self.Tabs       = {}
	self.ActiveTab  = nil
	self.ConfigName = opts.Config or opts.ConfigKey
	self.Acrylic    = opts.Acrylic ~= false
	self.Minimized  = false
	self.Hidden     = false
	self.ToggleKey  = opts.ToggleKey or Enum.KeyCode.RightShift
	self.MinSize    = opts.MinSize or Vector2.new(600, 400)

	local size = opts.Size or UDim2.fromOffset(760, 500)

	--── корпус ──
	local Main = new("Frame", {
		Parent = Gui,
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = size,
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Backdrop" },
	}, { corner(14) })
	self.Frame = Main

	new("ImageLabel", {  -- мягкая тень под окном
		Parent = Main,
		BackgroundTransparency = 1,
		Image = "rbxassetid://5554236805",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.35,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(23, 23, 277, 277),
		Size = UDim2.new(1, 60, 1, 60),
		Position = UDim2.fromOffset(-30, -30),
		ZIndex = 0,
	})

	stroke("Stroke", 1, 0.2).Parent = Main

	local Clip = new("Frame", {
		Parent = Main,
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, { corner(14) })
	self.Clip = Clip

	--═══ ЛЕВАЯ ПАНЕЛЬ ═══
	local SIDEBAR_W = opts.SidebarWidth or 200

	local Sidebar = new("Frame", {
		Parent = Clip,
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_W, 1, 0),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Sidebar" },
	})

	new("Frame", {  -- разделитель между панелью и контентом
		Parent = Sidebar,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.4,
		Theme = { BackgroundColor3 = "Stroke" },
	})

	--── шапка панели: логотип + название ──
	local Brand = new("Frame", {
		Parent = Sidebar,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
	})

	local logo = new("Frame", {
		Parent = Brand,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(24, 24),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Accent" },
	}, {
		corner(7),
		registerGradient(new("UIGradient", { Rotation = 45 }), "Accent", "Accent2"),
	})

	label({
		Parent = Brand,
		Position = UDim2.fromOffset(50, 15),
		Size = UDim2.new(1, -60, 0, 15),
		Font = FONT_B,
		TextSize = 13.5,
		Text = self.Title,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label({
		Parent = Brand,
		Position = UDim2.fromOffset(50, 30),
		Size = UDim2.new(1, -60, 0, 13),
		Font = FONT,
		TextSize = 11,
		Text = self.Subtitle,
		Theme = { TextColor3 = "Muted" },
	})

	--── поиск по всем вкладкам ──
	local SearchBox = new("Frame", {
		Parent = Sidebar,
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -24, 0, 32),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(9), stroke("Stroke", 1, 0.5) })

	label({
		Parent = SearchBox,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.fromOffset(16, 32),
		TextSize = 12,
		Text = "⌕",
		Theme = { TextColor3 = "Muted" },
	})

	local SearchInput = new("TextBox", {
		Parent = SearchBox,
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -38, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		Text = "",
		PlaceholderText = "Поиск по настройкам",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "Muted" },
	})

	--── список вкладок ──
	local TabList = new("ScrollingFrame", {
		Parent = Sidebar,
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 1, -142),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Theme = { ScrollBarImageColor3 = "Muted" },
	}, { padding(4, 8, 12, 12), list(4) })
	self.TabList = TabList

	--── подвал панели ──
	local Footer = new("Frame", {
		Parent = Sidebar,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
	})
	new("Frame", {
		Parent = Footer,
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.fromOffset(12, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.5,
		Theme = { BackgroundColor3 = "Stroke" },
	})
	label({
		Parent = Footer,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 1, 0),
		Font = FONT,
		TextSize = 11,
		Text = (LocalPlayer and LocalPlayer.DisplayName or "игрок")
			.. "  ·  " .. tostring(self.ToggleKey.Name),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Muted" },
	})

	--═══ ПРАВАЯ ЧАСТЬ ═══
	local Content = new("Frame", {
		Parent = Clip,
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_W, 0),
		Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Content" },
	})
	self.Content = Content

	--── верхняя полоса: заголовок вкладки + кнопки окна ──
	local TopBar = new("Frame", {
		Parent = Content,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
	})

	local TabTitle = label({
		Parent = TopBar,
		Position = UDim2.fromOffset(22, 13),
		Size = UDim2.new(1, -140, 0, 17),
		Font = FONT_B,
		TextSize = 15,
		Text = "",
	})
	local TabDesc = label({
		Parent = TopBar,
		Position = UDim2.fromOffset(22, 31),
		Size = UDim2.new(1, -140, 0, 13),
		Font = FONT,
		TextSize = 11.5,
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "SubText" },
	})
	self.TabTitle = TabTitle
	self.TabDesc  = TabDesc

	new("Frame", {
		Parent = TopBar,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.4,
		Theme = { BackgroundColor3 = "Stroke" },
	})

	local function winButton(glyph, offsetX, hoverKey)
		local b = new("TextButton", {
			Parent = TopBar,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, offsetX, 0, 16),
			Size = UDim2.fromOffset(26, 24),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = FONT_B,
			TextSize = 13,
			Text = glyph,
			Theme = { TextColor3 = "Muted" },
		}, { corner(7) })
		b.MouseEnter:Connect(function()
			tween(b, EASE_FAST, { BackgroundTransparency = 0.88, TextColor3 = Theme[hoverKey] })
			b.BackgroundColor3 = Theme[hoverKey]
		end)
		b.MouseLeave:Connect(function()
			tween(b, EASE_FAST, { BackgroundTransparency = 1, TextColor3 = Theme.Muted })
		end)
		return b
	end

	local BtnClose = winButton("✕", -14, "Bad")
	local BtnMin   = winButton("—", -46, "Accent")

	--── прокручиваемая область страницы ──
	local Pages = new("Frame", {
		Parent = Content,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	self.Pages = Pages

	--── ручка изменения размера ──
	local Grip = new("TextButton", {
		Parent = Clip,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "◢",
		Font = FONT,
		TextSize = 11,
		ZIndex = 20,
		Theme = { TextColor3 = "Muted" },
	})

	Grip.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		local origin = input.Position
		local startSize = Main.AbsoluteSize
		activeDrag = function(i)
			local d = i.Position - origin
			Main.Size = UDim2.fromOffset(
				math.max(self.MinSize.X, startSize.X + d.X),
				math.max(self.MinSize.Y, startSize.Y + d.Y)
			)
		end
	end)

	--── перетаскивание за верхнюю полосу и шапку панели ──
	draggable(TopBar, Main, closePopup)
	draggable(Brand, Main, closePopup)

	--═══ ПОВЕДЕНИЕ ОКНА ═══
	local savedSize = size

	function self:SetMinimized(state)
		if self.Minimized == state then return end
		self.Minimized = state
		closePopup()
		if state then
			savedSize = UDim2.fromOffset(Main.AbsoluteSize.X, Main.AbsoluteSize.Y)
			Sidebar.Visible = false
			Pages.Visible = false
			Grip.Visible = false
			tween(Main, EASE, { Size = UDim2.fromOffset(320, 56) })
			Content.Position = UDim2.new()
			Content.Size = UDim2.fromScale(1, 1)
			BtnMin.Text = "+"
		else
			tween(Main, EASE, { Size = savedSize })
			task.delay(0.22, function()
				Sidebar.Visible = true
				Pages.Visible = true
				Grip.Visible = true
				Content.Position = UDim2.fromOffset(SIDEBAR_W, 0)
				Content.Size = UDim2.new(1, -SIDEBAR_W, 1, 0)
			end)
			BtnMin.Text = "—"
		end
	end

	function self:SetVisible(state)
		self.Hidden = not state
		closePopup()
		if state then
			Main.Visible = true
			tween(Main, EASE, { Size = savedSize })
			if self.Acrylic then setBlur(14) end
		else
			if self.Acrylic then setBlur(0) end
			tween(Main, EASE_FAST, { Size = UDim2.fromOffset(savedSize.X.Offset, 0) })
			task.delay(0.14, function() Main.Visible = false end)
		end
		if self.FloatButton then self.FloatButton.Visible = not state end
	end

	function self:Toggle() self:SetVisible(self.Hidden) end

	function self:Notify(o) return Library:Notify(o) end

	BtnMin.MouseButton1Click:Connect(function() self:SetMinimized(not self.Minimized) end)
	BtnClose.MouseButton1Click:Connect(function()
		Library:Dialog{
			Title = "Закрыть " .. self.Title .. "?",
			Content = "Интерфейс будет выгружен. Активные функции скрипта продолжат работать.",
			Buttons = {
				{ Text = "Закрыть", Primary = true, Callback = function() Library:Destroy() end },
				{ Text = "Отмена" },
			},
		}
	end)

	-- клавиша показать/скрыть
	onInput("Began", function(input, processed)
		if processed or self.Hidden == nil then return end
		if input.KeyCode == self.ToggleKey then self:Toggle() end
	end)

	--── плавающая кнопка для телефонов ──
	if UserInput.TouchEnabled then
		local float = new("TextButton", {
			Parent = Gui,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 16, 0.5, 0),
			Size = UDim2.fromOffset(46, 46),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = FONT_B,
			TextSize = 16,
			Text = "◈",
			Visible = false,
			ZIndex = 800,
			Theme = { BackgroundColor3 = "Card", TextColor3 = "Accent" },
		}, { corner(23), stroke("Accent", 1, 0.4) })
		float.MouseButton1Click:Connect(function() self:SetVisible(true) end)
		draggable(float, float)
		self.FloatButton = float
	end

	--── появление окна ──
	Main.Size = UDim2.fromOffset(size.X.Offset, 0)
	tween(Main, EASE_SLOW, { Size = size })
	if self.Acrylic then setBlur(14) end

	--═══ ПОИСК / КОМАНДНАЯ ПАЛИТРА ═══
	local Results = new("Frame", {
		Parent = Overlay,
		Size = UDim2.fromOffset(280, 0),
		Visible = false,
		ZIndex = 600,
		ClipsDescendants = true,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(10), stroke("Stroke", 1, 0.2) })

	local ResultList = new("ScrollingFrame", {
		Parent = Results,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 601,
	}, { padding(6, 6, 6, 6), list(3) })

	local function hideResults()
		Results.Visible = false
		tween(Results, EASE_FAST, { Size = UDim2.fromOffset(280, 0) })
	end

	local function runSearch(query)
		for _, c in ipairs(ResultList:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if #query < 2 then hideResults() return end

		local found = 0
		for _, entry in ipairs(Library.SearchIndex) do
			if entry.window == self and entry.name:lower():find(query, 1, true) then
				found += 1
				if found > 8 then break end

				local item = new("TextButton", {
					Parent = ResultList,
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					BorderSizePixel = 0,
					Text = "",
					LayoutOrder = found,
					ZIndex = 602,
				}, { corner(8) })

				label({
					Parent = item,
					Position = UDim2.fromOffset(10, 5),
					Size = UDim2.new(1, -20, 0, 15),
					TextSize = 12.5,
					Text = entry.name,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 603,
				})
				label({
					Parent = item,
					Position = UDim2.fromOffset(10, 20),
					Size = UDim2.new(1, -20, 0, 13),
					Font = FONT,
					TextSize = 11,
					Text = entry.tab.Name .. "  ·  " .. entry.kind,
					ZIndex = 603,
					Theme = { TextColor3 = "Muted" },
				})

				item.MouseEnter:Connect(function()
					item.BackgroundColor3 = Theme.CardHover
					tween(item, EASE_FAST, { BackgroundTransparency = 0 })
				end)
				item.MouseLeave:Connect(function()
					tween(item, EASE_FAST, { BackgroundTransparency = 1 })
				end)
				item.MouseButton1Click:Connect(function()
					self:SelectTab(entry.tab)
					SearchInput.Text = ""
					hideResults()
					task.spawn(flashCard, entry.card)
				end)
			end
		end

		if found == 0 then hideResults() return end
		Results.Visible = true
		Results.Position = UDim2.fromOffset(
			SearchBox.AbsolutePosition.X,
			SearchBox.AbsolutePosition.Y + 38
		)
		tween(Results, EASE, { Size = UDim2.fromOffset(280, math.min(found, 5) * 41 + 12) })
	end

	SearchInput:GetPropertyChangedSignal("Text"):Connect(function()
		runSearch(SearchInput.Text)
	end)
	SearchInput.FocusLost:Connect(function()
		task.delay(0.15, function()
			if SearchInput.Text == "" then hideResults() end
		end)
	end)

	table.insert(Library.Windows, self)
	table.insert(Library._unloadFns, function()
		if self.Acrylic then setBlur(0) end
	end)

	return self
end

--═══════════════════════════════════════════════════════════════════════
--  11. ВКЛАДКИ
--═══════════════════════════════════════════════════════════════════════

local Tab = {}
Tab.__index = Tab

function Window:SelectTab(tab)
	if self.ActiveTab == tab then return end
	closePopup()

	for _, t in ipairs(self.Tabs) do
		local active = (t == tab)
		t.Page.Visible = active
		tween(t.Button, EASE_FAST, {
			BackgroundTransparency = active and 0 or 1,
		})
		t.Button.BackgroundColor3 = Theme.Card
		tween(t.Label, EASE_FAST, { TextColor3 = active and Theme.Text or Theme.SubText })
		if t.Icon then
			tween(t.Icon, EASE_FAST, { TextColor3 = active and Theme.Accent or Theme.Muted })
		end
		tween(t.Marker, EASE, {
			Size = UDim2.new(0, 3, 0, active and 16 or 0),
			BackgroundTransparency = active and 0 or 1,
		})
	end

	self.ActiveTab = tab
	if self.TabTitle then self.TabTitle.Text = tab.Name end
	if self.TabDesc then self.TabDesc.Text = tab.Desc or "" end

	-- Мягкое появление страницы. Двигаем саму страницу, а не её детей:
	-- позицией детей управляет UIListLayout, и анимировать их бесполезно.
	tab.Page.Position = UDim2.fromOffset(0, 12)
	tween(tab.Page, EASE, { Position = UDim2.fromOffset(0, 0) })
end

function Window:Tab(opts)
	opts = opts or {}
	local tab = setmetatable({}, Tab)
	tab.Name   = opts.Name or opts.Text or "Вкладка"
	tab.Desc   = opts.Desc
	tab.Window = self
	tab.Items  = {}
	tab._order = 0

	--── кнопка в сайдбаре ──
	local btn = new("TextButton", {
		Parent = self.TabList,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = #self.Tabs + 1,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(8) })

	local marker = new("Frame", {
		Parent = btn,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.new(0, 3, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(2) })

	local iconLbl
	local textX = 12
	if opts.Icon then
		textX = 34
		if tostring(opts.Icon):match("^rbxassetid") or tostring(opts.Icon):match("^%d+$") then
			new("ImageLabel", {
				Parent = btn,
				Position = UDim2.fromOffset(10, 9),
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				Image = tostring(opts.Icon):match("^%d+$")
					and ("rbxassetid://" .. opts.Icon) or opts.Icon,
				Theme = { ImageColor3 = "Muted" },
			})
		else
			iconLbl = label({
				Parent = btn,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(16, 34),
				TextSize = 12,
				Text = tostring(opts.Icon),
				TextXAlignment = Enum.TextXAlignment.Center,
				Theme = { TextColor3 = "Muted" },
			})
		end
	end

	local nameLbl = label({
		Parent = btn,
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX - 8, 1, 0),
		TextSize = 12.5,
		Text = tab.Name,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "SubText" },
	})

	btn.MouseEnter:Connect(function()
		if self.ActiveTab ~= tab then
			tween(btn, EASE_FAST, { BackgroundTransparency = 0.55 })
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.ActiveTab ~= tab then
			tween(btn, EASE_FAST, { BackgroundTransparency = 1 })
		end
	end)
	btn.MouseButton1Click:Connect(function() self:SelectTab(tab) end)

	tab.Button = btn
	tab.Label  = nameLbl
	tab.Icon   = iconLbl
	tab.Marker = marker

	--── страница ──
	tab.Page = new("ScrollingFrame", {
		Parent = self.Pages,
		Name = "Page_" .. tab.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Theme = { ScrollBarImageColor3 = "Muted" },
	}, { padding(16, 20, 20, 16), list(7) })

	table.insert(self.Tabs, tab)
	if not self.ActiveTab then self:SelectTab(tab) end
	return tab
end

--── регистрация элемента в поиске ──
local function index(tab, name, kind, card)
	table.insert(Library.SearchIndex, {
		window = tab.Window, tab = tab, name = name, kind = kind, card = card,
	})
end

local function nextOrder(tab)
	tab._order += 1
	return tab._order
end

--═══════════════════════════════════════════════════════════════════════
--  12. ВИДЖЕТЫ
--═══════════════════════════════════════════════════════════════════════

--────────────────────────── Заголовок секции ──────────────────────────
function Tab:Section(opts)
	opts = opts or {}
	local holder = new("Frame", {
		Parent = self.Page,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	})
	local lbl = label({
		Parent = holder,
		Position = UDim2.fromOffset(4, 8),
		Size = UDim2.new(1, -8, 0, 14),
		Font = FONT_B,
		TextSize = 11,
		Text = string.upper(opts.Text or opts.Name or "Секция"),
		Theme = { TextColor3 = "Muted" },
	})
	return {
		Set = function(_, text) lbl.Text = string.upper(text) end,
		Destroy = function() holder:Destroy() end,
	}
end

--──────────────────────────── Разделитель ────────────────────────────
function Tab:Divider()
	local holder = new("Frame", {
		Parent = self.Page,
		Size = UDim2.new(1, 0, 0, 11),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	})
	new("Frame", {
		Parent = holder,
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.5,
		Theme = { BackgroundColor3 = "Stroke" },
	})
	return { Destroy = function() holder:Destroy() end }
end

--────────────────────────────── Текст ──────────────────────────────
function Tab:Paragraph(opts)
	opts = opts or {}
	local card = new("Frame", {
		Parent = self.Page,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(self),
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(10), stroke("Stroke", 1, 0.55), padding(12, 12, 14, 14), list(4) })

	local title = label({
		Parent = card,
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 13,
		Text = opts.Text or opts.Title or "Заметка",
		LayoutOrder = 1,
	})
	local body = label({
		Parent = card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 12,
		Text = opts.Content or opts.Desc or "",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
		Theme = { TextColor3 = "SubText" },
	})

	index(self, title.Text, "текст", card)
	return {
		Set = function(_, t, c)
			if t then title.Text = t end
			if c then body.Text = c end
		end,
		Destroy = function() card:Destroy() end,
	}
end

--────────────────────────────── Кнопка ──────────────────────────────
function Tab:Button(opts)
	opts = opts or {}
	local card, slot = makeCard(self.Page, opts, nextOrder(self))
	slot.Size = UDim2.fromOffset(110, 30)

	local btn = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(110, 30),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_M,
		TextSize = 12,
		Text = opts.ButtonText or "Выполнить",
		Theme = { BackgroundColor3 = "Inset", TextColor3 = "Text" },
	}, { corner(8), stroke("Stroke", 1, 0.3) })

	btn.MouseEnter:Connect(function()
		tween(btn, EASE_FAST, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.Backdrop })
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, EASE_FAST, { BackgroundColor3 = Theme.Inset, TextColor3 = Theme.Text })
	end)
	btn.MouseButton1Click:Connect(function()
		tween(btn, TweenInfo.new(0.08), { Size = UDim2.fromOffset(104, 28) })
		task.delay(0.09, function()
			tween(btn, EASE_FAST, { Size = UDim2.fromOffset(110, 30) })
		end)
		if opts.Confirm then
			Library:Dialog{
				Title = opts.Text or "Подтверждение",
				Content = opts.Confirm == true and "Выполнить это действие?" or tostring(opts.Confirm),
				Buttons = {
					{ Text = "Да", Primary = true, Callback = opts.Callback },
					{ Text = "Отмена" },
				},
			}
		else
			safeCall(opts.Callback)
		end
	end)

	index(self, opts.Text or "Кнопка", "кнопка", card)
	return { Destroy = function() card:Destroy() end, Card = card }
end

--────────────────────────────── Тоггл ──────────────────────────────
function Tab:Toggle(opts)
	opts = opts or {}
	local card, slot = makeCard(self.Page, opts, nextOrder(self))
	local state = opts.Default == true

	-- Именно Frame, а не TextButton: кликом ловим всю строку целиком
	-- через card.InputBegan. Будь тут кнопка, клик по переключателю
	-- сработал бы дважды — и на кнопке, и всплытием на карточке.
	local track_ = new("Frame", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(42, 24),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(12), stroke("Stroke", 1, 0.3) })

	local knob = new("Frame", {
		Parent = track_,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(18, 18),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Muted" },
	}, { corner(9) })

	local obj = {}

	function obj:Set(value, silent)
		state = value and true or false
		tween(track_, EASE, { BackgroundColor3 = state and Theme.Accent or Theme.Inset })
		tween(knob, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
			BackgroundColor3 = state and Theme.Backdrop or Theme.Muted,
		})
		if opts.Flag then Library.Flags[opts.Flag] = state end
		if not silent then safeCall(opts.Callback, state) end
	end

	function obj:Get() return state end
	function obj:Destroy() card:Destroy() end
	obj.Card = card

	card.InputBegan:Connect(function(input)
		if isPressStart(input) then obj:Set(not state) end
	end)

	obj:Set(state, true)
	if opts.Flag then Library.Options[opts.Flag] = obj end
	index(self, opts.Text or "Тоггл", "переключатель", card)
	return obj
end

--────────────────────────────── Слайдер ──────────────────────────────
function Tab:Slider(opts)
	opts = opts or {}
	opts.Height = opts.Desc and 62 or 54
	local card, slot, titleLbl = makeCard(self.Page, opts, nextOrder(self))
	slot.Visible = false
	-- у слайдера низ карточки занимает полоса, поэтому заголовок
	-- прижимаем к верху, а не центрируем по всей высоте
	titleLbl.Position = UDim2.fromOffset(14, 9)
	titleLbl.Size = UDim2.new(1, -110, 0, 16)

	local minV     = opts.Min or 0
	local maxV     = opts.Max or 100
	local decimals = opts.Decimals or 0
	local suffix   = opts.Suffix or ""
	local value    = math.clamp(opts.Default or minV, minV, maxV)

	local valueLbl = label({
		Parent = card,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, opts.Desc and 9 or 8),
		Size = UDim2.fromOffset(90, 16),
		Font = FONT_B,
		TextSize = 12.5,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Theme = { TextColor3 = "Accent" },
	})

	local bar = new("Frame", {
		Parent = card,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.new(1, -28, 0, 6),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(3) })

	local fill = new("Frame", {
		Parent = bar,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Accent" },
	}, {
		corner(3),
		registerGradient(new("UIGradient", {}), "Accent", "Accent2"),
	})

	local knob = new("Frame", {
		Parent = bar,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BorderSizePixel = 0,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Text" },
	}, { corner(6) })

	local obj = {}

	function obj:Set(v, silent)
		value = math.clamp(round(v, decimals), minV, maxV)
		local alpha = (maxV - minV) == 0 and 0 or (value - minV) / (maxV - minV)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLbl.Text = tostring(value) .. suffix
		if opts.Flag then Library.Flags[opts.Flag] = value end
		if not silent then safeCall(opts.Callback, value) end
	end

	function obj:Get() return value end
	function obj:Destroy() card:Destroy() end
	obj.Card = card

	local function fromX(px)
		local alpha = clamp01((px - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X))
		obj:Set(minV + (maxV - minV) * alpha)
	end

	bar.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		tween(knob, EASE_FAST, { Size = UDim2.fromOffset(16, 16) })
		fromX(input.Position.X)
		activeDrag = function(i) fromX(i.Position.X) end
	end)
	onInput("Ended", function(input)
		if isPressStart(input) then
			tween(knob, EASE_FAST, { Size = UDim2.fromOffset(12, 12) })
		end
	end)

	obj:Set(value, true)
	if opts.Flag then Library.Options[opts.Flag] = obj end
	index(self, opts.Text or "Слайдер", "слайдер", card)
	return obj
end

--──────────────────────────── Выпадающий список ────────────────────────────
function Tab:Dropdown(opts)
	opts = opts or {}
	local card, slot = makeCard(self.Page, opts, nextOrder(self))
	slot.Size = UDim2.fromOffset(160, 30)

	local options  = opts.Options or opts.Values or {}
	local multi    = opts.Multi == true
	local selected = multi and {} or nil

	local button = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(160, 30),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(8), stroke("Stroke", 1, 0.3) })

	local display = label({
		Parent = button,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -30, 1, 0),
		Font = FONT,
		TextSize = 12,
		Text = opts.Placeholder or "Не выбрано",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "SubText" },
	})

	local arrow = label({
		Parent = button,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		TextSize = 10,
		Text = "▾",
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "Muted" },
	})

	--── меню в слое оверлея ──
	local menu = new("Frame", {
		Parent = Overlay,
		Size = UDim2.fromOffset(160, 0),
		Visible = false,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 610,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(9), stroke("Stroke", 1, 0.2) })

	local search
	local scroll = new("ScrollingFrame", {
		Parent = menu,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 611,
	}, { padding(5, 5, 5, 5), list(2) })

	if opts.Search then
		search = new("TextBox", {
			Parent = menu,
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.new(1, -10, 0, 26),
			BorderSizePixel = 0,
			Font = FONT,
			TextSize = 12,
			Text = "",
			PlaceholderText = "Фильтр…",
			ClearTextOnFocus = false,
			ZIndex = 613,
			Theme = { BackgroundColor3 = "Inset", TextColor3 = "Text", PlaceholderColor3 = "Muted" },
		}, { corner(7), padding(0, 0, 8, 8) })
		scroll.Position = UDim2.fromOffset(0, 32)
		scroll.Size = UDim2.new(1, 0, 1, -32)
	end

	local obj = {}
	local isOpen = false
	local rows = {}

	local function isSelected(v)
		if multi then
			for _, s in ipairs(selected) do if s == v then return true end end
			return false
		end
		return selected == v
	end

	local function refreshDisplay()
		if multi then
			if #selected == 0 then
				display.Text = opts.Placeholder or "Не выбрано"
				display.TextColor3 = Theme.SubText
			elseif #selected <= 2 then
				display.Text = table.concat(selected, ", ")
				display.TextColor3 = Theme.Text
			else
				display.Text = "Выбрано: " .. #selected
				display.TextColor3 = Theme.Text
			end
		else
			display.Text = selected ~= nil and tostring(selected) or (opts.Placeholder or "Не выбрано")
			display.TextColor3 = selected ~= nil and Theme.Text or Theme.SubText
		end
	end

	local function rowHeight()
		local visible = 0
		for _, r in ipairs(rows) do if r.frame.Visible then visible += 1 end end
		return math.min(visible, 6) * 28 + 10 + (search and 32 or 0)
	end

	local function place()
		local vp = viewport()
		local h = rowHeight()
		local x = button.AbsolutePosition.X
		local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y + 4
		if y + h > vp.Y - 10 then
			y = button.AbsolutePosition.Y - h - 4
		end
		menu.Position = UDim2.fromOffset(x, y)
	end

	local stopFollow
	local function close()
		if not isOpen then return end
		isOpen = false
		if openPopup == close then openPopup = nil end
		if stopFollow then stopFollow() stopFollow = nil end
		tween(arrow, EASE_FAST, { Rotation = 0 })
		tween(menu, EASE_FAST, { Size = UDim2.fromOffset(button.AbsoluteSize.X, 0) })
		task.delay(0.13, function() menu.Visible = false end)
	end

	local function open()
		closePopup()
		isOpen = true
		openPopup = close
		menu.Visible = true
		menu.Size = UDim2.fromOffset(button.AbsoluteSize.X, 0)
		place()
		tween(arrow, EASE_FAST, { Rotation = 180 })
		tween(menu, EASE, { Size = UDim2.fromOffset(button.AbsoluteSize.X, rowHeight()) })
		stopFollow = onRender(place)  -- меню едет за окном
	end

	local function buildRows()
		for _, r in ipairs(rows) do r.frame:Destroy() end
		table.clear(rows)

		for i, value in ipairs(options) do
			local row = new("TextButton", {
				Parent = scroll,
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Text = "",
				LayoutOrder = i,
				ZIndex = 612,
			}, { corner(6) })

			local check = new("Frame", {
				Parent = row,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 7, 0.5, 0),
				Size = UDim2.fromOffset(6, 6),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 613,
				Theme = { BackgroundColor3 = "Accent" },
			}, { corner(3) })

			local text = label({
				Parent = row,
				Position = UDim2.fromOffset(22, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Font = FONT,
				TextSize = 12,
				Text = tostring(value),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 613,
				Theme = { TextColor3 = "SubText" },
			})

			row.MouseEnter:Connect(function()
				row.BackgroundColor3 = Theme.CardHover
				tween(row, EASE_FAST, { BackgroundTransparency = 0 })
			end)
			row.MouseLeave:Connect(function()
				tween(row, EASE_FAST, { BackgroundTransparency = 1 })
			end)
			row.MouseButton1Click:Connect(function()
				if multi then
					if isSelected(value) then
						for idx, s in ipairs(selected) do
							if s == value then table.remove(selected, idx) break end
						end
					else
						table.insert(selected, value)
					end
					obj:Set(selected)
					place()
				else
					obj:Set(value)
					close()
				end
			end)

			table.insert(rows, { frame = row, value = value, check = check, text = text })
		end
	end

	local function paintRows()
		for _, r in ipairs(rows) do
			local on = isSelected(r.value)
			tween(r.check, EASE_FAST, { BackgroundTransparency = on and 0 or 1 })
			tween(r.text, EASE_FAST, { TextColor3 = on and Theme.Text or Theme.SubText })
		end
	end

	function obj:Set(value, silent)
		if multi then
			selected = {}
			if type(value) == "table" then
				for _, v in ipairs(value) do table.insert(selected, v) end
			elseif value ~= nil then
				table.insert(selected, value)
			end
		else
			selected = value
		end
		refreshDisplay()
		paintRows()
		if opts.Flag then
			Library.Flags[opts.Flag] = multi and table.clone(selected) or selected
		end
		if not silent then safeCall(opts.Callback, multi and table.clone(selected) or selected) end
	end

	function obj:Get() return multi and table.clone(selected) or selected end

	-- Главная боль всех библиотек: обновить список на лету.
	function obj:Refresh(newOptions, keepSelection)
		options = newOptions or {}
		buildRows()
		if keepSelection == false then
			obj:Set(multi and {} or nil, true)
		else
			-- выкидываем то, чего больше нет в списке
			if multi then
				local kept = {}
				for _, s in ipairs(selected) do
					for _, o in ipairs(options) do
						if o == s then table.insert(kept, s) break end
					end
				end
				obj:Set(kept, true)
			else
				local found = false
				for _, o in ipairs(options) do
					if o == selected then found = true break end
				end
				if not found then obj:Set(nil, true) else obj:Set(selected, true) end
			end
		end
		if isOpen then
			tween(menu, EASE_FAST, { Size = UDim2.fromOffset(button.AbsoluteSize.X, rowHeight()) })
		end
	end

	function obj:Destroy() close() menu:Destroy() card:Destroy() end
	obj.Card = card

	if search then
		search:GetPropertyChangedSignal("Text"):Connect(function()
			local q = search.Text:lower()
			for _, r in ipairs(rows) do
				r.frame.Visible = (q == "" or tostring(r.value):lower():find(q, 1, true) ~= nil)
			end
			tween(menu, EASE_FAST, { Size = UDim2.fromOffset(button.AbsoluteSize.X, rowHeight()) })
		end)
	end

	button.MouseButton1Click:Connect(function()
		if isOpen then close() else open() end
	end)
	-- клик по самому меню не должен его закрывать
	menu.InputBegan:Connect(function(input)
		if isPressStart(input) then guardPopup() end
	end)

	buildRows()
	obj:Set(opts.Default or (multi and {} or nil), true)
	if opts.Flag then Library.Options[opts.Flag] = obj end
	index(self, opts.Text or "Список", "список", card)
	return obj
end

--──────────────────────────── Поле ввода ────────────────────────────
function Tab:Input(opts)
	opts = opts or {}
	local card, slot = makeCard(self.Page, opts, nextOrder(self))
	slot.Size = UDim2.fromOffset(170, 30)

	local box = new("Frame", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(170, 30),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(8), stroke("Stroke", 1, 0.3) })

	local input = new("TextBox", {
		Parent = box,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "Введите…",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "Muted" },
	})

	local border = box:FindFirstChildOfClass("UIStroke")
	input.Focused:Connect(function()
		tween(border, EASE_FAST, { Color = Theme.Accent, Transparency = 0 })
	end)
	input.FocusLost:Connect(function(enter)
		tween(border, EASE_FAST, { Color = Theme.Stroke, Transparency = 0.3 })
		if opts.Numeric then
			local n = tonumber(input.Text)
			input.Text = n and tostring(n) or ""
		end
		if opts.Flag then Library.Flags[opts.Flag] = input.Text end
		if enter or not opts.OnEnter then safeCall(opts.Callback, input.Text, enter) end
	end)

	local obj = {}
	function obj:Set(v, silent)
		input.Text = tostring(v or "")
		if opts.Flag then Library.Flags[opts.Flag] = input.Text end
		if not silent then safeCall(opts.Callback, input.Text, false) end
	end
	function obj:Get() return input.Text end
	function obj:Destroy() card:Destroy() end
	obj.Card = card

	if opts.Flag then
		Library.Flags[opts.Flag] = input.Text
		Library.Options[opts.Flag] = obj
	end
	index(self, opts.Text or "Поле", "поле ввода", card)
	return obj
end

--────────────────────────────── Кейбинд ──────────────────────────────
function Tab:Keybind(opts)
	opts = opts or {}
	local card, slot = makeCard(self.Page, opts, nextOrder(self))
	slot.Size = UDim2.fromOffset(110, 30)

	local btn = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(110, 30),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_M,
		TextSize = 12,
		Text = "—",
		Theme = { BackgroundColor3 = "Inset", TextColor3 = "SubText" },
	}, { corner(8), stroke("Stroke", 1, 0.3) })

	local entry = { key = nil, fire = function() end }
	table.insert(keybinds, entry)

	local obj = {}

	function obj:Set(key, silent)
		entry.key = key
		btn.Text = key and (typeof(key) == "EnumItem" and key.Name or tostring(key)) or "—"
		btn.TextColor3 = key and Theme.Text or Theme.SubText
		if opts.Flag then Library.Flags[opts.Flag] = key end
		if not silent then safeCall(opts.Callback, key) end
	end

	function obj:Get() return entry.key end
	function obj:Destroy()
		for i, e in ipairs(keybinds) do
			if e == entry then table.remove(keybinds, i) break end
		end
		card:Destroy()
	end
	obj.Card = card

	entry.fire = function()
		if opts.OnPress then safeCall(opts.OnPress, entry.key) end
		if opts.Mode == "toggle" and opts.Flag then
			local target = Library.Options[opts.Toggle or ""]
			if target and target.Set then target:Set(not target:Get()) end
		end
	end

	btn.MouseButton1Click:Connect(function()
		btn.Text = "…"
		btn.TextColor3 = Theme.Accent
		captureTarget = function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				obj:Set(nil)
			elseif input.UserInputType == Enum.UserInputType.Keyboard then
				obj:Set(input.KeyCode)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3 then
				obj:Set(input.UserInputType)
			else
				obj:Set(entry.key)
			end
		end
	end)

	obj:Set(opts.Default, true)
	if opts.Flag then Library.Options[opts.Flag] = obj end
	index(self, opts.Text or "Клавиша", "клавиша", card)
	return obj
end

--──────────────────────────── Выбор цвета ────────────────────────────
function Tab:Colorpicker(opts)
	opts = opts or {}
	local card, slot = makeCard(self.Page, opts, nextOrder(self))
	slot.Size = UDim2.fromOffset(48, 26)

	local color = opts.Default or Color3.fromRGB(122, 140, 255)
	local h, s, v = color:ToHSV()

	local swatchBtn = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(48, 26),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
	}, { corner(7), stroke("Stroke", 1, 0.25) })

	--── поп-ап ──
	local pop = new("Frame", {
		Parent = Overlay,
		Size = UDim2.fromOffset(228, 0),
		Visible = false,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 620,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(11), stroke("Stroke", 1, 0.2) })

	local sv = new("Frame", {
		Parent = pop,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(174, 120),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 621,
	}, { corner(7) })

	new("Frame", {  -- насыщенность: белый слева → прозрачно справа
		Parent = sv,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 622,
	}, {
		corner(7),
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	new("Frame", {  -- яркость: прозрачно сверху → чёрный снизу
		Parent = sv,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 623,
	}, {
		corner(7),
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})

	local svCursor = new("Frame", {
		Parent = sv,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		BackgroundTransparency = 1,
		ZIndex = 625,
	}, { corner(6), new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }) })

	local hue = new("Frame", {
		Parent = pop,
		Position = UDim2.fromOffset(194, 12),
		Size = UDim2.fromOffset(22, 120),
		BorderSizePixel = 0,
		ZIndex = 621,
	}, {
		corner(7),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
			}),
		}),
	})

	local hueCursor = new("Frame", {
		Parent = hue,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 6, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 625,
	}, { corner(2) })

	local hexBox = new("TextBox", {
		Parent = pop,
		Position = UDim2.fromOffset(12, 142),
		Size = UDim2.fromOffset(204, 28),
		BorderSizePixel = 0,
		Font = FONT_M,
		TextSize = 12,
		Text = "",
		ClearTextOnFocus = false,
		ZIndex = 621,
		Theme = { BackgroundColor3 = "Inset", TextColor3 = "Text" },
	}, { corner(7), padding(0, 0, 10, 10) })

	local obj = {}

	function obj:Set(c, silent)
		color = c
		h, s, v = color:ToHSV()
		swatchBtn.BackgroundColor3 = color
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
		hexBox.Text = string.format("#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5))
		if opts.Flag then Library.Flags[opts.Flag] = color end
		if not silent then safeCall(opts.Callback, color) end
	end

	function obj:Get() return color end

	local stopFollow
	local function close()
		if openPopup == close then openPopup = nil end
		if stopFollow then stopFollow() stopFollow = nil end
		tween(pop, EASE_FAST, { Size = UDim2.fromOffset(228, 0) })
		task.delay(0.13, function() pop.Visible = false end)
	end

	local function place()
		local vp = viewport()
		local x = math.min(swatchBtn.AbsolutePosition.X + swatchBtn.AbsoluteSize.X - 228, vp.X - 238)
		local y = swatchBtn.AbsolutePosition.Y + swatchBtn.AbsoluteSize.Y + 6
		if y + 182 > vp.Y - 10 then y = swatchBtn.AbsolutePosition.Y - 188 end
		pop.Position = UDim2.fromOffset(math.max(10, x), y)
	end

	swatchBtn.MouseButton1Click:Connect(function()
		if pop.Visible then close() return end
		closePopup()
		openPopup = close
		pop.Visible = true
		pop.Size = UDim2.fromOffset(228, 0)
		place()
		tween(pop, EASE, { Size = UDim2.fromOffset(228, 182) })
		stopFollow = onRender(place)
	end)

	pop.InputBegan:Connect(function(input)
		if isPressStart(input) then guardPopup() end
	end)

	sv.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		local function upd(i)
			local ns = clamp01((i.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X)
			local nv = 1 - clamp01((i.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y)
			obj:Set(Color3.fromHSV(h, ns, nv))
		end
		upd(input)
		activeDrag = upd
	end)

	hue.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		local function upd(i)
			local nh = clamp01((i.Position.Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y)
			obj:Set(Color3.fromHSV(nh, s, v))
		end
		upd(input)
		activeDrag = upd
	end)

	hexBox.FocusLost:Connect(function()
		local hex = hexBox.Text:gsub("#", "")
		if #hex == 6 and tonumber(hex, 16) then
			obj:Set(Color3.fromHex and Color3.fromHex(hex) or Color3.fromRGB(
				tonumber(hex:sub(1, 2), 16),
				tonumber(hex:sub(3, 4), 16),
				tonumber(hex:sub(5, 6), 16)))
		else
			obj:Set(color, true)
		end
	end)

	function obj:Destroy() close() pop:Destroy() card:Destroy() end
	obj.Card = card

	obj:Set(color, true)
	if opts.Flag then Library.Options[opts.Flag] = obj end
	index(self, opts.Text or "Цвет", "цвет", card)
	return obj
end

--═══════════════════════════════════════════════════════════════════════
--  13. КОНФИГИ
--  Сериализуем Color3 и EnumItem — JSON их сам не умеет.
--═══════════════════════════════════════════════════════════════════════

local function encodeValue(v)
	if typeof(v) == "Color3" then
		return { __t = "Color3", r = v.R, g = v.G, b = v.B }
	elseif typeof(v) == "EnumItem" then
		return { __t = "Enum", e = v.EnumType.Name, n = v.Name }
	elseif type(v) == "table" then
		local out = {}
		for i, item in ipairs(v) do out[i] = encodeValue(item) end
		return out
	end
	return v
end

local function decodeValue(v)
	if type(v) == "table" then
		if v.__t == "Color3" then return Color3.new(v.r, v.g, v.b) end
		if v.__t == "Enum" then
			local ok, item = pcall(function() return Enum[v.e][v.n] end)
			return ok and item or nil
		end
		local out = {}
		for i, item in ipairs(v) do out[i] = decodeValue(item) end
		return out
	end
	return v
end

function Window:ConfigFolder()
	return "AuroraUI/" .. tostring(self.ConfigName or game.PlaceId)
end

local function ensureFolder(path)
	if not FS.isdir or not FS.mkdir then return end
	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
		local sub = table.concat(parts, "/")
		if not FS.isdir(sub) then pcall(FS.mkdir, sub) end
	end
end

function Window:SaveConfig(name)
	if not HAS_FS then
		Library:Notify{ Title = "Конфиги недоступны", Content = "Исполнитель не даёт доступ к файлам.", Type = "warn" }
		return false
	end
	name = name or "default"
	local folder = self:ConfigFolder()
	ensureFolder(folder)

	local data = {}
	for flag, value in next, Library.Flags do
		data[flag] = encodeValue(value)
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then return false end
	local written = pcall(FS.write, folder .. "/" .. name .. ".json", encoded)
	if written then
		Library:Notify{ Title = "Сохранено", Content = "Конфиг «" .. name .. "»", Type = "success" }
	end
	return written
end

function Window:LoadConfig(name)
	if not HAS_FS then return false end
	name = name or "default"
	local path = self:ConfigFolder() .. "/" .. name .. ".json"
	if not FS.isfile(path) then return false end

	local ok, raw = pcall(FS.read, path)
	if not ok then return false end
	local parsed, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not parsed then return false end

	for flag, value in next, data do
		local element = Library.Options[flag]
		if element and element.Set then
			pcall(element.Set, element, decodeValue(value))
		else
			Library.Flags[flag] = decodeValue(value)
		end
	end
	Library:Notify{ Title = "Загружено", Content = "Конфиг «" .. name .. "»", Type = "success" }
	return true
end

function Window:ListConfigs()
	local out = {}
	if not HAS_FS or not FS.list then return out end
	local folder = self:ConfigFolder()
	if FS.isdir and not FS.isdir(folder) then return out end
	local ok, files = pcall(FS.list, folder)
	if not ok then return out end
	for _, path in ipairs(files) do
		local name = tostring(path):match("([^/\\]+)%.json$")
		if name then table.insert(out, name) end
	end
	return out
end

function Window:DeleteConfig(name)
	if not HAS_FS or not FS.delete then return false end
	return pcall(FS.delete, self:ConfigFolder() .. "/" .. name .. ".json")
end

-- Готовая вкладка настроек: конфиги, темы, клавиша, выгрузка.
function Window:SettingsTab(opts)
	opts = opts or {}
	local tab = self:Tab{
		Name = opts.Name or "Настройки",
		Icon = opts.Icon or "⚙",
		Desc = "Тема, конфигурации и управление интерфейсом",
	}

	tab:Section{ Text = "Внешний вид" }

	local themeNames = {}
	for name in next, THEMES do table.insert(themeNames, name) end
	table.sort(themeNames)

	tab:Dropdown{
		Text = "Тема", Desc = "Цветовая схема интерфейса",
		Options = themeNames, Default = Library.ThemeName,
		Callback = function(v) Library:SetTheme(v) end,
	}

	tab:Keybind{
		Text = "Показать / скрыть", Desc = "Клавиша переключения окна",
		Default = self.ToggleKey,
		Callback = function(key) if key then self.ToggleKey = key end end,
	}

	tab:Section{ Text = "Конфигурации" }

	local configDropdown
	local nameInput = tab:Input{
		Text = "Имя конфига", Placeholder = "например: pvp", Default = "default",
	}

	tab:Button{
		Text = "Сохранить", Desc = "Записать текущие значения всех элементов",
		ButtonText = "Сохранить",
		Callback = function()
			self:SaveConfig(nameInput:Get())
			if configDropdown then configDropdown:Refresh(self:ListConfigs()) end
		end,
	}

	configDropdown = tab:Dropdown{
		Text = "Загрузить", Desc = "Выберите сохранённую конфигурацию",
		Options = self:ListConfigs(), Search = true,
		Callback = function(v) if v then self:LoadConfig(v) end end,
	}

	tab:Button{
		Text = "Обновить список", ButtonText = "Обновить",
		Callback = function() configDropdown:Refresh(self:ListConfigs()) end,
	}

	tab:Section{ Text = "Опасная зона" }

	tab:Button{
		Text = "Выгрузить интерфейс",
		Desc = "Закрыть окно и освободить память",
		ButtonText = "Выгрузить",
		Confirm = "Интерфейс будет полностью удалён. Продолжить?",
		Callback = function() Library:Destroy() end,
	}

	return tab
end

--═══════════════════════════════════════════════════════════════════════
--  14. СМЕНА ТЕМЫ
--═══════════════════════════════════════════════════════════════════════

function Library:SetTheme(name)
	local preset = THEMES[name]
	if not preset then return false end
	self.ThemeName = name
	for k, v in next, preset do Theme[k] = v end

	for i = #ThemeRegistry, 1, -1 do
		local entry = ThemeRegistry[i]
		if not entry.inst or not entry.inst.Parent then
			table.remove(ThemeRegistry, i)
		else
			tween(entry.inst, EASE, { [entry.prop] = Theme[entry.key] })
		end
	end

	for i = #GradientRegistry, 1, -1 do
		local entry = GradientRegistry[i]
		if not entry.inst or not entry.inst.Parent then
			table.remove(GradientRegistry, i)
		else
			entry.inst.Color = ColorSequence.new(Theme[entry.a], Theme[entry.b])
		end
	end

	self:Notify{ Title = "Тема изменена", Content = name, Type = "success" }
	return true
end

--═══════════════════════════════════════════════════════════════════════
--  15. ВЫГРУЗКА
--═══════════════════════════════════════════════════════════════════════

function Library:Destroy()
	if not self.Alive then return end
	self.Alive = false

	for _, fn in ipairs(self._unloadFns) do pcall(fn) end
	for _, conn in ipairs(self._conns) do pcall(function() conn:Disconnect() end) end

	table.clear(self._conns)
	table.clear(self._render)
	table.clear(Dispatch.Began)
	table.clear(Dispatch.Changed)
	table.clear(Dispatch.Ended)
	table.clear(keybinds)
	table.clear(ThemeRegistry)
	table.clear(self.SearchIndex)

	if Blur then pcall(function() Blur:Destroy() end) end
	if Gui then
		pcall(function()
			for _, w in ipairs(self.Windows) do
				tween(w.Frame, EASE_FAST, { Size = UDim2.fromOffset(w.Frame.AbsoluteSize.X, 0) })
			end
		end)
		task.delay(0.2, function() pcall(function() Gui:Destroy() end) end)
	end

	if ENV.AuroraUI == self then ENV.AuroraUI = nil end
end

Library.Unload = Library.Destroy

ENV.AuroraUI = Library
return Library
