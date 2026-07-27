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
║   local Main = Win:Tab{ Name = "Главная", Icon = "gamepad-2" }       ║
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

local LocalPlayer = Players and Players.LocalPlayer
local ENV = (typeof(getgenv) == "function") and getgenv() or _G

-- Загрузи PNG из assets/aurora в Roblox и впиши только id.
-- Пустой Id безопасен: соответствующий декоративный слой просто не создаётся.
-- SliceCenter уже соответствует приложенным файлам и менять его не нужно.
local ASSETS = {
	SoftShadow = {
		Id = "139518356096651",
		File = "assets/aurora/soft-shadow.png",
		SliceCenter = Rect.new(32, 32, 96, 96),
	},
	InnerShadow = {
		Id = "75184533556503",
		File = "assets/aurora/inner-shadow.png",
		SliceCenter = Rect.new(24, 24, 72, 72),
	},
	AccentGlow = {
		Id = "114203407815508",
		File = "assets/aurora/accent-glow.png",
		SliceCenter = Rect.new(40, 24, 88, 40),
		SliceScale = 0.5,
	},
	SurfaceNoise = {
		Id = "114070601377247",
		File = "assets/aurora/surface-noise.png",
		TileSize = UDim2.fromOffset(128, 128),
	},
}

-- В executor-demo можно использовать те же PNG локально, не загружая их
-- в Roblox. Для обычного распространения Id остаются единственным
-- источником и по-прежнему заполняются вручную.
if typeof(getcustomasset) == "function" and typeof(isfile) == "function" then
	for _, def in next, ASSETS do
		if def.Id == "" and def.File then
			for _, candidate in ipairs({ def.File, "AuroraUI/" .. def.File }) do
				local exists = false
				pcall(function() exists = isfile(candidate) end)
				if exists then
					local ok, uri = pcall(getcustomasset, candidate)
					if ok and uri then def.Id = uri break end
				end
			end
		end
	end
end

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

local function resolveHttpRequest()
	if typeof(request) == "function" then return request end
	if typeof(http_request) == "function" then return http_request end
	if typeof(syn) == "table" and typeof(syn.request) == "function" then return syn.request end
	if typeof(http) == "table" and typeof(http.request) == "function" then return http.request end
	if typeof(fluxus) == "table" and typeof(fluxus.request) == "function" then return fluxus.request end
	return nil
end

local function requestJSON(method, url, body)
	if not HttpService then return nil, "HttpService is unavailable." end
	if type(url) ~= "string" or #url > 2048
		or not (url:match("^https://") or url:match("^http://localhost[:/]")) then
		return nil, "The key server URL is invalid."
	end
	local requester = resolveHttpRequest()
	if not requester then
		return nil, "This executor does not support HTTP requests."
	end

	local encoded
	if body ~= nil then
		local ok, result = pcall(HttpService.JSONEncode, HttpService, body)
		if not ok then return nil, "Could not encode the server request." end
		encoded = result
	end

	local ok, response = pcall(requester, {
		Url = url,
		URL = url,
		Method = method,
		Headers = {
			["Accept"] = "application/json",
			["Content-Type"] = "application/json",
		},
		Body = encoded,
	})
	if not ok or type(response) ~= "table" then
		return nil, "Could not contact the key server."
	end

	local status = tonumber(response.StatusCode or response.Status) or 0
	local raw = response.Body or response.body
	if type(raw) ~= "string" or #raw > 65536 then
		return nil, "The key server returned an invalid response."
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decoded or type(data) ~= "table" then
		return nil, "The key server returned invalid JSON."
	end
	if status < 200 or status >= 300 then
		local message = data.message or data.Message
		return nil, message ~= nil and tostring(message) or "Key server request failed."
	end
	return data
end

-- Гасим предыдущую копию библиотеки, если она уже висит в памяти
if ENV.AuroraUI and type(ENV.AuroraUI.Destroy) == "function" then
	pcall(ENV.AuroraUI.Destroy, ENV.AuroraUI)
end

--═══════════════════════════════════════════════════════════════════════
--  1. ТЕМЫ
--═══════════════════════════════════════════════════════════════════════

-- Палитра почти нейтральная: цветной остаётся только акцентная линия.
-- Синевато-серые фоны читаются дёшево, а ровные ступени яркости
-- (Backdrop → Sidebar → Content → Card) дают ощущение глубины.
local THEMES = {
	Aurora = {
		Backdrop   = Color3.fromRGB(7, 8, 11),       -- корпус окна
		Sidebar    = Color3.fromRGB(11, 12, 17),     -- левая панель
		Content    = Color3.fromRGB(14, 15, 20),     -- рабочая область
		Card       = Color3.fromRGB(20, 22, 29),     -- строка элемента
		CardHover  = Color3.fromRGB(28, 30, 40),
		Inset      = Color3.fromRGB(8, 9, 13),       -- утопленные поля
		Stroke     = Color3.fromRGB(49, 51, 66),
		StrokeSoft = Color3.fromRGB(31, 33, 43),
		Text       = Color3.fromRGB(246, 246, 250),
		SubText    = Color3.fromRGB(158, 159, 174),
		Muted      = Color3.fromRGB(101, 103, 120),
		Accent     = Color3.fromRGB(124, 92, 255),
		Accent2    = Color3.fromRGB(178, 104, 255),
		Good       = Color3.fromRGB(52, 199, 123),
		Warn       = Color3.fromRGB(245, 180, 70),
		Bad        = Color3.fromRGB(250, 90, 110),
	},
	Midnight = {
		Backdrop   = Color3.fromRGB(8, 10, 12),
		Sidebar    = Color3.fromRGB(12, 14, 17),
		Content    = Color3.fromRGB(16, 19, 23),
		Card       = Color3.fromRGB(23, 27, 32),
		CardHover  = Color3.fromRGB(31, 36, 43),
		Inset      = Color3.fromRGB(11, 13, 16),
		Stroke     = Color3.fromRGB(40, 46, 54),
		StrokeSoft = Color3.fromRGB(26, 30, 36),
		Text       = Color3.fromRGB(240, 246, 250),
		SubText    = Color3.fromRGB(144, 156, 170),
		Muted      = Color3.fromRGB(94, 105, 118),
		Accent     = Color3.fromRGB(56, 189, 248),
		Accent2    = Color3.fromRGB(45, 212, 191),
		Good       = Color3.fromRGB(52, 211, 153),
		Warn       = Color3.fromRGB(251, 191, 36),
		Bad        = Color3.fromRGB(248, 113, 113),
	},
	Ember = {
		Backdrop   = Color3.fromRGB(13, 10, 9),
		Sidebar    = Color3.fromRGB(18, 14, 13),
		Content    = Color3.fromRGB(23, 18, 17),
		Card       = Color3.fromRGB(32, 25, 24),
		CardHover  = Color3.fromRGB(42, 33, 31),
		Inset      = Color3.fromRGB(16, 12, 11),
		Stroke     = Color3.fromRGB(54, 43, 40),
		StrokeSoft = Color3.fromRGB(36, 28, 26),
		Text       = Color3.fromRGB(248, 242, 239),
		SubText    = Color3.fromRGB(172, 150, 143),
		Muted      = Color3.fromRGB(120, 102, 96),
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
local ThemeWatch = setmetatable({}, { __mode = "k" })

local function removeThemeEntries(inst)
	for i = #ThemeRegistry, 1, -1 do
		if ThemeRegistry[i].inst == inst then table.remove(ThemeRegistry, i) end
	end
	for i = #GradientRegistry, 1, -1 do
		if GradientRegistry[i].inst == inst then table.remove(GradientRegistry, i) end
	end
	ThemeWatch[inst] = nil
end

local function watchThemeInstance(inst)
	if ThemeWatch[inst] ~= nil then return end
	ThemeWatch[inst] = false
	local ok, conn = pcall(function()
		return inst.Destroying:Connect(function() removeThemeEntries(inst) end)
	end)
	if ok then ThemeWatch[inst] = conn end
end

local function register(inst, prop, key)
	local entry = { inst = inst, prop = prop, key = key }
	table.insert(ThemeRegistry, entry)
	watchThemeInstance(inst)
	pcall(function() inst[prop] = Theme[key] end)
	return entry
end

-- Состояние контролов (активная вкладка, включённый toggle, выбранный
-- dropdown) меняет не только цвет, но и ключ привязки. Поэтому смена темы
-- больше не сбрасывает активный элемент к его базовому цвету.
local function setThemeKey(inst, prop, key)
	if not inst then return nil end
	for i = #ThemeRegistry, 1, -1 do
		local entry = ThemeRegistry[i]
		if entry.inst == inst and entry.prop == prop then
			entry.key = key
			return entry
		end
	end
	return register(inst, prop, key)
end

-- ColorSequence нельзя твинить как обычное свойство, поэтому градиенты
-- живут в отдельном реестре и пересобираются при смене темы.
local function registerGradient(gradient, keyA, keyB)
	table.insert(GradientRegistry, { inst = gradient, a = keyA, b = keyB })
	watchThemeInstance(gradient)
	pcall(function()
		gradient.Color = ColorSequence.new(Theme[keyA], Theme[keyB])
	end)
	return gradient
end

--═══════════════════════════════════════════════════════════════════════
--  2. УТИЛИТЫ
--═══════════════════════════════════════════════════════════════════════

-- Inter — тот же шрифт, что в Linear и подобных десктоп-приложениях,
-- и в отличие от Gotham у него есть настоящие промежуточные веса.
-- Если клиент старый и FontFace недоступен, откатываемся на Gotham.
local FONT, FONT_M, FONT_SB, FONT_B
do
	local family = "rbxasset://fonts/families/Inter.json"
	local ok = pcall(function() return Font.new(family, Enum.FontWeight.Medium) end)
	if ok then
		FONT    = Font.new(family, Enum.FontWeight.Regular)
		FONT_M  = Font.new(family, Enum.FontWeight.Medium)
		FONT_SB = Font.new(family, Enum.FontWeight.SemiBold)
		FONT_B  = Font.new(family, Enum.FontWeight.Bold)
	else
		FONT    = Enum.Font.Gotham
		FONT_M  = Enum.Font.GothamMedium
		FONT_SB = Enum.Font.GothamMedium
		FONT_B  = Enum.Font.GothamBold
	end
end

local EASE      = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local EASE_FAST  = TweenInfo.new(0.12, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local EASE_SLOW  = TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local AnimationsEnabled = true

local function tween(inst, info, props)
	if not AnimationsEnabled then
		pcall(function()
			for prop, value in next, props do inst[prop] = value end
		end)
		return nil
	end
	local ok, t = pcall(function() return TweenService:Create(inst, info, props) end)
	if ok and t then t:Play() end
	return t
end

-- Универсальный конструктор. Ключ `Theme = { Свойство = "КлючТемы" }`
-- сразу применяет цвет и подписывает инстанс на смену темы.
local function new(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then inst.BorderSizePixel = 0 end
	local parent
	for k, v in next, props or {} do
		if k == "Parent" then
			parent = v
		elseif k == "Theme" then
			for prop, key in next, v do register(inst, prop, key) end
		elseif k == "Font" and typeof(v) == "Font" then
			-- FontFace и Font — разные свойства; пишем в нужное,
			-- чтобы вызывающий код не думал, какой режим сейчас активен
			inst.FontFace = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function asText(value, fallback)
	if value == nil then return fallback or "" end
	return tostring(value)
end

-- string.lower не меняет кириллицу, поэтому обычный поиск не находил русские
-- названия, если регистр запроса отличался. Этого небольшого case-fold достаточно
-- для английских и русских подписей, используемых библиотекой.
local CYRILLIC_LOWER = {
	["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е", ["Ё"]="ё",
	["Ж"]="ж", ["З"]="з", ["И"]="и", ["Й"]="й", ["К"]="к", ["Л"]="л", ["М"]="м",
	["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р", ["С"]="с", ["Т"]="т", ["У"]="у",
	["Ф"]="ф", ["Х"]="х", ["Ц"]="ц", ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ",
	["Ы"]="ы", ["Ь"]="ь", ["Э"]="э", ["Ю"]="ю", ["Я"]="я",
}

local function normalizeSearch(value)
	local text = asText(value, ""):lower()
	return (text:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
		return CYRILLIC_LOWER[ch] or ch
	end))
end

local function finiteNumber(value, fallback)
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then
		return fallback
	end
	return number
end

local function assetUri(value)
	if value == nil or value == "" or value == 0 then return nil end
	if type(value) == "number" then return "rbxassetid://" .. value end
	local str = tostring(value):match("^%s*(.-)%s*$")
	if str == "" then return nil end
	if str:match("^%d+$") then return "rbxassetid://" .. str end
	if str:match("^rbxassetid://") or str:match("^rbxasset://") then return str end
	return nil
end

-- Единая фабрика растровых примитивов. Она намеренно ничего не создаёт,
-- пока пользователь не вписал Id: геометрический fallback библиотеки остаётся прежним.
local function assetLayer(parent, name, props)
	local def = ASSETS[name]
	local image = def and assetUri(def.Id)
	if not image then return nil end

	local base = {
		Parent = parent,
		Name = "Aurora" .. name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
	}
	if def.SliceCenter then
		base.ScaleType = Enum.ScaleType.Slice
		base.SliceCenter = def.SliceCenter
		if def.SliceScale then base.SliceScale = def.SliceScale end
	elseif def.TileSize then
		base.ScaleType = Enum.ScaleType.Tile
		base.TileSize = def.TileSize
	end
	for k, v in next, props or {} do base[k] = v end
	return new("ImageLabel", base)
end

local function softShadow(parent, z, paddingPixels, transparency)
	local pad = paddingPixels or 24
	local image = assetLayer(parent, "SoftShadow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, pad * 2, 1, pad * 2),
		ZIndex = z or 0,
		ImageTransparency = transparency or 0.2,
		Theme = { ImageColor3 = "Backdrop" },
	})
	if image then return image end

	-- Геометрический fallback: не такой мягкий, как PNG, но окно не
	-- превращается в плоскую плашку, пока id ассета ещё не заполнен.
	local holder = new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = z or 0,
	})
	for i = 3, 1, -1 do
		new("Frame", {
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 3 + i),
			Size = UDim2.new(1, i * 8, 1, i * 8),
			BackgroundTransparency = 0.82 + i * 0.045,
			ZIndex = z or 0,
			Theme = { BackgroundColor3 = "Backdrop" },
		}, { new("UICorner", { CornerRadius = UDim.new(0, 14 + i * 2) }) })
	end
	return holder
end

local function innerShadow(parent, z, transparency)
	local image = assetLayer(parent, "InnerShadow", {
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or parent.ZIndex,
		ImageTransparency = transparency or 0.32,
		Theme = { ImageColor3 = "Backdrop" },
	})
	if image then return image end

	local holder = new("Frame", {
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = z or parent.ZIndex,
	})
	new("Frame", {
		Parent = holder,
		Position = UDim2.fromOffset(2, 1),
		Size = UDim2.new(1, -4, 0, 1),
		BackgroundTransparency = 0.28,
		ZIndex = holder.ZIndex,
		Theme = { BackgroundColor3 = "Backdrop" },
	})
	new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, -1),
		Size = UDim2.new(1, -4, 0, 1),
		BackgroundTransparency = 0.94,
		ZIndex = holder.ZIndex,
		Theme = { BackgroundColor3 = "Text" },
	})
	return holder
end

local function floatingShadow(parent, z, transparency)
	local image = assetLayer(parent, "SoftShadow", {
		Visible = false,
		ZIndex = z or 0,
		ImageTransparency = transparency or 0.34,
		Theme = { ImageColor3 = "Backdrop" },
	})
	if image then return image end
	return new("Frame", {
		Parent = parent,
		Visible = false,
		ZIndex = z or 0,
		BackgroundTransparency = 0.68,
		Theme = { BackgroundColor3 = "Backdrop" },
	}, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })
end

local function surfaceNoise(parent, z, transparency)
	return assetLayer(parent, "SurfaceNoise", {
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or parent.ZIndex,
		ImageTransparency = transparency or 0.92,
		Theme = { ImageColor3 = "Text" },
	})
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

--════════════════════════════ ИКОНКИ ════════════════════════════
-- Набор Lucide (тот же, что тянет Rayfield): спрайтшиты, из которых иконка
-- вырезается через ImageRectOffset/ImageRectSize. Вшит подмножеством, чтобы
-- не тащить 147 КБ и не зависеть от чужого репозитория.
-- Формат: имя = {assetId, ширина, высота, смещениеX, смещениеY}
local LUCIDE = {
	["activity"]={16898612629,48,48,514,771},
	["anchor"]={16898612629,48,48,306,869},
	["arrow-down"]={16898612629,48,48,967,49},
	["arrow-left"]={16898612629,48,48,98,918},
	["arrow-right"]={16898612629,48,48,453,820},
	["arrow-up"]={16898612629,48,48,967,355},
	["at-sign"]={16898612629,48,48,453,869},
	["axe"]={16898612629,48,48,869,710},
	["banknote"]={16898612629,48,48,453,967},
	["battery"]={16898612629,48,48,967,857},
	["bell"]={16898612819,48,48,820,257},
	["bomb"]={16898612819,48,48,257,869},
	["bookmark"]={16898612819,48,48,514,918},
	["bot"]={16898612819,48,48,869,98},
	["box"]={16898612819,48,48,771,196},
	["boxes"]={16898612819,48,48,196,771},
	["brush"]={16898612819,48,48,404,820},
	["bug"]={16898612819,48,48,257,967},
	["calendar"]={16898612819,48,48,355,918},
	["camera"]={16898612819,48,48,967,563},
	["car"]={16898612819,48,48,918,147},
	["check"]={16898612819,48,48,710,869},
	["chevron-down"]={16898612819,48,48,196,918},
	["chevron-left"]={16898612819,48,48,404,967},
	["chevron-right"]={16898612819,48,48,869,759},
	["chevron-up"]={16898612819,48,48,710,918},
	["circle"]={16898613044,48,48,771,355},
	["clipboard"]={16898613044,48,48,49,869},
	["clock"]={16898613044,48,48,771,661},
	["cloud"]={16898613044,48,48,918,306},
	["code"]={16898613044,48,48,355,869},
	["coins"]={16898613044,48,48,869,612},
	["compass"]={16898613044,48,48,514,967},
	["copy"]={16898613044,48,48,918,612},
	["cpu"]={16898613044,48,48,196,869},
	["crosshair"]={16898613044,48,48,453,869},
	["crown"]={16898613044,48,48,404,918},
	["database"]={16898613044,48,48,710,869},
	["download"]={16898613044,48,48,820,906},
	["droplet"]={16898613044,48,48,820,955},
	["eye"]={16898613353,48,48,771,563},
	["eye-off"]={16898613353,48,48,820,514},
	["filter"]={16898613353,48,48,612,869},
	["flag"]={16898613353,48,48,98,918},
	["flame"]={16898613353,48,48,967,306},
	["folder"]={16898613353,48,48,404,967},
	["footprints"]={16898613353,48,48,918,710},
	["gamepad-2"]={16898613353,48,48,710,967},
	["gem"]={16898613353,48,48,918,857},
	["ghost"]={16898613353,48,48,869,906},
	["gift"]={16898613353,48,48,820,955},
	["globe"]={16898613509,48,48,771,563},
	["hammer"]={16898613509,48,48,306,820},
	["hash"]={16898613509,48,48,147,771},
	["headphones"]={16898613509,48,48,306,869},
	["heart"]={16898613509,48,48,661,771},
	["hexagon"]={16898613509,48,48,967,0},
	["home"]={16898613509,48,48,820,147},
	["hourglass"]={16898613509,48,48,49,918},
	["image"]={16898613509,48,48,306,918},
	["info"]={16898613509,48,48,612,869},
	["key"]={16898613509,48,48,869,404},
	["keyboard"]={16898613509,48,48,453,820},
	["layers"]={16898613509,48,48,98,967},
	["layout-dashboard"]={16898613509,48,48,967,355},
	["layout-grid"]={16898613509,48,48,918,404},
	["layout-list"]={16898613509,48,48,869,453},
	["leaf"]={16898613509,48,48,918,661},
	["link"]={16898613509,48,48,918,453},
	["list"]={16898613509,48,48,869,808},
	["lock"]={16898613509,48,48,918,857},
	["mail"]={16898613613,48,48,820,0},
	["map"]={16898613613,48,48,306,771},
	["map-pin"]={16898613613,48,48,820,257},
	["maximize"]={16898613613,48,48,771,563},
	["medal"]={16898613613,48,48,563,771},
	["menu"]={16898613613,48,48,49,820},
	["message-square"]={16898613613,48,48,355,820},
	["mic"]={16898613613,48,48,820,612},
	["minimize"]={16898613613,48,48,918,49},
	["minus"]={16898613613,48,48,771,196},
	["monitor"]={16898613613,48,48,404,820},
	["moon"]={16898613613,48,48,306,918},
	["mountain"]={16898613613,48,48,869,612},
	["move"]={16898613613,48,48,453,820},
	["music"]={16898613613,48,48,967,563},
	["package"]={16898613613,48,48,918,196},
	["palette"]={16898613613,48,48,453,918},
	["panel-left"]={16898613613,48,48,967,453},
	["pause"]={16898613699,48,48,0,771},
	["pencil"]={16898613699,48,48,820,257},
	["percent"]={16898613699,48,48,771,563},
	["phone"]={16898613699,48,48,0,869},
	["plane"]={16898613699,48,48,98,820},
	["play"]={16898613699,48,48,918,257},
	["plus"]={16898613699,48,48,257,918},
	["power"]={16898613699,48,48,820,147},
	["radio"]={16898613699,48,48,306,918},
	["refresh-cw"]={16898613699,48,48,404,869},
	["rocket"]={16898613699,48,48,918,147},
	["save"]={16898613699,48,48,918,453},
	["scale"]={16898613699,48,48,404,967},
	["scan"]={16898613699,48,48,967,196},
	["search"]={16898613699,48,48,918,857},
	["send"]={16898613699,48,48,967,857},
	["settings"]={16898613777,48,48,771,257},
	["shield"]={16898613777,48,48,869,0},
	["shield-check"]={16898613777,48,48,820,257},
	["shopping-cart"]={16898613777,48,48,869,257},
	["skull"]={16898613777,48,48,49,869},
	["sliders-horizontal"]={16898613777,48,48,820,355},
	["snowflake"]={16898613777,48,48,771,661},
	["sparkles"]={16898613777,48,48,918,49},
	["square"]={16898613777,48,48,869,710},
	["star"]={16898613777,48,48,967,147},
	["sun"]={16898613777,48,48,967,453},
	["sword"]={16898613777,48,48,710,967},
	["swords"]={16898613777,48,48,967,759},
	["tag"]={16898613777,48,48,967,906},
	["target"]={16898613869,48,48,514,771},
	["terminal"]={16898613869,48,48,820,257},
	["timer"]={16898613869,48,48,918,0},
	["toggle-left"]={16898613869,48,48,869,49},
	["trash-2"]={16898613869,48,48,257,918},
	["triangle"]={16898613869,48,48,869,98},
	["trophy"]={16898613869,48,48,820,147},
	["unlock"]={16898613869,48,48,771,710},
	["upload"]={16898613869,48,48,612,869},
	["user"]={16898613869,48,48,661,869},
	["user-plus"]={16898613869,48,48,918,355},
	["users"]={16898613869,48,48,967,98},
	["video"]={16898613869,48,48,355,967},
	["volume-2"]={16898613869,48,48,771,808},
	["wallet"]={16898613869,48,48,147,967},
	["waves"]={16898613869,48,48,820,808},
	["wifi"]={16898613869,48,48,869,808},
	["wind"]={16898613869,48,48,820,857},
	["wrench"]={16898613869,48,48,820,906},
	["x"]={16898613869,48,48,869,906},
	["zap"]={16898613869,48,48,918,906},
}

-- Принимает имя Lucide ("gamepad-2"), числовой id или "rbxassetid://...".
-- Возвращает готовый набор свойств для ImageLabel либо nil.
local function resolveIcon(value)
	if not value or value == 0 or value == "" then return nil end

	if type(value) == "number" then
		return { image = "rbxassetid://" .. value }
	end

	local str = tostring(value)
	if str:match("^rbxassetid://") or str:match("^rbxasset://") or str:match("^rbxthumb://") then
		return { image = str }
	end
	if str:match("^%d+$") then
		return { image = "rbxassetid://" .. str }
	end

	local entry = LUCIDE[str:lower():match("^%s*(.-)%s*$")]
	if not entry then return nil end
	return {
		image  = "rbxassetid://" .. entry[1],
		rect   = Vector2.new(entry[2], entry[3]),
		offset = Vector2.new(entry[4], entry[5]),
	}
end

-- Юникод-глифы (✕ ⌕ ▾ ✓) в Roblox не рендерятся — шрифт подставляет
-- пустой прямоугольник. Поэтому иконки собираем из повёрнутых фреймов:
-- всегда чёткие, красятся темой и не зависят от наличия символа в шрифте.

local function iconBar(parent, w, h, rot, ox, oy, key, z)
	return new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, ox or 0, 0.5, oy or 0),
		Size = UDim2.fromOffset(w, h),
		Rotation = rot or 0,
		BorderSizePixel = 0,
		ZIndex = z or 2,
		Theme = { BackgroundColor3 = key or "Muted" },
	}, { corner(1) })
end

local Icons = {}

function Icons.close(box, key, z)
	iconBar(box, 11, 1.5,  45, 0, 0, key, z)
	iconBar(box, 11, 1.5, -45, 0, 0, key, z)
end

function Icons.minimize(box, key, z)
	iconBar(box, 11, 1.5, 0, 0, 0, key, z)
end

function Icons.expand(box, key, z)
	iconBar(box, 11, 1.5, 0, 0, 0, key, z)
	iconBar(box, 11, 1.5, 90, 0, 0, key, z)
end

function Icons.maximize(box, key, z)
	new("Frame", {
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = z or 2,
	}, { corner(1), stroke(key or "Muted", 1.4, 0) })
end

function Icons.chevron(box, key, z)          -- «галочка» вниз
	iconBar(box, 7, 1.5,  45, -2.1, 0, key, z)
	iconBar(box, 7, 1.5, -45,  2.1, 0, key, z)
end

function Icons.check(box, key, z)
	iconBar(box, 5, 1.6,  45, -2.6, 1.6, key, z)
	iconBar(box, 9, 1.6, -45,  1.4, -0.4, key, z)
end

function Icons.search(box, key, z)
	new("Frame", {
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -1, 0.5, -1),
		Size = UDim2.fromOffset(9, 9),
		BackgroundTransparency = 1,
		ZIndex = z or 2,
	}, { corner(5), stroke(key or "Muted", 1.4, 0) })
	iconBar(box, 4.5, 1.4, 45, 3.4, 3.4, key, z)
end

function Icons.grip(box, key, z)
	iconBar(box, 9, 1.4, -45,  1.5,  1.5, key, z)
	iconBar(box, 4, 1.4, -45,  4,    4,   key, z)
end

local function recolorIcon(box, key)
	if not box then return end
	local color = Theme[key]
	for _, part in ipairs(box:GetDescendants()) do
		if part:IsA("Frame") then
			setThemeKey(part, "BackgroundColor3", key)
			tween(part, EASE_FAST, { BackgroundColor3 = color })
		elseif part:IsA("UIStroke") then
			setThemeKey(part, "Color", key)
			tween(part, EASE_FAST, { Color = color })
		elseif part:IsA("ImageLabel") or part:IsA("ImageButton") then
			setThemeKey(part, "ImageColor3", key)
			tween(part, EASE_FAST, { ImageColor3 = color })
		end
	end
end

local function topSheen(parent, z, inset, transparency)
	inset = inset or 1
	return new("Frame", {
		Parent = parent,
		Position = UDim2.fromOffset(inset, 1),
		Size = UDim2.new(1, -inset * 2, 0, 1),
		BackgroundTransparency = transparency or 0.88,
		ZIndex = z or parent.ZIndex,
		Theme = { BackgroundColor3 = "Text" },
	}, { corner(1) })
end

-- Квадратный контейнер под иконку — позиционируется как обычный элемент
local function icon(parent, name, key, size, z)
	local box = new("Frame", {
		Parent = parent,
		Size = UDim2.fromOffset(size or 16, size or 16),
		BackgroundTransparency = 1,
		ZIndex = z or 2,
	})
	if Icons[name] then
		Icons[name](box, key, (z or 2) + 1)
	else
		local data = resolveIcon(name)
		if data then
			new("ImageLabel", {
				Parent = box,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = data.image,
				ImageRectSize = data.rect or Vector2.zero,
				ImageRectOffset = data.offset or Vector2.zero,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = (z or 2) + 1,
				Theme = { ImageColor3 = key or "Muted" },
			})
		end
	end
	return box
end

local function round(value, decimals)
	local m = 10 ^ (decimals or 0)
	local scaled = value * m
	if scaled >= 0 then
		return math.floor(scaled + 0.5) / m
	end
	return math.ceil(scaled - 0.5) / m
end

local function snapGuiPosition(inst)
	if not inst or not inst.Parent then return end
	local absolute = inst.AbsolutePosition
	local dx = round(absolute.X, 0) - absolute.X
	local dy = round(absolute.Y, 0) - absolute.Y
	if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then return end
	local position = inst.Position
	inst.Position = UDim2.new(
		position.X.Scale, position.X.Offset + dx,
		position.Y.Scale, position.Y.Offset + dy
	)
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
}

local function optionFlag(opts)
	local flag = opts and opts.Flag
	if flag == nil or flag == "" then return nil end
	return tostring(flag)
end

local function registerOption(flag, obj, value, owner)
	if not flag then return end
	obj.Window = owner
	if owner then
		owner._options = owner._options or {}
		owner._optionOrder = owner._optionOrder or {}
		if owner._options[flag] and owner._options[flag] ~= obj then
			warn("[AuroraUI] повторный Flag в одном окне: " .. flag)
		else
			table.insert(owner._optionOrder, flag)
		end
		owner._options[flag] = obj
	end
	Library.Options[flag] = obj
	Library.Flags[flag] = value
end

local function unregisterOption(flag, obj)
	if not flag then return end
	local owner = obj and obj.Window
	if owner and owner._options and owner._options[flag] == obj then
		owner._options[flag] = nil
		for i = #(owner._optionOrder or {}), 1, -1 do
			if owner._optionOrder[i] == flag then
				table.remove(owner._optionOrder, i)
				break
			end
		end
	end
	if Library.Options[flag] == obj then
		Library.Options[flag] = nil
		Library.Flags[flag] = nil
	end
end

local function bindCleanup(inst, fn)
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		local ok, err = pcall(fn)
		if not ok then warn("[AuroraUI] очистка элемента: " .. tostring(err)) end
	end
	pcall(function() inst.Destroying:Connect(cleanup) end)
	return cleanup
end

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
	local bucket = Dispatch[kind]
	if not bucket then return function() end end
	table.insert(bucket, fn)
	local connected = true
	return function()
		if not connected then return end
		connected = false
		for i = #bucket, 1, -1 do
			if bucket[i] == fn then table.remove(bucket, i) break end
		end
	end
end

local activeDrag = nil       -- функция обновления текущего перетаскивания
local captureTarget = nil    -- элемент, ожидающий нажатия клавиши
local keybinds = {}          -- список активных кейбиндов

local function fire(kind, input, processed)
	local bucket = Dispatch[kind]
	-- Обработчик вправе отписаться прямо во время события. Идём по снимку,
	-- иначе table.remove сдвинет массив и следующий обработчик будет пропущен.
	for _, fn in ipairs(table.clone(bucket)) do
		if table.find(bucket, fn) then
			local ok, err = pcall(fn, input, processed)
			if not ok then warn("[AuroraUI] ввод: " .. tostring(err)) end
		end
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
local viewport
local function draggable(handle, target, onMove, canStart)
	handle.InputBegan:Connect(function(input)
		if not isPressStart(input) or (canStart and not canStart()) then return end
		local origin = input.Position
		local startAbs = target.AbsolutePosition
		local startSize = target.AbsoluteSize
		local startPosition = target.Position
		activeDrag = function(i)
			local d = i.Position - origin
			local vp = viewport and viewport() or Vector2.new(1920, 1080)
			local minX = -startSize.X + 48
			local maxX = math.max(minX, vp.X - 48)
			local maxY = math.max(0, vp.Y - 48)
			local x = math.clamp(startAbs.X + d.X, minX, maxX)
			local y = math.clamp(startAbs.Y + d.Y, 0, maxY)
			local adjusted = Vector2.new(x - startAbs.X, y - startAbs.Y)
			target.Position = UDim2.new(
				startPosition.X.Scale, startPosition.X.Offset + adjusted.X,
				startPosition.Y.Scale, startPosition.Y.Offset + adjusted.Y
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
pcall(function()
	Gui.ScreenInsets = Enum.ScreenInsets.None
	Gui.ClipToDeviceSafeArea = false
	Gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
end)

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

local function overlayPosition(x, y)
	local origin = Overlay.AbsolutePosition
	return UDim2.fromOffset(x - origin.X, y - origin.Y)
end

viewport = function()
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

local function refreshBlur()
	local amount = 0
	for _, window in ipairs(Library.Windows) do
		if window.Acrylic and not window.Hidden and window.Frame and window.Frame.Parent then
			amount = 14
			break
		end
	end
	setBlur(amount)
end

--═══════════════════════════════════════════════════════════════════════
--  7. УВЕДОМЛЕНИЯ
--═══════════════════════════════════════════════════════════════════════

local ToastLayer = new("Frame", {
	Parent = Gui,
	Name = "Toasts",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(360, 600),
	BackgroundTransparency = 1,
	ZIndex = 900,
}, {
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

function Library:Notify(opts)
	if not self.Alive then return nil end
	opts = type(opts) == "table" and opts or {}
	local title    = asText(opts.Title, "Уведомление")
	local content  = asText(opts.Content ~= nil and opts.Content or opts.Text, "")
	local duration = math.clamp(finiteNumber(opts.Duration, 4), 0.1, 3600)
	local kind = asText(opts.Type, ""):lower()
	local accentKey = kind == "error" and "Bad"
		or kind == "warn" and "Warn"
		or kind == "success" and "Good"
		or "Accent"
	local contentChars = utf8.len(content) or #content
	local bodyHeight = content ~= "" and math.clamp(math.ceil(contentChars / 42) * 15, 30, 60) or 0
	local toastHeight = content ~= "" and 42 + bodyHeight or 54

	local card = new("Frame", {
		Parent = ToastLayer,
		Size = UDim2.fromOffset(360, toastHeight),
		BackgroundTransparency = 1,
		ZIndex = 901,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(12), stroke("Stroke", 1, 1) })
	softShadow(card, 900, 18, 0.38)

	local shell = new("Frame", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 902,
	})
	surfaceNoise(shell, 902, 0.94)
	topSheen(shell, 904, 12, 0.9)

	new("Frame", {
		Parent = shell,
		Size = UDim2.new(0, 3, 1, -22),
		Position = UDim2.fromOffset(11, 11),
		BorderSizePixel = 0,
		ZIndex = 903,
		Theme = { BackgroundColor3 = accentKey },
	}, { corner(2) })

	local statusRing = new("Frame", {
		Parent = shell,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 25, 0.5, -2),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		ZIndex = 904,
	}, { corner(11), stroke(accentKey, 1.5, 0.12) })
	local statusIconName = opts.Icon and tostring(opts.Icon) or nil
	local statusIconData = statusIconName and resolveIcon(statusIconName) or nil
	if statusIconData then
		new("ImageLabel", {
			Parent = statusRing,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(13, 13),
			BackgroundTransparency = 1,
			Image = statusIconData.image,
			ImageRectSize = statusIconData.rect or Vector2.zero,
			ImageRectOffset = statusIconData.offset or Vector2.zero,
			ZIndex = 905,
			Theme = { ImageColor3 = accentKey },
		})
	else
		new("Frame", {
			Parent = statusRing,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			ZIndex = 905,
			Theme = { BackgroundColor3 = accentKey },
		}, { corner(3) })
	end

	local titleLbl = label({
		Parent = shell,
		Position = UDim2.fromOffset(50, 11),
		Size = UDim2.new(1, -92, 0, 16),
		Font = FONT_B,
		TextSize = 13,
		Text = title,
		ZIndex = 903,
	})

	local bodyLbl
	if content ~= "" then
		bodyLbl = label({
			Parent = shell,
			Position = UDim2.fromOffset(50, 30),
			Size = UDim2.new(1, -92, 0, bodyHeight),
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
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 903,
		Theme = { BackgroundColor3 = accentKey },
	}, { corner(1) })

	local closeButton = new("TextButton", {
		Parent = shell,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 906,
	})
	local closeIcon = icon(closeButton, "close", "Muted", 14, 907)
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)

	-- UIListLayout управляет Position, поэтому появление анимируем шириной:
	-- карточка раскрывается от правого края и не спорит с layout.
	card.Size = UDim2.fromOffset(0, toastHeight)
	tween(card, EASE, { BackgroundTransparency = 0, Size = UDim2.fromOffset(360, toastHeight) })
	tween(card:FindFirstChildOfClass("UIStroke"), EASE, { Transparency = 0.4 })
	tween(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		if not card.Parent then return end
		tween(card, EASE_FAST, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, toastHeight) })
		tween(titleLbl, EASE_FAST, { TextTransparency = 1 })
		if bodyLbl then tween(bodyLbl, EASE_FAST, { TextTransparency = 1 }) end
		local s = card:FindFirstChildOfClass("UIStroke")
		if s then tween(s, EASE_FAST, { Transparency = 1 }) end
		task.delay(0.18, function()
			if card.Parent then card:Destroy() end
		end)
	end
	closeButton.MouseButton1Click:Connect(dismiss)
	task.delay(duration, dismiss)

	return card
end

--═══════════════════════════════════════════════════════════════════════
--  8. МОДАЛЬНОЕ ОКНО
--═══════════════════════════════════════════════════════════════════════

function Library:Dialog(opts)
	if not self.Alive then return nil end
	opts = type(opts) == "table" and opts or {}
	local dialogContent = asText(opts.Content, "")
	local dialogChars = utf8.len(dialogContent) or #dialogContent
	local contentHeight = math.clamp(math.ceil(dialogChars / 46) * 16, 40, 96)
	local dialogHeight = 110 + contentHeight
	local shade = new("Frame", {
		Parent = Gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Active = true,
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
	softShadow(box, 950, 26, 0.28)

	local inner = new("Frame", {
		Parent = box,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 952,
		ClipsDescendants = true,
	}, { padding(20, 16, 20, 20) })
	surfaceNoise(inner, 952, 0.94)
	topSheen(inner, 954, 8, 0.86)

	label({
		Parent = inner,
		Size = UDim2.new(1, 0, 0, 20),
		Font = FONT_B,
		TextSize = 15,
		Text = asText(opts.Title, "Подтверждение"),
		ZIndex = 953,
	})

	label({
		Parent = inner,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, contentHeight),
		TextSize = 12,
		Text = dialogContent,
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
		if not shade.Parent then return end
		tween(shade, EASE_FAST, { BackgroundTransparency = 1 })
		tween(box, EASE_FAST, { Size = UDim2.fromOffset(380, 0) })
		shade.Active = false
		task.delay(0.2, function()
			if shade.Parent then shade:Destroy() end
		end)
	end

	local buttons = type(opts.Buttons) == "table" and opts.Buttons or nil
	if not buttons or #buttons == 0 then buttons = { { Text = "OK" } } end
	local closed = false
	local function closeOnce()
		if closed then return false end
		closed = true
		close()
		return true
	end

	for i, def in ipairs(buttons) do
		if type(def) ~= "table" then def = { Text = def } end
		local primary = def.Primary == true or (i == 1 and #buttons == 1)
		local buttonText = asText(def.Text, "OK")
		local charCount = utf8.len(buttonText) or #buttonText
		local btn = new("TextButton", {
			Parent = row,
			Size = UDim2.fromOffset(math.max(84, charCount * 9 + 28), 34),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = FONT_M,
			TextSize = 13,
			Text = buttonText,
			LayoutOrder = i,
			ZIndex = 954,
			Theme = {
				BackgroundColor3 = primary and "Accent" or "Card",
				TextColor3 = primary and "Backdrop" or "Text",
			},
		}, { corner(9) })
		topSheen(btn, 955, 8, primary and 0.74 or 0.9)
		if not primary then
			stroke("StrokeSoft", 1, 0).Parent = btn
		end
		btn.MouseButton1Click:Connect(function()
			if closeOnce() then safeCall(def.Callback) end
		end)
	end

	tween(box, EASE, { Size = UDim2.fromOffset(380, dialogHeight) })
	return { Close = closeOnce }
end

--═══════════════════════════════════════════════════════════════════════
--  9. ОБЩИЙ КАРКАС ЭЛЕМЕНТА (строка-карточка)
--═══════════════════════════════════════════════════════════════════════

-- Создаёт новую группу-карточку на странице вкладки. Элементы кладутся
-- ВНУТРЬ неё строками с волосяными разделителями — именно это отличает
-- собранный интерфейс настроек от россыпи отдельных плашек.
local function openSection(tab, titleText, preferredColumn, minimumHeight)
	titleText = titleText ~= nil and tostring(titleText) or nil
	local columnIndex
	local fullWidth = preferredColumn == "full"
	if fullWidth then
		columnIndex = 1
	elseif preferredColumn ~= nil then
		columnIndex = math.clamp(math.floor(finiteNumber(preferredColumn, 1)), 1, tab._columnCount)
	else
		tab._columnCursor = (tab._columnCursor % tab._columnCount) + 1
		columnIndex = tab._columnCursor
	end
	local parent = fullWidth and tab._fullColumn or tab._columns[columnIndex] or tab.Page
	tab._lastColumn = parent
	local holder = new("Frame", {
		Parent = parent,
		Name = "Section",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = tab._order + 1,
	}, { list(0) })
	tab._order += 1

	local groupStroke = stroke("StrokeSoft", 1, 0.12)
	local card = new("Frame", {
		Parent = holder,
		Name = "Group",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(8), groupStroke, list(0) })
	minimumHeight = finiteNumber(minimumHeight, 0)
	if minimumHeight > 0 then
		new("UISizeConstraint", {
			Parent = card,
			MinSize = Vector2.new(0, minimumHeight),
		})
	end

	-- В desktop-макете название секции является частью самой панели,
	-- а не отдельной подписью над ней.
	local headerLbl
	local rowOffset = 0
	if titleText and titleText ~= "" then
		rowOffset = 1
		local head = new("Frame", {
			Parent = card,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		})
		headerLbl = label({
			Parent = head,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -44, 1, -1),
			Font = FONT_SB,
			TextSize = 14,
			Text = titleText,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "Text" },
		})
		new("Frame", {
			Parent = head,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 22, 1, 0),
			Size = UDim2.new(1, -44, 0, 1),
			BackgroundTransparency = 0.12,
			Theme = { BackgroundColor3 = "StrokeSoft" },
		})
	end

	-- UIGradient умножает цвет фона, поэтому белый сверху оставляет тон
	-- как есть, а приглушённый снизу делает поверхность темнее. Получается
	-- освещение сверху вместо плоской заливки.
	new("UIGradient", {
		Parent = card,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(222, 222, 228)),
		}),
	})

	-- Тот же приём для обводки: сверху светлее, снизу почти растворяется.
	-- Внутрь карточки линию-подсветку не положить — её подхватит UIListLayout.
	new("UIGradient", {
		Parent = groupStroke,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 158)),
		}),
	})

	local section = {
		holder = holder,
		card = card,
		rows = 0,
		header = headerLbl,
		rowOffset = rowOffset,
	}
	tab._section = section
	return section
end

-- Строка внутри текущей группы. Если группы ещё нет — заводит безымянную.
local function makeCard(tab, opts, slotWidthOverride, heightOverride)
	local section = tab._section or openSection(tab, nil)
	local desc = opts.Desc ~= nil and tostring(opts.Desc) or nil
	local hasDesc = desc ~= nil and desc ~= ""
	local height = math.max(32, finiteNumber(
		heightOverride ~= nil and heightOverride or opts.Height,
		hasDesc and 62 or 52
	))
	local slotWidth = math.max(0, finiteNumber(
		slotWidthOverride ~= nil and slotWidthOverride or opts.SlotWidth,
		140
	))
	local textReserve = math.max(180, slotWidth + 46)

	local row = new("Frame", {
		Parent = section.card,
		Name = "Item",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = section.rows + 1 + section.rowOffset,
		Theme = { BackgroundColor3 = "CardHover" },
	})
	section.rows += 1

	-- разделитель рисуем сверху у всех строк кроме первой
	if section.rows > 1 then
		new("Frame", {
			Parent = row,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -44, 0, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
			Theme = { BackgroundColor3 = "StrokeSoft" },
		})
	end
	surfaceNoise(row, 1, 0.96)
	topSheen(row, 2, 22, 0.975)
	local hoverRail = new("Frame", {
		Parent = row,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(2, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(1) })

	local title = label({
		Parent = row,
		Position = UDim2.fromOffset(22, hasDesc and 10 or 0),
		Size = UDim2.new(1, -textReserve, 0, hasDesc and 16 or height),
		Font = FONT_M,
		TextSize = 13,
		Text = asText(opts.Text ~= nil and opts.Text or opts.Name, "Элемент"),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	if hasDesc then
		label({
			Parent = row,
			Position = UDim2.fromOffset(22, 31),
			Size = UDim2.new(1, -textReserve, 0, 15),
			Font = FONT_M,
			TextSize = 12,
			Text = desc,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "Muted" },
		})
	end

	-- правая зона под сам контрол
	local slot = new("Frame", {
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0),
		Size = UDim2.fromOffset(slotWidth, height - 12),
		BackgroundTransparency = 1,
	})

	row.MouseEnter:Connect(function()
		tween(row, EASE_FAST, { BackgroundTransparency = 0.7 })
		tween(hoverRail, EASE_FAST, {
			Size = UDim2.fromOffset(2, math.min(22, height - 12)),
			BackgroundTransparency = 0.15,
		})
	end)
	row.MouseLeave:Connect(function()
		tween(row, EASE_FAST, { BackgroundTransparency = 1 })
		tween(hoverRail, EASE_FAST, {
			Size = UDim2.fromOffset(2, 0),
			BackgroundTransparency = 1,
		})
	end)

	return row, slot, title
end

-- Подсветка строки при переходе из поиска
local function flashCard(row)
	if not row or not row.Parent then return end
	setThemeKey(row, "BackgroundColor3", "Accent")
	for _ = 1, 2 do
		if not row.Parent then return end
		row.BackgroundColor3 = Theme.Accent
		tween(row, TweenInfo.new(0.18), { BackgroundTransparency = 0.7 })
		task.wait(0.22)
		if not row.Parent then return end
		tween(row, TweenInfo.new(0.18), { BackgroundTransparency = 1 })
		task.wait(0.22)
	end
	if row.Parent then
		setThemeKey(row, "BackgroundColor3", "CardHover")
		row.BackgroundColor3 = Theme.CardHover
	end
end

--═══════════════════════════════════════════════════════════════════════
--  10. ОКНО
--═══════════════════════════════════════════════════════════════════════

local KEY_PROVIDER_META = {
	WorkInk = {
		Name = "Work.ink",
		Description = "Short link and unlock tasks",
		Icon = "link",
	},
	LootLabs = {
		Name = "LootLabs",
		Description = "Content locker and offers",
		Icon = "gift",
	},
}

local function keyCacheStem(value)
	local text = asText(value, "default")
	text = text:gsub("[^%w%-_]", "_"):gsub("_+", "_")
	text = text:gsub("^_+", ""):gsub("_+$", "")
	if text == "" then text = "default" end
	return text:sub(1, 48)
end

local function keyCacheFile(window, config, provider)
	local owner = config.CacheKey or window.ConfigName or window.Title or game.PlaceId
	return "AuroraUI/keys/" .. keyCacheStem(owner) .. "_" .. provider.Id:lower() .. ".json"
end

local function ensureKeyCacheFolder()
	if not FS.mkdir or not FS.isdir then return end
	for _, folder in ipairs({ "AuroraUI", "AuroraUI/keys" }) do
		local checked, exists = pcall(FS.isdir, folder)
		if not checked or not exists then pcall(FS.mkdir, folder) end
	end
end

local function readKeyCache(window, config, provider)
	if config.Remember == false or provider.Remember == false or not HAS_FS or not HttpService then
		return nil
	end
	local path = keyCacheFile(window, config, provider)
	local checked, exists = pcall(FS.isfile, path)
	if not checked or not exists then return nil end
	local read, raw = pcall(FS.read, path)
	if not read or type(raw) ~= "string" or #raw > 16384 then return nil end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decoded or type(data) ~= "table" then return nil end
	if data.provider ~= provider.Id or type(data.key) ~= "string" or #data.key > 4096 then
		return nil
	end
	if type(data.expiresAt) == "number" and data.expiresAt <= os.time() then
		if FS.delete then pcall(FS.delete, path) end
		return nil
	end
	return data.key
end

local function writeKeyCache(window, config, provider, key)
	if config.Remember == false or provider.Remember == false or not HAS_FS or not HttpService then
		return false
	end
	local duration = math.clamp(
		finiteNumber(provider.CacheDuration, finiteNumber(config.CacheDuration, 86400)),
		60,
		2678400
	)
	ensureKeyCacheFolder()
	local encoded, raw = pcall(HttpService.JSONEncode, HttpService, {
		provider = provider.Id,
		key = key,
		expiresAt = os.time() + duration,
	})
	if not encoded then return false end
	local wrote, result = pcall(FS.write, keyCacheFile(window, config, provider), raw)
	return wrote and result ~= false
end

local function clearKeyCache(window, config, provider)
	if not FS.delete or not FS.isfile then return end
	local path = keyCacheFile(window, config, provider)
	local checked, exists = pcall(FS.isfile, path)
	if checked and exists then pcall(FS.delete, path) end
end

local function copyToClipboard(text)
	local copier
	if typeof(setclipboard) == "function" then
		copier = setclipboard
	elseif typeof(toclipboard) == "function" then
		copier = toclipboard
	end
	if not copier then return false end
	local ok, result = pcall(copier, text)
	return ok and result ~= false
end

local function normalizeKeyProviders(config)
	local source = type(config.Providers) == "table" and config.Providers or {}
	local providers = {}
	local server = type(config.Server) == "string"
		and config.Server:match("^%s*(.-)%s*$"):gsub("/+$", "")
		or nil

	local function add(id)
		local meta = KEY_PROVIDER_META[id]
		local raw = source[id] or source[meta.Name] or config[id]
		if type(raw) == "string" then raw = { URL = raw } end
		raw = type(raw) == "table" and raw or {}
		if raw.Enabled == false then return end

		local url = raw.GetKeyURL or raw.URL or raw.Link
		if url == nil then
			url = id == "WorkInk" and config.WorkInkURL or config.LootLabsURL
		end
		local validator = raw.Validate or raw.Verify or config.Validate or config.Verify

		if server and server ~= "" then
			if url == nil then
				url = function(_, providerId)
					local data, err = requestJSON("POST", server .. "/api/start", {
						provider = providerId,
					})
					if not data then error(err) end
					if data.success ~= true or type(data.url) ~= "string" then
						error(asText(data.message, "The key server did not return a link."))
					end
					return data.url
				end
			end
			if validator == nil then
				validator = function(key, providerId)
					local data, err = requestJSON("POST", server .. "/api/verify", {
						key = key,
						provider = providerId,
					})
					if not data then return false, err end
					return data.success == true,
						asText(data.message, data.success == true and "Access granted." or "Invalid key."),
						data.token or key
				end
			end
		end

		table.insert(providers, {
			Id = id,
			Name = asText(raw.Name, meta.Name),
			Description = asText(raw.Description, meta.Description),
			Icon = raw.Icon or meta.Icon,
			GetKeyURL = url,
			Validate = validator,
			OnGetKey = raw.OnGetKey or config.OnGetKey,
			Key = raw.Key,
			Keys = raw.Keys,
			Remember = raw.Remember,
			CacheDuration = raw.CacheDuration,
		})
	end

	add("WorkInk")
	add("LootLabs")
	return providers
end

local function validateKey(config, provider, key, cached)
	local validator = provider.Validate
	if type(validator) == "function" then
		local ok, valid, message, token = pcall(validator, key, provider.Id, cached == true)
		if not ok then
			warn("[AuroraUI] Key validation failed: " .. tostring(valid))
			return false, "Could not contact the verification service."
		end
		if type(valid) == "table" then
			local result = valid
			local success = result.Success == true or result.Valid == true
			return success, asText(result.Message, success and "Access granted." or "Invalid key."),
				result.Token or result.Key or key
		end
		local success = valid == true
		return success, asText(message, success and "Access granted." or "Invalid key."), token or key
	end

	local expected = provider.Key or config.Key
	if expected ~= nil then
		local success = key == tostring(expected)
		return success, success and "Access granted." or "Invalid key.", key
	end

	local keys = provider.Keys or config.Keys
	if type(keys) == "table" then
		for candidate, enabled in next, keys do
			local value = type(candidate) == "number" and enabled or candidate
			if enabled ~= false and key == tostring(value) then
				return true, "Access granted.", key
			end
		end
		return false, "Invalid key."
	end

	return false, "No validator is configured for " .. provider.Name .. "."
end

local function runKeySystem(window, options, main)
	if options == nil or options == false then return true end
	local config = type(options) == "table" and options or {}
	if config.Enabled == false then return true end

	local providers = normalizeKeyProviders(config)
	if #providers == 0 then
		warn("[AuroraUI] KeySystem has no enabled providers.")
		return false
	end

	window.KeySystemLocked = true
	local selected = providers[1]
	local sessionId = HttpService and HttpService:GenerateGUID(false)
		or tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
	local resolved = false
	local busy = false
	local gateEvent = Instance.new("BindableEvent")
	local shellClip = window.Clip
	local shellStroke = main:FindFirstChildOfClass("UIStroke")
	local shellState = {
		Size = main.Size,
		BackgroundTransparency = main.BackgroundTransparency,
		ClipVisible = shellClip and shellClip.Visible,
		StrokeTransparency = shellStroke and shellStroke.Transparency,
	}
	local shellRestored = false

	local function restoreShell()
		if shellRestored or not main.Parent then return end
		shellRestored = true
		main.Size = shellState.Size
		main.BackgroundTransparency = shellState.BackgroundTransparency
		if shellClip and shellClip.Parent then
			shellClip.Visible = shellState.ClipVisible
		end
		if shellStroke and shellStroke.Parent then
			shellStroke.Transparency = shellState.StrokeTransparency
		end
		snapGuiPosition(main)
	end

	-- До авторизации показываем только компактную карточку Key System.
	-- Основной desktop-интерфейс создаётся заранее, но остаётся полностью скрытым.
	main.Size = UDim2.fromOffset(500, 450)
	main.BackgroundTransparency = 1
	if shellClip then shellClip.Visible = false end
	if shellStroke then shellStroke.Transparency = 1 end
	snapGuiPosition(main)

	local gate = new("Frame", {
		Parent = main,
		Name = "KeySystem",
		Size = UDim2.fromScale(1, 1),
		Active = true,
		BackgroundTransparency = 1,
		ZIndex = 300,
		Theme = { BackgroundColor3 = "Backdrop" },
	}, { corner(14) })
	surfaceNoise(gate, 300, 0.92)

	local card = new("Frame", {
		Parent = gate,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 450),
		ZIndex = 302,
		Theme = { BackgroundColor3 = "Content" },
	}, { corner(16), stroke("Stroke", 1, 0.12) })
	topSheen(card, 304, 12, 0.78)
	surfaceNoise(card, 302, 0.94)

	local closeButton = new("TextButton", {
		Parent = card,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 306,
		Theme = { BackgroundColor3 = "CardHover" },
	}, { corner(8) })
	local closeBox = icon(closeButton, "close", "Muted", 14, 307)
	closeBox.AnchorPoint = Vector2.new(0.5, 0.5)
	closeBox.Position = UDim2.fromScale(0.5, 0.5)

	local keyIconCard = new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(24, 22),
		Size = UDim2.fromOffset(42, 42),
		ZIndex = 304,
		Theme = { BackgroundColor3 = "CardHover" },
	}, { corner(11), stroke("Accent", 1, 0.45) })
	local keyIcon = icon(keyIconCard, "key", "Accent", 20, 305)
	keyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	keyIcon.Position = UDim2.fromScale(0.5, 0.5)

	label({
		Parent = card,
		Position = UDim2.fromOffset(80, 20),
		Size = UDim2.new(1, -136, 0, 24),
		Font = FONT_B,
		TextSize = 18,
		Text = asText(config.Title, "Access required"),
		ZIndex = 304,
	})
	label({
		Parent = card,
		Position = UDim2.fromOffset(80, 44),
		Size = UDim2.new(1, -136, 0, 18),
		Font = FONT_M,
		TextSize = 12,
		Text = asText(config.Subtitle, "Choose a provider and unlock the script"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 304,
		Theme = { TextColor3 = "Muted" },
	})

	label({
		Parent = card,
		Position = UDim2.fromOffset(24, 84),
		Size = UDim2.new(1, -48, 0, 18),
		Font = FONT_SB,
		TextSize = 12,
		Text = "Choose key provider",
		ZIndex = 304,
		Theme = { TextColor3 = "SubText" },
	})

	local providerButtons = {}
	local providerWidth = (#providers == 1) and 452 or 220
	for i, provider in ipairs(providers) do
		local button = new("TextButton", {
			Parent = card,
			Position = UDim2.fromOffset(24 + (i - 1) * 232, 110),
			Size = UDim2.fromOffset(providerWidth, 66),
			AutoButtonColor = false,
			Text = "",
			ZIndex = 304,
			Theme = { BackgroundColor3 = "Card" },
		}, { corner(10), stroke("StrokeSoft", 1, 0) })

		local providerIcon = icon(button, provider.Icon, "Muted", 18, 306)
		providerIcon.Position = UDim2.fromOffset(15, 15)
		label({
			Parent = button,
			Position = UDim2.fromOffset(45, 10),
			Size = UDim2.new(1, -56, 0, 20),
			Font = FONT_SB,
			TextSize = 13,
			Text = provider.Name,
			ZIndex = 306,
		})
		label({
			Parent = button,
			Position = UDim2.fromOffset(45, 31),
			Size = UDim2.new(1, -56, 0, 25),
			Font = FONT_M,
			TextSize = 11,
			Text = provider.Description,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 306,
			Theme = { TextColor3 = "Muted" },
		})
		providerButtons[provider] = { Button = button, Icon = providerIcon }
	end

	label({
		Parent = card,
		Position = UDim2.fromOffset(24, 196),
		Size = UDim2.new(1, -48, 0, 18),
		Font = FONT_SB,
		TextSize = 12,
		Text = "License key",
		ZIndex = 304,
		Theme = { TextColor3 = "SubText" },
	})

	local inputFrame = new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(24, 222),
		Size = UDim2.new(1, -48, 0, 44),
		ZIndex = 304,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(9), stroke("Stroke", 1, 0.16) })
	innerShadow(inputFrame, 304, 0.5)
	local input = new("TextBox", {
		Parent = inputFrame,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = FONT_M,
		TextSize = 13,
		Text = "",
		PlaceholderText = asText(config.Placeholder, "Paste your key here"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 306,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "Muted" },
	})

	local status = label({
		Parent = card,
		Position = UDim2.fromOffset(24, 276),
		Size = UDim2.new(1, -48, 0, 34),
		Font = FONT_M,
		TextSize = 12,
		Text = "Select a provider, then get and enter your key.",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 304,
		Theme = { TextColor3 = "Muted" },
	})

	local function actionButton(text, x, primary)
		return new("TextButton", {
			Parent = card,
			Position = UDim2.fromOffset(x, 326),
			Size = UDim2.fromOffset(220, 42),
			AutoButtonColor = false,
			Font = FONT_SB,
			TextSize = 13,
			Text = text,
			ZIndex = 304,
			Theme = {
				BackgroundColor3 = primary and "Accent" or "Card",
				TextColor3 = "Text",
			},
		}, { corner(9), stroke(primary and "Accent" or "Stroke", 1, primary and 0.55 or 0.1) })
	end

	local getButton = actionButton(asText(config.GetKeyText, "Get key"), 24, false)
	local verifyButton = actionButton(asText(config.VerifyText, "Verify key"), 256, true)

	label({
		Parent = card,
		Position = UDim2.fromOffset(24, 388),
		Size = UDim2.new(1, -48, 0, 36),
		Font = FONT_M,
		TextSize = 11,
		Text = asText(config.Footer, "Your selected provider opens outside Roblox. Never share account passwords."),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 304,
		Theme = { TextColor3 = "Muted" },
	})

	local function setStatus(text, key)
		if not status.Parent then return end
		status.Text = asText(text, "")
		setThemeKey(status, "TextColor3", key or "Muted")
		status.TextColor3 = Theme[key or "Muted"]
	end

	local function refreshProviders()
		for provider, refs in next, providerButtons do
			local active = provider == selected
			setThemeKey(refs.Button, "BackgroundColor3", active and "CardHover" or "Card")
			refs.Button.BackgroundColor3 = Theme[active and "CardHover" or "Card"]
			local outline = refs.Button:FindFirstChildOfClass("UIStroke")
			if outline then
				setThemeKey(outline, "Color", active and "Accent" or "StrokeSoft")
				outline.Color = Theme[active and "Accent" or "StrokeSoft"]
				outline.Transparency = active and 0.25 or 0
			end
			recolorIcon(refs.Icon, active and "Accent" or "Muted")
		end
		window.KeySystemProvider = selected.Id
	end

	for provider, refs in next, providerButtons do
		refs.Button.MouseButton1Click:Connect(function()
			if busy or resolved or selected == provider then return end
			selected = provider
			input.Text = ""
			refreshProviders()
			setStatus(provider.Name .. " selected. Get a key to continue.", "Muted")
		end)
		refs.Button.MouseEnter:Connect(function()
			if selected ~= provider then
				tween(refs.Button, EASE_FAST, { BackgroundColor3 = Theme.CardHover })
			end
		end)
		refs.Button.MouseLeave:Connect(function()
			if selected ~= provider then
				tween(refs.Button, EASE_FAST, { BackgroundColor3 = Theme.Card })
			end
		end)
	end
	refreshProviders()

	local function resolveURL(provider)
		local source = provider.GetKeyURL
		if type(source) == "function" then
			local ok, result = pcall(source, sessionId, provider.Id)
			if not ok then
				warn("[AuroraUI] GetKeyURL failed: " .. tostring(result))
				return nil, tostring(result)
			end
			source = result
		end
		local url = type(source) == "string" and source:match("^%s*(.-)%s*$") or nil
		if not url or url == "" then return nil, "No key link is configured for " .. provider.Name .. "." end
		return url
	end

	getButton.MouseButton1Click:Connect(function()
		if busy or resolved then return end
		local url, urlError = resolveURL(selected)
		if not url then
			setStatus(asText(urlError, "Could not create a key link."), "Bad")
			return
		end

		if type(selected.OnGetKey) == "function" then
			local ok, handled, message = pcall(selected.OnGetKey, url, selected.Id, sessionId)
			if not ok then
				warn("[AuroraUI] OnGetKey failed: " .. tostring(handled))
				setStatus("Could not open the key link.", "Bad")
				return
			end
			if handled == false then
				setStatus(asText(message, "Could not open the key link."), "Bad")
				return
			end
			setStatus(asText(message, selected.Name .. " key page opened."), "Good")
			return
		end

		if copyToClipboard(url) then
			setStatus(selected.Name .. " link copied. Paste it into your browser.", "Good")
		else
			setStatus("Clipboard is unavailable. Configure OnGetKey for this executor.", "Bad")
		end
	end)

	local function unlock(provider, token, message)
		if resolved or not main.Parent then return end
		resolved = true
		busy = false
		window.KeySystemLocked = false
		window.KeySystemProvider = provider.Id
		writeKeyCache(window, config, provider, token)
		setStatus(message or "Access granted.", "Good")
		tween(card, EASE_FAST, { Position = UDim2.new(0.5, 0, 0.5, -8), BackgroundTransparency = 1 })
		tween(gate, EASE_FAST, { BackgroundTransparency = 1 })
		task.delay(0.16, function()
			if gate.Parent then gate:Destroy() end
			restoreShell()
		end)
		gateEvent:Fire(true)
	end

	local function tryKey(provider, key, cached)
		if busy or resolved then return end
		key = type(key) == "string" and key:match("^%s*(.-)%s*$") or ""
		if key == "" then
			if not cached then setStatus("Enter a key first.", "Bad") end
			return
		end

		busy = true
		verifyButton.Active = false
		verifyButton.Text = "Checking..."
		if not cached then setStatus("Verifying with " .. provider.Name .. "...", "Accent") end

		task.spawn(function()
			local valid, message, token = validateKey(config, provider, key, cached)
			if resolved or not gate.Parent then return end
			busy = false
			verifyButton.Active = true
			verifyButton.Text = asText(config.VerifyText, "Verify key")
			if valid then
				unlock(provider, asText(token, key), message)
			else
				if cached then clearKeyCache(window, config, provider) end
				setStatus(message, "Bad")
			end
		end)
	end

	verifyButton.MouseButton1Click:Connect(function()
		tryKey(selected, input.Text, false)
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then tryKey(selected, input.Text, false) end
	end)

	closeButton.MouseButton1Click:Connect(function()
		if not resolved and main.Parent then main:Destroy() end
	end)
	closeButton.MouseEnter:Connect(function()
		tween(closeButton, EASE_FAST, { BackgroundTransparency = 0 })
	end)
	closeButton.MouseLeave:Connect(function()
		tween(closeButton, EASE_FAST, { BackgroundTransparency = 1 })
	end)

	local destroyingConnection = main.Destroying:Connect(function()
		if resolved then return end
		resolved = true
		window.KeySystemLocked = false
		gateEvent:Fire(false)
	end)

	task.defer(function()
		for _, provider in ipairs(providers) do
			if resolved then break end
			local cached = readKeyCache(window, config, provider)
			if cached then
				selected = provider
				refreshProviders()
				setStatus("Checking saved " .. provider.Name .. " key...", "Accent")
				tryKey(provider, cached, true)
				while busy and not resolved and main.Parent do task.wait() end
			end
		end
		if not resolved and main.Parent then
			setStatus("Select a provider, then get and enter your key.", "Muted")
		end
	end)

	local unlocked = gateEvent.Event:Wait()
	destroyingConnection:Disconnect()
	gateEvent:Destroy()
	return unlocked == true
end

local Window = {}
Window.__index = Window

function Library:Window(opts)
	if not self.Alive then return nil end
	opts = type(opts) == "table" and opts or {}
	local self = setmetatable({}, Window)

	self.Title      = asText(opts.Title, "Aurora")
	self.Subtitle   = asText(opts.Subtitle, "v" .. Library.Version)
	self.Tabs       = {}
	self.ActiveTab  = nil
	self._options   = {}
	self._optionOrder = {}
	self._navOrder  = 0
	self._lastTabGroup = nil
	self.ConfigName = opts.Config or opts.ConfigKey
	self.Acrylic    = opts.Acrylic ~= false
	self.Minimized  = false
	self.Hidden     = false
	self.SidebarOpen = true
	self.ToggleKey  = typeof(opts.ToggleKey) == "EnumItem" and opts.ToggleKey or Enum.KeyCode.RightShift
	self.MinSize    = typeof(opts.MinSize) == "Vector2" and opts.MinSize or Vector2.new(760, 520)
	self.MinSize = Vector2.new(
		round(math.max(320, finiteNumber(self.MinSize.X, 600)), 0),
		round(math.max(180, finiteNumber(self.MinSize.Y, 400)), 0)
	)

	local size = typeof(opts.Size) == "UDim2" and opts.Size or UDim2.fromOffset(1180, 730)
	local savedSize = size

	--── корпус ──
	local Main = new("Frame", {
		Parent = Gui,
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = typeof(opts.Position) == "UDim2" and opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = size,
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Backdrop" },
	}, { corner(14) })
	self.Frame = Main
	snapGuiPosition(Main)
	local initialScale = math.clamp(finiteNumber(opts.Scale, 1), 0.5, 1.5)
	local windowScale = new("UIScale", { Parent = Main, Scale = initialScale })
	self.Scale = initialScale

	-- У главного окна нет внешней тени: на светлом фоне она превращается
	-- в заметный тёмный ореол. Тени остаются только у временных верхних
	-- слоёв — модалок, уведомлений и popup.

	local outerStroke = stroke("Stroke", 1, 0.08)
	outerStroke.Parent = Main
	new("UIGradient", {
		Parent = outerStroke,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 150, 160)),
			ColorSequenceKeypoint.new(0.48, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(132, 132, 144)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.48, 0.1),
			NumberSequenceKeypoint.new(1, 0.55),
		}),
	})

	local Clip = new("Frame", {
		Parent = Main,
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, { corner(14) })
	self.Clip = Clip
	topSheen(Clip, 30, 14, 0.78)

	--═══ ЛЕВАЯ ПАНЕЛЬ ═══
	local minimumWindowWidth = self.MinSize.X
	local sidebarWidth = round(math.clamp(finiteNumber(opts.SidebarWidth, 288), 210, 340), 0)
	self.SidebarWidth = sidebarWidth
	self.MinSize = Vector2.new(math.max(minimumWindowWidth, sidebarWidth + 280), self.MinSize.Y)

	local Sidebar = new("Frame", {
		Parent = Clip,
		Name = "Sidebar",
		Size = UDim2.new(0, sidebarWidth, 1, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Theme = { BackgroundColor3 = "Sidebar" },
	})
	surfaceNoise(Sidebar, 1, 0.93)
	new("UIGradient", {
		Parent = Sidebar,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(224, 224, 232)),
		}),
	})

	new("Frame", {  -- разделитель между панелью и контентом
		Parent = Sidebar,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "StrokeSoft" },
	})

	--── шапка панели: логотип + название ──
	local Brand = new("Frame", {
		Parent = Sidebar,
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
	})

	local logo = new("Frame", {
		Parent = Brand,
		Position = UDim2.fromOffset(24, 21),
		Size = UDim2.fromOffset(28, 28),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	assetLayer(Brand, "AccentGlow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(38, 35),
		Size = UDim2.fromOffset(44, 38),
		ZIndex = 1,
		ImageTransparency = 0.78,
		Theme = { ImageColor3 = "Accent" },
	})

	-- Геометрическая буква A из трёх чистых примитивов.
	new("Frame", {
		Parent = logo,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.38, 0, 0.52, 0),
		Size = UDim2.fromOffset(4, 27),
		Rotation = 22,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(2) })
	new("Frame", {
		Parent = logo,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.62, 0, 0.52, 0),
		Size = UDim2.fromOffset(4, 27),
		Rotation = -22,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Accent2" },
	}, { corner(2) })
	new("Frame", {
		Parent = logo,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(15, 3),
		ZIndex = 4,
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(2) })

	label({
		Parent = Brand,
		Position = UDim2.fromOffset(64, 20),
		Size = UDim2.new(1, -116, 0, 18),
		Font = FONT_B,
		TextSize = 16,
		Text = self.Title,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label({
		Parent = Brand,
		Position = UDim2.fromOffset(64, 39),
		Size = UDim2.new(1, -116, 0, 13),
		Font = FONT_M,
		TextSize = 12,
		Text = self.Subtitle,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Muted" },
	})

	local SidebarToggle = new("TextButton", {
		Parent = Clip,
		Position = UDim2.fromOffset(sidebarWidth - 46, 20),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 0.25,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 32,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(8), stroke("StrokeSoft", 1, 0) })
	local sidebarArrow = icon(SidebarToggle, "chevron", "Muted", 14, 33)
	sidebarArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	sidebarArrow.Position = UDim2.fromScale(0.5, 0.5)
	sidebarArrow.Rotation = 90

	--── поиск по всем вкладкам ──
	local SearchBox = new("Frame", {
		Parent = Sidebar,
		Position = UDim2.fromOffset(16, 76),
		Size = UDim2.new(1, -32, 0, 42),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(9), stroke("StrokeSoft", 1, 0) })
	innerShadow(SearchBox, 1, 0.42)
	topSheen(SearchBox, 2, 8, 0.93)

	local searchIcon = icon(SearchBox, "search", "Muted", 16)
	searchIcon.Position = UDim2.fromOffset(13, 13)

	local searchKeycap = new("Frame", {
		Parent = SearchBox,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(48, 24),
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(6), stroke("StrokeSoft", 1, 0.1) })
	label({
		Parent = searchKeycap,
		Size = UDim2.fromScale(1, 1),
		Font = FONT_M,
		TextSize = 10,
		Text = asText(opts.SearchKeyText, "CTRL K"),
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "Muted" },
	})

	local SearchInput = new("TextBox", {
		Parent = SearchBox,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -96, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_M,
		TextSize = 13,
		Text = "",
		PlaceholderText = asText(opts.SearchPlaceholder, "Поиск по настройкам"),
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "Muted" },
	})

	do  -- подсветка рамки поиска при фокусе
		local edge = SearchBox:FindFirstChildOfClass("UIStroke")
		SearchInput.Focused:Connect(function()
			setThemeKey(edge, "Color", "Accent")
			tween(edge, EASE_FAST, { Color = Theme.Accent })
			recolorIcon(searchIcon, "Accent")
			tween(searchKeycap, EASE_FAST, { BackgroundTransparency = 0.35 })
		end)
		SearchInput.FocusLost:Connect(function()
			setThemeKey(edge, "Color", "StrokeSoft")
			tween(edge, EASE_FAST, { Color = Theme.StrokeSoft })
			recolorIcon(searchIcon, "Muted")
			tween(searchKeycap, EASE_FAST, { BackgroundTransparency = 0 })
		end)
	end

	--── список вкладок ──
	local TabList = new("ScrollingFrame", {
		Parent = Sidebar,
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 1, -272),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Theme = { ScrollBarImageColor3 = "Muted" },
	}, { padding(0, 8, 14, 14), list(3) })
	self.TabList = TabList

	local PinnedTabList = new("Frame", {
		Parent = Sidebar,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -80),
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
	}, { padding(4, 4, 14, 14), list(3) })
	new("Frame", {
		Parent = PinnedTabList,
		Position = UDim2.fromOffset(0, -4),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "StrokeSoft" },
	})
	self.PinnedTabList = PinnedTabList

	--── подвал панели ──
	local Footer = new("Frame", {
		Parent = Sidebar,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
	})
	new("Frame", {
		Parent = Footer,
		Size = UDim2.new(1, -28, 0, 1),
		Position = UDim2.fromOffset(14, 0),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "StrokeSoft" },
	})
	local displayUser = LocalPlayer and LocalPlayer.DisplayName or asText(opts.UserText, "игрок")
	local avatarName = displayUser
	local avatarOK, avatarInitial = pcall(function()
		return utf8.char(utf8.codepoint(avatarName, 1)):upper()
	end)
	if not avatarOK then avatarInitial = "A" end
	local avatar = new("Frame", {
		Parent = Footer,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(42, 42),
		ClipsDescendants = true,
		Theme = { BackgroundColor3 = "CardHover" },
	}, { corner(8), stroke("StrokeSoft", 1, 0) })
	local avatarInitialLabel = label({
		Parent = avatar,
		Size = UDim2.fromScale(1, 1),
		Font = FONT_B,
		TextSize = 14,
		Text = avatarInitial,
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "Accent" },
	})
	local avatarImage = new("ImageLabel", {
		Parent = avatar,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
	})
	if LocalPlayer then
		task.spawn(function()
			local ok, image = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				LocalPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
			if ok and image and image ~= "" and avatarImage.Parent then
				avatarImage.Image = image
				avatarImage.Visible = true
				avatarInitialLabel.Visible = false
			end
		end)
	end

	label({
		Parent = Footer,
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -86, 1, 0),
		Font = FONT_SB,
		TextSize = 13,
		Text = displayUser,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Text" },
	})

	--═══ ПРАВАЯ ЧАСТЬ ═══
	local Content = new("Frame", {
		Parent = Clip,
		Name = "Content",
		Position = UDim2.fromOffset(sidebarWidth, 0),
		Size = UDim2.new(1, -sidebarWidth, 1, 0),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Content" },
	})
	self.Content = Content
	surfaceNoise(Content, 1, 0.93)
	new("UIGradient", {
		Parent = Content,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 226, 234)),
		}),
	})

	--── верхняя полоса: заголовок вкладки + кнопки окна ──
	local TopBar = new("Frame", {
		Parent = Content,
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundTransparency = 0.68,
		Theme = { BackgroundColor3 = "Sidebar" },
	})
	new("UIGradient", {
		Parent = TopBar,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(0.62, 0.5),
			NumberSequenceKeypoint.new(1, 0.78),
		}),
	})
	local HeaderIcon = new("ImageLabel", {
		Parent = TopBar,
		Position = UDim2.fromOffset(36, 31),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Theme = { ImageColor3 = "SubText" },
	})
	self.HeaderIcon = HeaderIcon

	local TabTitle = label({
		Parent = TopBar,
		Position = UDim2.fromOffset(76, 27),
		Size = UDim2.new(1, -206, 0, 22),
		Font = FONT_B,
		TextSize = 18,
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local TabDesc = label({
		Parent = TopBar,
		Position = UDim2.fromOffset(76, 51),
		Size = UDim2.new(1, -206, 0, 16),
		Font = FONT_M,
		TextSize = 12,
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Muted" },
	})
	self.TabTitle = TabTitle
	self.TabDesc  = TabDesc

	new("Frame", {
		Parent = TopBar,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "StrokeSoft" },
	})

	-- Кнопки окна: иконки нарисованы фреймами, а не глифами шрифта,
	-- поэтому не превращаются в пустые прямоугольники.
	local function winButton(iconName, offsetX, hoverKey)
		local b = new("TextButton", {
			Parent = TopBar,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, offsetX, 0, 24),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = "",
			Theme = { BackgroundColor3 = "CardHover" },
		}, { corner(8) })

		local box = icon(b, iconName, "Muted", 16, 3)
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)

		local function paint(key)
			local color = Theme[key]
			for _, part in ipairs(box:GetDescendants()) do
				if part:IsA("Frame") then
					setThemeKey(part, "BackgroundColor3", key)
					tween(part, EASE_FAST, { BackgroundColor3 = color })
				elseif part:IsA("UIStroke") then
					setThemeKey(part, "Color", key)
					tween(part, EASE_FAST, { Color = color })
				end
			end
		end

		b.MouseEnter:Connect(function()
			tween(b, EASE_FAST, { BackgroundTransparency = 0 })
			paint(hoverKey)
		end)
		b.MouseLeave:Connect(function()
			tween(b, EASE_FAST, { BackgroundTransparency = 1 })
			paint("Muted")
		end)
		return b, box
	end

	local BtnClose = winButton("close", -16, "Bad")
	local BtnMax = winButton("maximize", -50, "Text")
	local BtnMin, BtnMinBox = winButton("minimize", -84, "Text")
	local maximized = false

	--── прокручиваемая область страницы ──
	local Pages = new("Frame", {
		Parent = Content,
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 1, -90),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	self.Pages = Pages

	--── ручка изменения размера ──
	local Grip = new("TextButton", {
		Parent = Clip,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -3),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 20,
	})
	icon(Grip, "grip", "Muted", 16, 21)

	Grip.InputBegan:Connect(function(input)
		if not isPressStart(input) or self.Minimized or self.Hidden or maximized then return end
		local origin = input.Position
		local startSize = Main.AbsoluteSize
		activeDrag = function(i)
			local d = i.Position - origin
			Main.Size = UDim2.fromOffset(
				round(math.max(self.MinSize.X, startSize.X + d.X), 0),
				round(math.max(self.MinSize.Y, startSize.Y + d.Y), 0)
			)
			savedSize = Main.Size
		end
	end)

	--── перетаскивание за верхнюю полосу и шапку панели ──
	draggable(TopBar, Main, closePopup, function() return not maximized end)
	draggable(Brand, Main, closePopup, function() return not maximized end)

	--═══ ПОВЕДЕНИЕ ОКНА ═══
	local minimizeToken = 0
	local visibilityToken = 0
	local sidebarOpen = true

	local function applyChrome(minimized)
		Sidebar.Visible = not minimized
		SidebarToggle.Visible = not minimized
		Pages.Visible = not minimized
		Grip.Visible = not minimized and not maximized
		if minimized then
			Content.Position = UDim2.new()
			Content.Size = UDim2.fromScale(1, 1)
		else
			local width = sidebarOpen and sidebarWidth or 0
			Content.Position = UDim2.fromOffset(width, 0)
			Content.Size = UDim2.new(1, -width, 1, 0)
		end
	end

	SidebarToggle.MouseEnter:Connect(function()
		tween(SidebarToggle, EASE_FAST, { BackgroundTransparency = 0 })
		recolorIcon(sidebarArrow, "Text")
	end)
	SidebarToggle.MouseLeave:Connect(function()
		tween(SidebarToggle, EASE_FAST, { BackgroundTransparency = 0.25 })
		recolorIcon(sidebarArrow, "Muted")
	end)
	function self:SetSidebarOpen(state)
		if not Library.Alive or not Main.Parent or self.Minimized then return false end
		state = state and true or false
		if sidebarOpen == state then return true end
		sidebarOpen = state
		self.SidebarOpen = sidebarOpen
		closePopup()
		tween(Sidebar, EASE, { Size = UDim2.new(0, sidebarOpen and sidebarWidth or 0, 1, 0) })
		tween(Content, EASE, {
			Position = UDim2.fromOffset(sidebarOpen and sidebarWidth or 0, 0),
			Size = UDim2.new(1, sidebarOpen and -sidebarWidth or 0, 1, 0),
		})
		tween(SidebarToggle, EASE, {
			Position = UDim2.fromOffset(sidebarOpen and (sidebarWidth - 46) or 14, 20),
		})
		tween(sidebarArrow, EASE, { Rotation = sidebarOpen and 90 or -90 })
		return true
	end

	function self:SetSidebarWidth(width)
		if not Library.Alive or not Main.Parent then return false end
		sidebarWidth = round(math.clamp(finiteNumber(width, sidebarWidth), 210, 340), 0)
		self.SidebarWidth = sidebarWidth
		self.MinSize = Vector2.new(math.max(minimumWindowWidth, sidebarWidth + 280), self.MinSize.Y)
		Sidebar.Size = UDim2.new(0, sidebarOpen and sidebarWidth or 0, 1, 0)
		Content.Position = UDim2.fromOffset(sidebarOpen and sidebarWidth or 0, 0)
		Content.Size = UDim2.new(1, sidebarOpen and -sidebarWidth or 0, 1, 0)
		SidebarToggle.Position = UDim2.fromOffset(sidebarOpen and (sidebarWidth - 46) or 14, 20)
		return true
	end

	SidebarToggle.MouseButton1Click:Connect(function()
		if self.Minimized then return end
		self:SetSidebarOpen(not sidebarOpen)
	end)

	-- иконка кнопки перерисовывается, а не подменяется символом
	local function setMinIcon(name)
		for _, c in ipairs(BtnMinBox:GetChildren()) do c:Destroy() end
		if Icons[name] then Icons[name](BtnMinBox, "Muted", 4) end
	end

	function self:SetMinimized(state)
		if not Library.Alive or not Main.Parent then return false end
		state = state and true or false
		if self.Minimized == state then return true end
		self.Minimized = state
		minimizeToken += 1
		local token = minimizeToken
		closePopup()
		if self._hideResults then self._hideResults() end
		if state then
			if not self.Hidden then
				local absolute = Main.AbsoluteSize
				if absolute.X > 0 and absolute.Y > 0 then
					savedSize = UDim2.fromOffset(
						round(absolute.X, 0),
						round(absolute.Y, 0)
					)
				end
				tween(Main, EASE, { Size = UDim2.fromOffset(380, 90) })
			end
			applyChrome(true)
			setMinIcon("expand")
		else
			if self.Hidden then
				applyChrome(false)
			else
				tween(Main, EASE, { Size = savedSize })
				task.delay(0.22, function()
					if token == minimizeToken and not self.Minimized and not self.Hidden and Main.Parent then
						applyChrome(false)
						snapGuiPosition(Main)
					end
				end)
			end
			setMinIcon("minimize")
		end
		return true
	end

	function self:SetVisible(state)
		if not Library.Alive or not Main.Parent then return false end
		state = state and true or false
		if state == (not self.Hidden) then return true end
		self.Hidden = not state
		visibilityToken += 1
		local token = visibilityToken
		closePopup()
		if self._hideResults then self._hideResults() end
		if state then
			Main.Visible = true
			applyChrome(self.Minimized)
			local targetSize = self.Minimized and UDim2.fromOffset(380, 90) or savedSize
			tween(Main, EASE, { Size = targetSize })
			task.delay(0.22, function()
				if token == visibilityToken and not self.Hidden and Main.Parent then
					snapGuiPosition(Main)
				end
			end)
		else
			if not self.Minimized then
				local absolute = Main.AbsoluteSize
				if absolute.X > 0 and absolute.Y > 0 then
					savedSize = UDim2.fromOffset(
						round(absolute.X, 0),
						round(absolute.Y, 0)
					)
				end
			end
			local width = Main.Size.X
			tween(Main, EASE_FAST, { Size = UDim2.new(width.Scale, width.Offset, 0, 0) })
			task.delay(0.14, function()
				if token == visibilityToken and self.Hidden and Main.Parent then
					Main.Visible = false
				end
			end)
		end
		if self.FloatButton then self.FloatButton.Visible = not state end
		refreshBlur()
		return true
	end

	function self:Toggle() return self:SetVisible(self.Hidden) end

	function self:Notify(o) return Library:Notify(o) end

	function self:SetAcrylic(state)
		if not Library.Alive or not Main.Parent then return false end
		self.Acrylic = state ~= false
		refreshBlur()
		return true
	end

	function self:SetScale(scale)
		if not Library.Alive or not Main.Parent then return false end
		scale = math.clamp(finiteNumber(scale, self.Scale), 0.5, 1.5)
		self.Scale = scale
		tween(windowScale, EASE_FAST, { Scale = scale })
		return true
	end

	local restoreSize = savedSize
	local restorePosition = Main.Position
	BtnMax.MouseButton1Click:Connect(function()
		if self.Minimized or self.Hidden then return end
		if maximized then
			maximized = false
			Grip.Visible = true
			savedSize = restoreSize
			tween(Main, EASE, { Size = restoreSize, Position = restorePosition })
			task.delay(0.24, function()
				if not maximized and Main.Parent then snapGuiPosition(Main) end
			end)
		else
			maximized = true
			Grip.Visible = false
			restoreSize = UDim2.fromOffset(
				round(Main.AbsoluteSize.X, 0),
				round(Main.AbsoluteSize.Y, 0)
			)
			restorePosition = Main.Position
			local vp = viewport()
			local target = UDim2.fromOffset(
				round(math.max(self.MinSize.X, vp.X - 72), 0),
				round(math.max(self.MinSize.Y, vp.Y - 72), 0)
			)
			savedSize = target
			tween(Main, EASE, { Size = target, Position = UDim2.fromScale(0.5, 0.5) })
			task.delay(0.24, function()
				if maximized and Main.Parent then snapGuiPosition(Main) end
			end)
		end
	end)
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
	local stopWindowInput = onInput("Began", function(input, processed)
		if self.Hidden == nil then return end
		if self.KeySystemLocked then return end
		local ctrlK = input.KeyCode == Enum.KeyCode.K
			and (UserInput:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInput:IsKeyDown(Enum.KeyCode.RightControl))
		if ctrlK then
			self:SetVisible(true)
			task.defer(function()
				if SearchInput.Parent then SearchInput:CaptureFocus() end
			end)
			return
		end
		if not processed and self.ToggleKey
			and (input.KeyCode == self.ToggleKey or input.UserInputType == self.ToggleKey) then
			self:Toggle()
		end
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
			Text = "",
			Visible = false,
			ZIndex = 800,
			Theme = { BackgroundColor3 = "Card", TextColor3 = "Accent" },
		}, { corner(23), stroke("Accent", 1, 0.4) })
		new("Frame", {
			Parent = float,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			ZIndex = 801,
			Theme = { BackgroundColor3 = "Accent" },
		}, { corner(3) })

		local floatDragged = false
		float.InputBegan:Connect(function(input)
			if not isPressStart(input) then return end
			floatDragged = false
			local origin = input.Position
			local startAbs = float.AbsolutePosition
			local startPosition = float.Position
			activeDrag = function(i)
				local delta = i.Position - origin
				if delta.Magnitude > 5 then floatDragged = true end
				local vp = viewport()
				local x = math.clamp(startAbs.X + delta.X, 0, math.max(0, vp.X - 46))
				local y = math.clamp(startAbs.Y + delta.Y, 0, math.max(0, vp.Y - 46))
				local adjusted = Vector2.new(x - startAbs.X, y - startAbs.Y)
				float.Position = UDim2.new(
					startPosition.X.Scale, startPosition.X.Offset + adjusted.X,
					startPosition.Y.Scale, startPosition.Y.Offset + adjusted.Y
				)
			end
		end)
		float.MouseButton1Click:Connect(function()
			if not floatDragged then self:SetVisible(true) end
		end)
		self.FloatButton = float
	end

	--── появление окна ──
	-- Key System сам временно уменьшает Main до своей карточки. Если сначала
	-- запустить обычный tween от нулевой высоты, он запомнит промежуточный
	-- размер и после авторизации восстановит окно как одну горизонтальную линию.
	local keySystemOptions = opts.KeySystem
	local keySystemEnabled = keySystemOptions ~= nil
		and keySystemOptions ~= false
		and not (type(keySystemOptions) == "table" and keySystemOptions.Enabled == false)
	if keySystemEnabled then
		Main.Size = size
		snapGuiPosition(Main)
	else
		Main.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, 0)
		tween(Main, EASE_SLOW, { Size = size })
		task.delay(0.44, function()
			if Main.Parent then snapGuiPosition(Main) end
		end)
	end

	--═══ ПОИСК / КОМАНДНАЯ ПАЛИТРА ═══
	local Results = new("Frame", {
		Parent = Overlay,
		Size = UDim2.fromOffset(280, 0),
		Visible = false,
		ZIndex = 600,
		ClipsDescendants = true,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(10), stroke("Stroke", 1, 0.2) })
	topSheen(Results, 604, 10, 0.86)

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
	self._hideResults = hideResults

	local function runSearch(query)
		for _, c in ipairs(ResultList:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		query = normalizeSearch(query):gsub("^%s+", ""):gsub("%s+$", "")
		if #query < 2 then hideResults() return end

		for i = #Library.SearchIndex, 1, -1 do
			local entry = Library.SearchIndex[i]
			if not entry.card or not entry.card.Parent
				or not entry.tab or not entry.tab.Page or not entry.tab.Page.Parent then
				table.remove(Library.SearchIndex, i)
			end
		end

		local found = 0
		for _, entry in ipairs(Library.SearchIndex) do
			if entry.window == self and entry.searchName:find(query, 1, true) then
				if found >= 8 then break end
				found += 1

				local item = new("TextButton", {
					Parent = ResultList,
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					BorderSizePixel = 0,
					Text = "",
					LayoutOrder = found,
					ZIndex = 602,
					Theme = { BackgroundColor3 = "CardHover" },
				}, { corner(8) })

				label({
					Parent = item,
					Position = UDim2.fromOffset(10, 5),
					Size = UDim2.new(1, -20, 0, 15),
					TextSize = 13,
					Text = entry.name,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 603,
				})
				label({
					Parent = item,
					Position = UDim2.fromOffset(10, 20),
					Size = UDim2.new(1, -20, 0, 13),
					Font = FONT_M,
					TextSize = 12,
					Text = entry.tab.Name .. "  /  " .. entry.kind,
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
					task.defer(function()
						local page = entry.tab.Page
						if not page or not page.Parent or not entry.card or not entry.card.Parent then return end
						local targetY = entry.card.AbsolutePosition.Y
							- page.AbsolutePosition.Y + page.CanvasPosition.Y - 16
						local maxY = math.max(0, page.AbsoluteCanvasSize.Y - page.AbsoluteWindowSize.Y)
						page.CanvasPosition = Vector2.new(page.CanvasPosition.X, math.clamp(targetY, 0, maxY))
						task.spawn(flashCard, entry.card)
					end)
				end)
			end
		end

		if found == 0 then hideResults() return end
		Results.Visible = true
		Results.Position = overlayPosition(
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
			if SearchInput.Parent and not SearchInput:IsFocused() then hideResults() end
		end)
	end)

	table.insert(Library.Windows, self)
	refreshBlur()

	local windowCleaned = false
	local function cleanupWindow()
		if windowCleaned then return end
		windowCleaned = true
		self.Hidden = nil
		stopWindowInput()
		if Results.Parent then Results:Destroy() end
		if self.FloatButton and self.FloatButton.Parent then self.FloatButton:Destroy() end
		table.clear(self._options)
		table.clear(self._optionOrder)
		for i = #Library.Windows, 1, -1 do
			if Library.Windows[i] == self then
				table.remove(Library.Windows, i)
				break
			end
		end
		if Library.Alive then task.defer(refreshBlur) end
	end
	Main.Destroying:Connect(cleanupWindow)

	function self:Destroy()
		if not Main.Parent then return false end
		Main:Destroy()
		return true
	end

	if not runKeySystem(self, opts.KeySystem, Main) then
		return nil
	end

	return self
end

--═══════════════════════════════════════════════════════════════════════
--  11. ВКЛАДКИ
--═══════════════════════════════════════════════════════════════════════

local Tab = {}
Tab.__index = Tab

local function tabAlive(tab)
	return Library.Alive and tab and tab.Page and tab.Page.Parent ~= nil
end

function Window:SelectTab(tab)
	if not Library.Alive then return false end
	if type(tab) ~= "table" or tab.Window ~= self or not tab.Page or not tab.Page.Parent then
		return false
	end
	if self.ActiveTab == tab then return true end
	closePopup()

	for _, t in ipairs(self.Tabs) do
		local active = (t == tab)
		t.Page.Visible = active
		setThemeKey(t._btn, "BackgroundColor3", active and "CardHover" or "Card")
		tween(t._btn, EASE_FAST, {
			BackgroundTransparency = active and 0.18 or 1,
			BackgroundColor3 = active and Theme.CardHover or Theme.Card,
		})
		if t._btnStroke then
			tween(t._btnStroke, EASE_FAST, { Transparency = active and 0.68 or 1 })
		end
		setThemeKey(t._label, "TextColor3", active and "Accent" or "SubText")
		tween(t._label, EASE_FAST, { TextColor3 = active and Theme.Accent or Theme.SubText })

		-- В desktop-навигации акцент получает сама иконка и тонкий маркер,
		-- без отдельной тяжёлой плашки вокруг каждой иконки.
		tween(t._chip, EASE_FAST, { BackgroundTransparency = 1 })
		setThemeKey(t._chipText, "TextColor3", active and "Accent" or "SubText")
		tween(t._chipText, EASE_FAST, {
			TextColor3 = active and Theme.Accent or Theme.SubText,
		})
		if t._chipImage then
			setThemeKey(t._chipImage, "ImageColor3", active and "Accent" or "SubText")
			tween(t._chipImage, EASE_FAST, {
				ImageColor3 = active and Theme.Accent or Theme.SubText,
			})
		end

		tween(t._marker, EASE, {
			Size = UDim2.new(0, 3, 0, active and 18 or 0),
			BackgroundTransparency = active and 0 or 1,
		})
	end

	self.ActiveTab = tab
	if self.TabTitle then self.TabTitle.Text = tab.Name end
	if self.TabDesc then self.TabDesc.Text = tab.Desc or "" end
	if self.HeaderIcon then
		local data = tab._iconData
		self.HeaderIcon.Visible = data ~= nil
		if data then
			self.HeaderIcon.Image = data.image
			self.HeaderIcon.ImageRectSize = data.rect or Vector2.zero
			self.HeaderIcon.ImageRectOffset = data.offset or Vector2.zero
		end
	end

	-- Мягкое появление страницы. Двигаем саму страницу, а не её детей:
	-- позицией детей управляет UIListLayout, и анимировать их бесполезно.
	tab.Page.Position = UDim2.fromOffset(0, 12)
	tween(tab.Page, EASE, { Position = UDim2.fromOffset(0, 0) })
	return true
end

function Window:Tab(opts)
	if not Library.Alive or not self.Pages or not self.Pages.Parent then return nil end
	opts = type(opts) == "table" and opts or {}
	local tab = setmetatable({}, Tab)
	tab.Name   = asText(opts.Name ~= nil and opts.Name or opts.Text, "Вкладка")
	tab.Desc   = opts.Desc ~= nil and tostring(opts.Desc) or nil
	tab.Window = self
	tab._order = 0
	tab._section = nil
	tab._columnCount = math.clamp(math.floor(finiteNumber(opts.Columns, 1)), 1, 2)
	tab._columnCursor = 0
	tab._columns = {}

	--── кнопка в сайдбаре ──
	local pinned = opts.Pinned == true
	local navParent = pinned and self.PinnedTabList or self.TabList
	if not pinned then
		local group = asText(opts.Group, "General")
		if self._lastTabGroup ~= group then
			self._lastTabGroup = group
			self._navOrder += 1
			local groupRow = new("Frame", {
				Parent = navParent,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				LayoutOrder = self._navOrder,
			})
			label({
				Parent = groupRow,
				Position = UDim2.fromOffset(2, 10),
				Size = UDim2.new(1, -4, 0, 12),
				Font = FONT_SB,
				TextSize = 10,
				Text = group:upper(),
				Theme = { TextColor3 = "Muted" },
			})
		end
	end
	self._navOrder += 1
	local btn = new("TextButton", {
		Parent = navParent,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = self._navOrder,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(9) })
	local btnStroke = stroke("Accent", 1, 1)
	btnStroke.Parent = btn
	topSheen(btn, 3, 8, 0.94)

	local marker = new("Frame", {
		Parent = btn,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.new(0, 3, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(2) })

	-- Вместо юникод-глифа — «чип»: скруглённый квадрат с первой буквой.
	-- Всегда рендерится, выглядит намеренно и подсвечивается акцентом
	-- на активной вкладке.
	local chip = new("Frame", {
		Parent = btn,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(7) })

	local iconData = resolveIcon(opts.Icon)
	local chipImage
	if iconData then
		chipImage = new("ImageLabel", {
			Parent = chip,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(15, 15),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Image = iconData.image,
			-- нулевой Rect означает «взять всю картинку», для спрайтшита
			-- подставляются реальные координаты вырезки
			ImageRectSize = iconData.rect or Vector2.zero,
			ImageRectOffset = iconData.offset or Vector2.zero,
			Theme = { ImageColor3 = "Muted" },
		})
	end

	-- Запасной вариант, если иконку не указали или имя не распознано:
	-- первая буква названия. utf8 нужен, чтобы не разрезать кириллицу.
	local chipText = label({
		Parent = chip,
		Size = UDim2.fromScale(1, 1),
		Font = FONT_B,
		TextSize = 12,
		Text = chipImage and "" or (function()
			local ok, ch = pcall(function()
				return utf8.char(utf8.codepoint(tab.Name, 1))
			end)
			return (ok and ch or "A"):upper()
		end)(),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Theme = { TextColor3 = "Muted" },
	})

	local nameLbl = label({
		Parent = btn,
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -52, 1, 0),
		Font = FONT_M,
		TextSize = 13,
		Text = tab.Name,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Theme = { TextColor3 = "SubText" },
	})

	btn.MouseEnter:Connect(function()
		if self.ActiveTab ~= tab then
			tween(btn, EASE_FAST, { BackgroundTransparency = 0.4 })
			setThemeKey(nameLbl, "TextColor3", "Text")
			tween(nameLbl, EASE_FAST, { TextColor3 = Theme.Text })
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.ActiveTab ~= tab then
			tween(btn, EASE_FAST, { BackgroundTransparency = 1 })
			setThemeKey(nameLbl, "TextColor3", "SubText")
			tween(nameLbl, EASE_FAST, { TextColor3 = Theme.SubText })
		end
	end)
	btn.MouseButton1Click:Connect(function() self:SelectTab(tab) end)

	-- Внутренние ссылки на элементы сайдбара держим под префиксом «_».
	-- Без него поле tab.Button перекрывало бы метод Tab:Button через
	-- __index, и вызов Tab:Button{...} падал бы на попытке вызвать Instance.
	tab._btn       = btn
	tab._btnStroke = btnStroke
	tab._label     = nameLbl
	tab._marker    = marker
	tab._chip      = chip
	tab._chipText  = chipText
	tab._chipImage = chipImage
	tab._iconData  = iconData

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
	}, { padding(12, 24, 36, 26) })

	local pageRoot = new("Frame", {
		Parent = tab.Page,
		Name = "PageRoot",
		Size = UDim2.new(1, -62, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, { list(10) })
	local columnsHost = new("Frame", {
		Parent = pageRoot,
		Name = "Columns",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	})
	local columnsLayout = new("UIListLayout", {
		Parent = columnsHost,
		Padding = UDim.new(0, 10),
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i = 1, tab._columnCount do
		tab._columns[i] = new("Frame", {
			Parent = columnsHost,
			Name = "Column_" .. i,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, { list(10) })
	end
	tab._columnsHost = columnsHost
	tab._columnsLayout = columnsLayout
	tab._fullColumn = new("Frame", {
		Parent = pageRoot,
		Name = "FullWidth",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, { list(10) })
	tab._pageRoot = pageRoot

	local function updateColumns()
		if not columnsHost.Parent then return end
		local sideBySide = tab._columnCount > 1 and tab.Page.AbsoluteSize.X >= 760
		columnsLayout.FillDirection = sideBySide
			and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		for _, column in ipairs(tab._columns) do
			column.Size = sideBySide
				and UDim2.new(1 / tab._columnCount, -5, 0, 0)
				or UDim2.new(1, 0, 0, 0)
		end
	end
	tab.Page:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateColumns)
	updateColumns()

	table.insert(self.Tabs, tab)
	if not self.ActiveTab then self:SelectTab(tab) end
	return tab
end

--── регистрация элемента в поиске ──
local function index(tab, name, kind, card)
	local entry = {
		window = tab.Window,
		tab = tab,
		name = asText(name, "Элемент"),
		kind = asText(kind, "элемент"),
		card = card,
	}
	entry.searchName = normalizeSearch(entry.name)
	table.insert(Library.SearchIndex, entry)
	pcall(function()
		card.Destroying:Connect(function()
			for i = #Library.SearchIndex, 1, -1 do
				if Library.SearchIndex[i] == entry then
					table.remove(Library.SearchIndex, i)
					break
				end
			end
		end)
	end)
	return entry
end

local function nextOrder(tab)
	tab._order += 1
	return tab._order
end

--═══════════════════════════════════════════════════════════════════════
--  12. ВИДЖЕТЫ
--═══════════════════════════════════════════════════════════════════════

--────────────────────────── Заголовок секции ──────────────────────────
-- Открывает новую группу: последующие элементы лягут внутрь неё строками.
function Tab:Section(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local targetColumn = opts.Span == 2 and "full" or opts.Column
	local section = openSection(self, opts.Text or opts.Name, targetColumn, opts.MinHeight)
	return {
		Set = function(_, text)
			if not section.holder.Parent then return false end
			if section.header then section.header.Text = asText(text, "") end
			return true
		end,
		Destroy = function()
			if self._section == section then self._section = nil end
			if section.holder.Parent then section.holder:Destroy() end
		end,
	}
end

--──────────────────────────── Разделитель ────────────────────────────
-- Закрывает текущую группу: следующий элемент начнёт новую карточку.
function Tab:Divider()
	if not tabAlive(self) then return nil end
	self._section = nil
	local spacer = new("Frame", {
		Parent = self._lastColumn or self._columns[1] or self.Page,
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	})
	return { Destroy = function() if spacer.Parent then spacer:Destroy() end end }
end

--────────────────────────────── Текст ──────────────────────────────
function Tab:Paragraph(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local section = self._section or openSection(self, nil)

	local row = new("Frame", {
		Parent = section.card,
		Name = "Item",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = section.rows + 1 + section.rowOffset,
	}, { padding(12, 14, 16, 16), list(5) })
	section.rows += 1

	if section.rows > 1 then
		new("Frame", {
			Parent = row,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
			Theme = { BackgroundColor3 = "StrokeSoft" },
		})
	end

	local title = label({
		Parent = row,
		Size = UDim2.new(1, 0, 0, 16),
		Font = FONT_M,
		TextSize = 13,
		Text = asText(opts.Text ~= nil and opts.Text or opts.Title, "Заметка"),
		LayoutOrder = 1,
	})
	local body = label({
		Parent = row,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 12,
		Text = asText(opts.Content ~= nil and opts.Content or opts.Desc, ""),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
		Theme = { TextColor3 = "Muted" },
	})

	local searchEntry = index(self, title.Text, "текст", row)
	return {
		Set = function(_, t, c)
			if not row.Parent then return false end
			if t ~= nil then
				title.Text = tostring(t)
				searchEntry.name = title.Text
				searchEntry.searchName = normalizeSearch(title.Text)
			end
			if c ~= nil then body.Text = tostring(c) end
			return true
		end,
		Destroy = function() if row.Parent then row:Destroy() end end,
	}
end

--────────────────────────────── Кнопка ──────────────────────────────
function Tab:Button(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local controlWidth = math.max(72, finiteNumber(opts.SlotWidth, 110))
	local card, slot = makeCard(self, opts, controlWidth)
	slot.Size = UDim2.fromOffset(controlWidth, 30)

	local btn = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(controlWidth, 30),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_SB,
		TextSize = 13,
		Text = asText(opts.ButtonText, "Выполнить"),
		Theme = { BackgroundColor3 = "CardHover", TextColor3 = "Text" },
	}, { corner(8), stroke("StrokeSoft", 1, 0) })
	topSheen(btn, 2, 7, 0.88)

	btn.MouseEnter:Connect(function()
		setThemeKey(btn, "BackgroundColor3", "Accent")
		setThemeKey(btn, "TextColor3", "Text")
		tween(btn, EASE_FAST, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.Text })
	end)
	btn.MouseLeave:Connect(function()
		setThemeKey(btn, "BackgroundColor3", "CardHover")
		setThemeKey(btn, "TextColor3", "Text")
		tween(btn, EASE_FAST, { BackgroundColor3 = Theme.CardHover, TextColor3 = Theme.Text })
	end)
	btn.MouseButton1Click:Connect(function()
		tween(btn, TweenInfo.new(0.08), { Size = UDim2.fromOffset(math.max(68, controlWidth - 6), 28) })
		task.delay(0.09, function()
			if btn.Parent then tween(btn, EASE_FAST, { Size = UDim2.fromOffset(controlWidth, 30) }) end
		end)
		if opts.Confirm then
			Library:Dialog{
				Title = asText(opts.Text, "Подтверждение"),
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

	index(self, asText(opts.Text, "Кнопка"), "кнопка", card)
	return {
		Destroy = function() if card.Parent then card:Destroy() end end,
		Card = card,
	}
end

--──────────────────────── Акцентный preview-ряд ────────────────────────
-- Композит для галереи темы: показывает базовые состояния рядом,
-- как в desktop-макете, но остаётся собранным из обычных примитивов.
function Tab:Preview(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local slotWidth = math.max(560, finiteNumber(opts.SlotWidth, 650))
	local card, slot = makeCard(self, {
		Text = opts.Text or "Accent preview",
		Desc = opts.Desc or "This is how your accent color looks in action",
		Height = opts.Height or 76,
	}, slotWidth, opts.Height or 76)
	slot.Size = UDim2.fromOffset(slotWidth, 36)

	new("UIListLayout", {
		Parent = slot,
		Padding = UDim.new(0, 18),
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local function sampleButton(text, width, primary, order)
		local button = new("TextButton", {
			Parent = slot,
			Size = UDim2.fromOffset(width, 36),
			AutoButtonColor = false,
			Text = text,
			Font = FONT_M,
			TextSize = 12,
			LayoutOrder = order,
			Theme = {
				BackgroundColor3 = primary and "Accent" or "Inset",
				TextColor3 = "Text",
			},
		}, { corner(7), stroke(primary and "Accent" or "StrokeSoft", 1, primary and 0.4 or 0) })
		topSheen(button, 3, 7, primary and 0.72 or 0.9)
		return button
	end

	local primary = sampleButton("Primary", 96, true, 1)
	local secondary = sampleButton("Secondary", 108, false, 2)

	local dropdown = new("Frame", {
		Parent = slot,
		Size = UDim2.fromOffset(150, 36),
		LayoutOrder = 3,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(7), stroke("StrokeSoft", 1, 0) })
	label({
		Parent = dropdown,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -42, 1, 0),
		Font = FONT_M,
		TextSize = 12,
		Text = "Dropdown",
	})
	local previewArrow = icon(dropdown, "chevron", "Muted", 14, 3)
	previewArrow.AnchorPoint = Vector2.new(1, 0.5)
	previewArrow.Position = UDim2.new(1, -12, 0.5, 0)

	local toggle = new("Frame", {
		Parent = slot,
		Size = UDim2.fromOffset(48, 26),
		LayoutOrder = 4,
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(13), stroke("Accent", 1, 0.35) })
	new("Frame", {
		Parent = toggle,
		Position = UDim2.fromOffset(25, 3),
		Size = UDim2.fromOffset(20, 20),
		Theme = { BackgroundColor3 = "Text" },
	}, { corner(10) })

	local previewSlider = new("Frame", {
		Parent = slot,
		Size = UDim2.fromOffset(174, 5),
		LayoutOrder = 5,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(3) })
	new("Frame", {
		Parent = previewSlider,
		Size = UDim2.fromScale(0.48, 1),
		Theme = { BackgroundColor3 = "Accent" },
	}, { corner(3), registerGradient(new("UIGradient", {}), "Accent", "Accent2") })
	new("Frame", {
		Parent = previewSlider,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.48, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Theme = { BackgroundColor3 = "Text" },
	}, { corner(7), stroke("Accent", 2, 0.35) })

	primary.MouseButton1Click:Connect(function() safeCall(opts.Callback, "primary") end)
	secondary.MouseButton1Click:Connect(function() safeCall(opts.Callback, "secondary") end)

	index(self, opts.Text or "Accent preview", "preview", card)
	return {
		Card = card,
		Destroy = function() if card.Parent then card:Destroy() end end,
	}
end

--────────────────────────────── Тоггл ──────────────────────────────
function Tab:Toggle(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local flag = optionFlag(opts)
	local card, slot = makeCard(self, opts, 60)
	local state = opts.Default == true

	-- Именно Frame, а не TextButton: кликом ловим всю строку целиком
	-- через card.InputBegan. Будь тут кнопка, клик по переключателю
	-- сработал бы дважды — и на кнопке, и всплытием на карточке.
	local track_ = new("Frame", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(46, 26),
		BorderSizePixel = 0,
		ZIndex = 2,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(13), stroke("StrokeSoft", 1, 0) })
	innerShadow(track_, 2, 0.38)

	-- лёгкое свечение вокруг включённого переключателя
	local glow = new("UIStroke", {
		Parent = track_,
		Thickness = 1.5,
		Transparency = 1,
		Theme = { Color = "Accent" },
	})

	local knob = new("Frame", {
		Parent = track_,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(20, 20),
		BorderSizePixel = 0,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Muted" },
	}, { corner(10) })
	topSheen(knob, 4, 4, 0.76)

	local obj = {}
	local cleanup

	function obj:Set(value, silent)
		if not card.Parent then return false end
		if type(value) ~= "boolean" then return false end
		state = value and true or false
		setThemeKey(track_, "BackgroundColor3", state and "Accent" or "Inset")
		setThemeKey(knob, "BackgroundColor3", state and "Text" or "Muted")
		tween(track_, EASE, { BackgroundColor3 = state and Theme.Accent or Theme.Inset })
		tween(glow, EASE, { Transparency = state and 0.82 or 1 })
		tween(knob, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
			BackgroundColor3 = state and Theme.Text or Theme.Muted,
		})
		if flag then Library.Flags[flag] = state end
		if not silent then safeCall(opts.Callback, state) end
		return true
	end

	function obj:Get() return state end
	function obj:Destroy()
		cleanup()
		if card.Parent then card:Destroy() end
	end
	obj.Card = card
	cleanup = bindCleanup(card, function()
		unregisterOption(flag, obj)
	end)

	card.InputBegan:Connect(function(input)
		if isPressStart(input) then obj:Set(not state) end
	end)

	obj:Set(state, true)
	registerOption(flag, obj, state, self.Window)
	index(self, asText(opts.Text, "Тоггл"), "переключатель", card)
	return obj
end

--────────────────────────────── Слайдер ──────────────────────────────
function Tab:Slider(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local flag = optionFlag(opts)
	local hasDesc = opts.Desc ~= nil and tostring(opts.Desc) ~= ""
	local sliderHeight = finiteNumber(opts.Height, hasDesc and 70 or 60)
	local card, slot, titleLbl = makeCard(self, opts, 0, sliderHeight)
	slot.Visible = false
	-- у слайдера низ строки занимает полоса, поэтому заголовок
	-- прижимаем к верху, а не центрируем по всей высоте
	titleLbl.Position = UDim2.fromOffset(22, 10)
	titleLbl.Size = UDim2.new(1, -142, 0, 16)

	local minV = finiteNumber(opts.Min, 0)
	local maxV = finiteNumber(opts.Max, 100)
	if minV > maxV then minV, maxV = maxV, minV end
	local decimals = math.clamp(math.floor(finiteNumber(opts.Decimals, 0) + 0.5), 0, 6)
	local suffix = asText(opts.Suffix, "")
	local value = math.clamp(finiteNumber(opts.Default, minV), minV, maxV)

	local valueLbl = label({
		Parent = card,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 10),
		Size = UDim2.fromOffset(100, 16),
		Font = FONT_SB,
		TextSize = 13,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Theme = { TextColor3 = "Accent" },
	})

	local bar = new("Frame", {
		Parent = card,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.44, 0, 1, -16),
		Size = UDim2.new(0.56, -22, 0, 5),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(3) })
	innerShadow(bar, 1, 0.35)
	topSheen(bar, 2, 6, 0.91)

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
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, { corner(7), stroke("Backdrop", 2, 0.55) })

	local obj = {}
	local dragFn
	local dragging = false
	local stopEnded
	local cleanup

	function obj:Set(v, silent)
		if not card.Parent then return false end
		local number = finiteNumber(v, nil)
		if number == nil then return false end
		value = math.clamp(round(number, decimals), minV, maxV)
		local alpha = (maxV - minV) == 0 and 0 or (value - minV) / (maxV - minV)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLbl.Text = tostring(value) .. suffix
		if flag then Library.Flags[flag] = value end
		if not silent then safeCall(opts.Callback, value) end
		return true
	end

	function obj:Get() return value end
	function obj:Destroy()
		cleanup()
		if card.Parent then card:Destroy() end
	end
	obj.Card = card
	cleanup = bindCleanup(card, function()
		if activeDrag == dragFn then activeDrag = nil end
		dragging = false
		if stopEnded then stopEnded() stopEnded = nil end
		unregisterOption(flag, obj)
	end)

	local function fromX(px)
		local alpha = clamp01((px - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X))
		obj:Set(minV + (maxV - minV) * alpha)
	end

	bar.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		tween(knob, EASE_FAST, { Size = UDim2.fromOffset(18, 18) })
		fromX(input.Position.X)
		dragFn = function(i) fromX(i.Position.X) end
		dragging = true
		activeDrag = dragFn
	end)
	stopEnded = onInput("Ended", function(input)
		if dragging and isPressStart(input) then
			dragging = false
			tween(knob, EASE_FAST, { Size = UDim2.fromOffset(14, 14) })
		end
	end)

	obj:Set(value, true)
	registerOption(flag, obj, value, self.Window)
	index(self, asText(opts.Text, "Слайдер"), "слайдер", card)
	return obj
end

--──────────────────────────── Выпадающий список ────────────────────────────
function Tab:Dropdown(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local flag = optionFlag(opts)
	local controlWidth = math.max(100, finiteNumber(opts.SlotWidth, 160))
	local card, slot = makeCard(self, opts, controlWidth)
	slot.Size = UDim2.fromOffset(controlWidth, 30)

	local suppliedOptions = opts.Options ~= nil and opts.Options or opts.Values
	local function uniqueList(source)
		local out = {}
		if type(source) ~= "table" then return out end
		for _, value in ipairs(source) do
			local validNumber = type(value) ~= "number"
				or (value == value and value ~= math.huge and value ~= -math.huge)
			local duplicate = false
			for _, existing in ipairs(out) do
				if existing == value then duplicate = true break end
			end
			if value ~= nil and validNumber and not duplicate then
				out[#out + 1] = value
			end
		end
		return out
	end
	local options  = uniqueList(suppliedOptions)
	local multi    = opts.Multi == true
	local selected = multi and {} or nil
	local placeholder = asText(opts.Placeholder, "Не выбрано")

	local button = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(controlWidth, 30),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(8), stroke("StrokeSoft", 1, 0) })
	innerShadow(button, 1, 0.4)
	topSheen(button, 2, 7, 0.92)
	local dropdownEdge = button:FindFirstChildOfClass("UIStroke")
	local leadingIconData = resolveIcon(opts.Icon)
	if leadingIconData then
		new("ImageLabel", {
			Parent = button,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(15, 15),
			BackgroundTransparency = 1,
			Image = leadingIconData.image,
			ImageRectSize = leadingIconData.rect or Vector2.zero,
			ImageRectOffset = leadingIconData.offset or Vector2.zero,
			ZIndex = 3,
			Theme = { ImageColor3 = "SubText" },
		})
	end

	local display = label({
		Parent = button,
		Position = UDim2.fromOffset(leadingIconData and 34 or 10, 0),
		Size = UDim2.new(1, leadingIconData and -54 or -30, 1, 0),
		Font = FONT,
		TextSize = 12,
		Text = placeholder,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "SubText" },
	})

	local arrow = icon(button, "chevron", "Muted", 14)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -10, 0.5, 0)

	--── меню в слое оверлея ──
	local menu = new("Frame", {
		Parent = Overlay,
		Size = UDim2.fromOffset(controlWidth, 0),
		Visible = false,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 610,
		Theme = { BackgroundColor3 = "Card" },
	}, { corner(9), stroke("Stroke", 1, 0.2) })
	surfaceNoise(menu, 610, 0.94)
	topSheen(menu, 614, 9, 0.86)
	local menuShadow = floatingShadow(Overlay, 609, 0.34)

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
			PlaceholderText = "Фильтр...",
			ClearTextOnFocus = false,
			ZIndex = 613,
			Theme = { BackgroundColor3 = "Inset", TextColor3 = "Text", PlaceholderColor3 = "Muted" },
		}, { corner(7), padding(0, 0, 8, 8) })
		innerShadow(search, 613, 0.42)
		scroll.Position = UDim2.fromOffset(0, 32)
		scroll.Size = UDim2.new(1, 0, 1, -32)
	end

	local obj = {}
	local isOpen = false
	local rows = {}
	local popupToken = 0
	local cleanup

	local function hasOption(value)
		for _, option in ipairs(options) do
			if option == value then return true end
		end
		return false
	end

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
				display.Text = placeholder
				setThemeKey(display, "TextColor3", "SubText")
				display.TextColor3 = Theme.SubText
			elseif #selected <= 2 then
				local parts = {}
				for i, item in ipairs(selected) do parts[i] = tostring(item) end
				display.Text = table.concat(parts, ", ")
				setThemeKey(display, "TextColor3", "Text")
				display.TextColor3 = Theme.Text
			else
				display.Text = "Выбрано: " .. #selected
				setThemeKey(display, "TextColor3", "Text")
				display.TextColor3 = Theme.Text
			end
		else
			display.Text = selected ~= nil and tostring(selected) or placeholder
			setThemeKey(display, "TextColor3", selected ~= nil and "Text" or "SubText")
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
		local width = math.max(1, button.AbsoluteSize.X)
		local x = math.clamp(button.AbsolutePosition.X, 10, math.max(10, vp.X - width - 10))
		local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y + 4
		if y + h > vp.Y - 10 then
			y = button.AbsolutePosition.Y - h - 4
		end
		y = math.clamp(y, 10, math.max(10, vp.Y - h - 10))
		menu.Position = overlayPosition(x, y)
		if menuShadow then
			menuShadow.Position = overlayPosition(x - 18, y - 18)
			menuShadow.Size = UDim2.fromOffset(width + 36, h + 36)
		end
	end

	local stopFollow
	local function close()
		if not isOpen then return end
		isOpen = false
		popupToken += 1
		local token = popupToken
		if openPopup == close then openPopup = nil end
		if stopFollow then stopFollow() stopFollow = nil end
		setThemeKey(dropdownEdge, "Color", "StrokeSoft")
		tween(dropdownEdge, EASE_FAST, { Color = Theme.StrokeSoft, Transparency = 0 })
		tween(arrow, EASE_FAST, { Rotation = 0 })
		tween(menu, EASE_FAST, { Size = UDim2.fromOffset(button.AbsoluteSize.X, 0) })
		task.delay(0.13, function()
			if token ~= popupToken or isOpen then return end
			if menu.Parent then menu.Visible = false end
			if menuShadow and menuShadow.Parent then menuShadow.Visible = false end
		end)
	end

	local function open()
		closePopup()
		isOpen = true
		popupToken += 1
		openPopup = close
		setThemeKey(dropdownEdge, "Color", "Accent")
		tween(dropdownEdge, EASE_FAST, { Color = Theme.Accent, Transparency = 0.35 })
		menu.Visible = true
		if menuShadow then menuShadow.Visible = true end
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
				Theme = { BackgroundColor3 = "CardHover" },
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
			setThemeKey(r.text, "TextColor3", on and "Text" or "SubText")
			tween(r.text, EASE_FAST, { TextColor3 = on and Theme.Text or Theme.SubText })
		end
	end

	local function applyFilter()
		local query = search and normalizeSearch(search.Text) or ""
		for _, row in ipairs(rows) do
			row.frame.Visible = query == ""
				or normalizeSearch(row.value):find(query, 1, true) ~= nil
		end
	end

	function obj:Set(value, silent)
		if not card.Parent then return false end
		if multi then
			local nextSelected = {}
			if type(value) == "table" then
				for _, item in ipairs(value) do
					local duplicate = false
					for _, existing in ipairs(nextSelected) do
						if existing == item then duplicate = true break end
					end
					if item ~= nil and not hasOption(item) then return false end
					if item ~= nil and not duplicate then
						nextSelected[#nextSelected + 1] = item
					end
				end
			elseif value ~= nil then
				if not hasOption(value) then return false end
				nextSelected[1] = value
			end
			selected = nextSelected
		else
			if value ~= nil and hasOption(value) then
				selected = value
			elseif value ~= nil then
				return false
			else
				selected = nil
			end
		end
		refreshDisplay()
		paintRows()
		if flag then
			Library.Flags[flag] = multi and table.clone(selected) or selected
		end
		if not silent then safeCall(opts.Callback, multi and table.clone(selected) or selected) end
		return true
	end

	function obj:Get() return multi and table.clone(selected) or selected end

	-- Главная боль всех библиотек: обновить список на лету.
	function obj:Refresh(newOptions, keepSelection)
		if not card.Parent then return false end
		options = uniqueList(newOptions)
		buildRows()
		applyFilter()
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
		return true
	end

	function obj:Destroy()
		cleanup()
		if card.Parent then card:Destroy() end
	end
	obj.Card = card
	cleanup = bindCleanup(card, function()
		close()
		popupToken += 1
		unregisterOption(flag, obj)
		if menu.Parent then menu:Destroy() end
		if menuShadow and menuShadow.Parent then menuShadow:Destroy() end
	end)

	if search then
		search:GetPropertyChangedSignal("Text"):Connect(function()
			applyFilter()
			tween(menu, EASE_FAST, { Size = UDim2.fromOffset(button.AbsoluteSize.X, rowHeight()) })
		end)
	end

	button.MouseButton1Click:Connect(function()
		if isOpen then close() else open() end
	end)
	button.MouseEnter:Connect(function()
		setThemeKey(dropdownEdge, "Color", "Accent")
		tween(dropdownEdge, EASE_FAST, { Color = Theme.Accent, Transparency = 0.45 })
	end)
	button.MouseLeave:Connect(function()
		if isOpen then return end
		setThemeKey(dropdownEdge, "Color", "StrokeSoft")
		tween(dropdownEdge, EASE_FAST, { Color = Theme.StrokeSoft, Transparency = 0 })
	end)
	-- клик по самому меню не должен его закрывать
	menu.InputBegan:Connect(function(input)
		if isPressStart(input) then guardPopup() end
	end)

	buildRows()
	local default = opts.Default
	if default == nil and multi then default = {} end
	obj:Set(default, true)
	registerOption(flag, obj, multi and table.clone(selected) or selected, self.Window)
	index(self, asText(opts.Text, "Список"), "список", card)
	return obj
end

--──────────────────────────── Поле ввода ────────────────────────────
function Tab:Input(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local flag = optionFlag(opts)
	local controlWidth = math.max(100, finiteNumber(opts.SlotWidth, 170))
	local card, slot = makeCard(self, opts, controlWidth)
	slot.Size = UDim2.fromOffset(controlWidth, 30)
	local function normalizeValue(value)
		local text = asText(value, "")
		if opts.Numeric then
			local number = finiteNumber(text, nil)
			return number and tostring(number) or ""
		end
		return text
	end

	local box = new("Frame", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(controlWidth, 30),
		BorderSizePixel = 0,
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(8), stroke("StrokeSoft", 1, 0) })
	innerShadow(box, 1, 0.4)
	topSheen(box, 2, 7, 0.92)

	local input = new("TextBox", {
		Parent = box,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		Text = normalizeValue(opts.Default),
		PlaceholderText = asText(opts.Placeholder, "Введите..."),
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "Muted" },
	})

	local border = box:FindFirstChildOfClass("UIStroke")
	input.Focused:Connect(function()
		setThemeKey(border, "Color", "Accent")
		tween(border, EASE_FAST, { Color = Theme.Accent, Transparency = 0 })
	end)
	input.FocusLost:Connect(function(enter)
		setThemeKey(border, "Color", "StrokeSoft")
		tween(border, EASE_FAST, { Color = Theme.StrokeSoft, Transparency = 0 })
		if opts.Numeric then
			input.Text = normalizeValue(input.Text)
		end
		if flag then Library.Flags[flag] = input.Text end
		if enter or not opts.OnEnter then safeCall(opts.Callback, input.Text, enter) end
	end)

	local obj = {}
	local cleanup
	function obj:Set(v, silent)
		if not card.Parent then return false end
		if opts.Numeric and v ~= nil and finiteNumber(asText(v, ""), nil) == nil then
			return false
		end
		input.Text = normalizeValue(v)
		if flag then Library.Flags[flag] = input.Text end
		if not silent then safeCall(opts.Callback, input.Text, false) end
		return true
	end
	function obj:Get() return input.Text end
	function obj:Destroy()
		cleanup()
		if card.Parent then card:Destroy() end
	end
	obj.Card = card
	cleanup = bindCleanup(card, function()
		unregisterOption(flag, obj)
	end)

	registerOption(flag, obj, input.Text, self.Window)
	index(self, asText(opts.Text, "Поле"), "поле ввода", card)
	return obj
end

--────────────────────────────── Кейбинд ──────────────────────────────
function Tab:Keybind(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local flag = optionFlag(opts)
	local controlWidth = math.max(88, finiteNumber(opts.SlotWidth, 110))
	local card, slot = makeCard(self, opts, controlWidth)
	slot.Size = UDim2.fromOffset(controlWidth, 30)
	local modifiers = type(opts.Modifiers) == "table" and opts.Modifiers or {}
	local function modifierMatchesKey(modifier, keyCode)
		if typeof(modifier) == "EnumItem" then return modifier == keyCode end
		local name = tostring(modifier):lower()
		if name == "ctrl" or name == "control" then
			return keyCode == Enum.KeyCode.LeftControl or keyCode == Enum.KeyCode.RightControl
		elseif name == "shift" then
			return keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift
		elseif name == "alt" then
			return keyCode == Enum.KeyCode.LeftAlt or keyCode == Enum.KeyCode.RightAlt
		end
		return false
	end
	local function isConfiguredModifier(keyCode)
		for _, modifier in ipairs(modifiers) do
			if modifierMatchesKey(modifier, keyCode) then return true end
		end
		return false
	end
	local function keyText(key)
		if not key then return "Нет" end
		local parts = {}
		for _, modifier in ipairs(modifiers) do parts[#parts + 1] = tostring(modifier) end
		parts[#parts + 1] = key.Name
		return table.concat(parts, "  +  ")
	end
	local function modifiersHeld()
		for _, modifier in ipairs(modifiers) do
			local name = tostring(modifier):lower()
			local held
			if name == "ctrl" or name == "control" then
				held = UserInput:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInput:IsKeyDown(Enum.KeyCode.RightControl)
			elseif name == "shift" then
				held = UserInput:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInput:IsKeyDown(Enum.KeyCode.RightShift)
			elseif name == "alt" then
				held = UserInput:IsKeyDown(Enum.KeyCode.LeftAlt)
					or UserInput:IsKeyDown(Enum.KeyCode.RightAlt)
			elseif typeof(modifier) == "EnumItem" then
				held = UserInput:IsKeyDown(modifier)
			else
				held = false
			end
			if not held then return false end
		end
		return true
	end

	local btn = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(controlWidth, 30),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_M,
		TextSize = 12,
		Text = "Нет",
		Theme = { BackgroundColor3 = "Inset", TextColor3 = "SubText" },
	}, { corner(8), stroke("StrokeSoft", 1, 0) })
	local keyEdge = btn:FindFirstChildOfClass("UIStroke")
	local comboMode = #modifiers > 0
	local keyCapLabel
	if comboMode then
		btn.BackgroundTransparency = 1
		keyEdge.Transparency = 1
		local comboRow = new("Frame", {
			Parent = btn,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			new("UIListLayout", {
				Padding = UDim.new(0, 6),
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local order = 0
		local function plus()
			order += 1
			label({
				Parent = comboRow,
				Size = UDim2.fromOffset(8, 30),
				Font = FONT_M,
				TextSize = 11,
				Text = "+",
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = order,
				ZIndex = 4,
				Theme = { TextColor3 = "Muted" },
			})
		end
		local function keycap(text, width)
			order += 1
			local cap = new("Frame", {
				Parent = comboRow,
				Size = UDim2.fromOffset(width, 30),
				LayoutOrder = order,
				ZIndex = 4,
				Theme = { BackgroundColor3 = "Inset" },
			}, { corner(6), stroke("StrokeSoft", 1, 0) })
			return label({
				Parent = cap,
				Size = UDim2.fromScale(1, 1),
				Font = FONT_M,
				TextSize = 11,
				Text = text,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 5,
			})
		end
		for i, modifier in ipairs(modifiers) do
			if i > 1 then plus() end
			local text = typeof(modifier) == "EnumItem" and modifier.Name or tostring(modifier)
			keycap(text, math.max(38, #text * 7 + 16))
		end
		plus()
		keyCapLabel = keycap("", 34)
		order += 1
		local editCap = new("Frame", {
			Parent = comboRow,
			Size = UDim2.fromOffset(30, 30),
			LayoutOrder = order,
			ZIndex = 4,
			Theme = { BackgroundColor3 = "Inset" },
		}, { corner(6), stroke("StrokeSoft", 1, 0) })
		local editData = resolveIcon("pencil")
		if editData then
			new("ImageLabel", {
				Parent = editCap,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Image = editData.image,
				ImageRectSize = editData.rect or Vector2.zero,
				ImageRectOffset = editData.offset or Vector2.zero,
				ZIndex = 5,
				Theme = { ImageColor3 = "Muted" },
			})
		end
	else
		innerShadow(btn, 1, 0.4)
		topSheen(btn, 2, 7, 0.92)
	end

	local entry = { key = nil, fire = function() end }
	table.insert(keybinds, entry)

	local obj = {}
	local captureFn
	local cleanup

	function obj:Set(key, silent)
		if not card.Parent then return false end
		local supplied = key
		if typeof(key) == "EnumItem" then
			local enumType = tostring(key.EnumType)
			local keyCode = enumType == "Enum.KeyCode" or enumType == "KeyCode"
			local inputType = enumType == "Enum.UserInputType" or enumType == "UserInputType"
			if keyCode and key == Enum.KeyCode.Unknown then
				key = nil
			elseif inputType and key ~= Enum.UserInputType.MouseButton1
				and key ~= Enum.UserInputType.MouseButton2
				and key ~= Enum.UserInputType.MouseButton3 then
				key = nil
			elseif not keyCode and not inputType then
				key = nil
			end
		else
			key = nil
		end
		if supplied ~= nil and key == nil then return false end
		entry.key = key
		if comboMode then
			keyCapLabel.Text = key and key.Name or "Нет"
			btn.Text = ""
		else
			btn.Text = keyText(key)
		end
		setThemeKey(btn, "TextColor3", key and "Text" or "SubText")
		btn.TextColor3 = key and Theme.Text or Theme.SubText
		if not comboMode then
			setThemeKey(keyEdge, "Color", "StrokeSoft")
			tween(keyEdge, EASE_FAST, { Color = Theme.StrokeSoft, Transparency = 0 })
		end
		if flag then Library.Flags[flag] = key end
		if not silent then safeCall(opts.Callback, key) end
		return true
	end

	function obj:Get() return entry.key end
	function obj:Destroy()
		cleanup()
		if card.Parent then card:Destroy() end
	end
	obj.Card = card
	cleanup = bindCleanup(card, function()
		if captureTarget == captureFn then captureTarget = nil end
		for i, e in ipairs(keybinds) do
			if e == entry then table.remove(keybinds, i) break end
		end
		unregisterOption(flag, obj)
	end)

	entry.fire = function()
		if not modifiersHeld() then return end
		if opts.OnPress then safeCall(opts.OnPress, entry.key) end
		if opts.Mode == "toggle" and opts.Toggle ~= nil then
			local targetFlag = tostring(opts.Toggle)
			local target = self.Window and self.Window._options[targetFlag] or Library.Options[targetFlag]
			if target and target.Set then target:Set(not target:Get()) end
		end
	end

	btn.MouseButton1Click:Connect(function()
		if comboMode then keyCapLabel.Text = "..." else btn.Text = "..." end
		setThemeKey(btn, "TextColor3", "Accent")
		btn.TextColor3 = Theme.Accent
		if not comboMode then
			setThemeKey(keyEdge, "Color", "Accent")
			tween(keyEdge, EASE_FAST, { Color = Theme.Accent, Transparency = 0.28 })
		end
		captureFn = function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				obj:Set(nil)
			elseif input.UserInputType == Enum.UserInputType.Keyboard then
				if comboMode and isConfiguredModifier(input.KeyCode) then
					captureTarget = captureFn
				else
					obj:Set(input.KeyCode)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3 then
				obj:Set(input.UserInputType)
			else
				obj:Set(entry.key)
			end
		end
		captureTarget = captureFn
	end)

	obj:Set(opts.Default, true)
	registerOption(flag, obj, entry.key, self.Window)
	index(self, asText(opts.Text, "Клавиша"), "клавиша", card)
	return obj
end

--──────────────────────────── Выбор цвета ────────────────────────────
function Tab:Colorpicker(opts)
	if not tabAlive(self) then return nil end
	opts = type(opts) == "table" and opts or {}
	local flag = optionFlag(opts)
	local controlWidth = math.max(120, finiteNumber(opts.SlotWidth, 176))
	local card, slot = makeCard(self, opts, controlWidth)
	slot.Size = UDim2.fromOffset(controlWidth, 36)

	local color = typeof(opts.Default) == "Color3" and opts.Default or Color3.fromRGB(122, 140, 255)
	local h, s, v = color:ToHSV()

	local swatchBtn = new("TextButton", {
		Parent = slot,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(controlWidth, 36),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Theme = { BackgroundColor3 = "Inset" },
	}, { corner(7), stroke("Stroke", 1, 0.25) })
	innerShadow(swatchBtn, 1, 0.4)
	topSheen(swatchBtn, 2, 8, 0.92)
	local swatch = new("Frame", {
		Parent = swatchBtn,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(26, 22),
		BackgroundColor3 = color,
		ZIndex = 3,
	}, { corner(5) })
	new("Frame", {
		Parent = swatch,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
		ZIndex = 2,
	}, {
		corner(7),
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(0.5, 0.9),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local hexDisplay = label({
		Parent = swatchBtn,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -78, 1, 0),
		Font = FONT_M,
		TextSize = 12,
		Text = "",
		ZIndex = 3,
	})
	local swatchArrow = icon(swatchBtn, "chevron", "Muted", 14, 3)
	swatchArrow.AnchorPoint = Vector2.new(1, 0.5)
	swatchArrow.Position = UDim2.new(1, -12, 0.5, 0)
	local swatchEdge = swatchBtn:FindFirstChildOfClass("UIStroke")

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
	surfaceNoise(pop, 620, 0.94)
	topSheen(pop, 626, 10, 0.86)
	local popShadow = floatingShadow(Overlay, 619, 0.32)

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
	innerShadow(hexBox, 621, 0.42)

	local obj = {}
	local isOpen = false
	local popupToken = 0
	local svDrag
	local hueDrag
	local cleanup

	function obj:Set(c, silent)
		if not card.Parent then return false end
		if typeof(c) ~= "Color3" then return false end
		color = c
		h, s, v = color:ToHSV()
		swatch.BackgroundColor3 = color
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
		hexBox.Text = string.format("#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5))
		hexDisplay.Text = hexBox.Text
		if flag then Library.Flags[flag] = color end
		if not silent then safeCall(opts.Callback, color) end
		return true
	end

	function obj:Get() return color end

	local stopFollow
	local function close()
		if not isOpen then return end
		isOpen = false
		popupToken += 1
		local token = popupToken
		if openPopup == close then openPopup = nil end
		if stopFollow then stopFollow() stopFollow = nil end
		setThemeKey(swatchEdge, "Color", "Stroke")
		tween(swatchEdge, EASE_FAST, { Color = Theme.Stroke, Transparency = 0.25 })
		tween(pop, EASE_FAST, { Size = UDim2.fromOffset(228, 0) })
		task.delay(0.13, function()
			if token ~= popupToken or isOpen then return end
			if pop.Parent then pop.Visible = false end
			if popShadow and popShadow.Parent then popShadow.Visible = false end
		end)
	end

	local function place()
		local vp = viewport()
		local x = swatchBtn.AbsolutePosition.X + swatchBtn.AbsoluteSize.X - 228
		local y = swatchBtn.AbsolutePosition.Y + swatchBtn.AbsoluteSize.Y + 6
		if y + 182 > vp.Y - 10 then y = swatchBtn.AbsolutePosition.Y - 188 end
		x = math.clamp(x, 10, math.max(10, vp.X - 238))
		y = math.clamp(y, 10, math.max(10, vp.Y - 192))
		pop.Position = overlayPosition(x, y)
		if popShadow then
			popShadow.Position = overlayPosition(x - 18, y - 18)
			popShadow.Size = UDim2.fromOffset(264, 218)
		end
	end

	swatchBtn.MouseButton1Click:Connect(function()
		if isOpen then close() return end
		closePopup()
		isOpen = true
		popupToken += 1
		openPopup = close
		setThemeKey(swatchEdge, "Color", "Accent")
		tween(swatchEdge, EASE_FAST, { Color = Theme.Accent, Transparency = 0.1 })
		pop.Visible = true
		if popShadow then popShadow.Visible = true end
		pop.Size = UDim2.fromOffset(228, 0)
		place()
		tween(pop, EASE, { Size = UDim2.fromOffset(228, 182) })
		stopFollow = onRender(place)
	end)
	swatchBtn.MouseEnter:Connect(function()
		setThemeKey(swatchEdge, "Color", "Accent")
		tween(swatchEdge, EASE_FAST, { Color = Theme.Accent, Transparency = 0.1 })
	end)
	swatchBtn.MouseLeave:Connect(function()
		if isOpen then return end
		setThemeKey(swatchEdge, "Color", "Stroke")
		tween(swatchEdge, EASE_FAST, { Color = Theme.Stroke, Transparency = 0.25 })
	end)

	pop.InputBegan:Connect(function(input)
		if isPressStart(input) then guardPopup() end
	end)

	sv.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		svDrag = function(i)
			local ns = clamp01((i.Position.X - sv.AbsolutePosition.X) / math.max(1, sv.AbsoluteSize.X))
			local nv = 1 - clamp01((i.Position.Y - sv.AbsolutePosition.Y) / math.max(1, sv.AbsoluteSize.Y))
			obj:Set(Color3.fromHSV(h, ns, nv))
		end
		svDrag(input)
		activeDrag = svDrag
	end)

	hue.InputBegan:Connect(function(input)
		if not isPressStart(input) then return end
		hueDrag = function(i)
			local nh = clamp01((i.Position.Y - hue.AbsolutePosition.Y) / math.max(1, hue.AbsoluteSize.Y))
			obj:Set(Color3.fromHSV(nh, s, v))
		end
		hueDrag(input)
		activeDrag = hueDrag
	end)

	hexBox.FocusLost:Connect(function()
		local hex = hexBox.Text:gsub("#", ""):gsub("%s+", "")
		if #hex == 6 and tonumber(hex, 16) then
			obj:Set(Color3.fromRGB(
				tonumber(hex:sub(1, 2), 16),
				tonumber(hex:sub(3, 4), 16),
				tonumber(hex:sub(5, 6), 16)))
		else
			obj:Set(color, true)
		end
	end)

	function obj:Destroy()
		cleanup()
		if card.Parent then card:Destroy() end
	end
	obj.Card = card
	cleanup = bindCleanup(card, function()
		close()
		popupToken += 1
		if activeDrag == svDrag or activeDrag == hueDrag then activeDrag = nil end
		unregisterOption(flag, obj)
		if pop.Parent then pop:Destroy() end
		if popShadow and popShadow.Parent then popShadow:Destroy() end
	end)

	obj:Set(color, true)
	registerOption(flag, obj, color, self.Window)
	index(self, asText(opts.Text, "Цвет"), "цвет", card)
	return obj
end

--═══════════════════════════════════════════════════════════════════════
--  13. КОНФИГИ
--  Сериализуем Color3 и EnumItem — JSON их сам не умеет.
--═══════════════════════════════════════════════════════════════════════

local function encodeValue(v)
	if v == nil then
		return { __t = "Nil" }
	elseif typeof(v) == "Color3" then
		return { __t = "Color3", r = v.R, g = v.G, b = v.B }
	elseif typeof(v) == "EnumItem" then
		-- У объекта Enum нет свойства .Name (обращение к нему кидает ошибку),
		-- поэтому имя типа достаём из tostring: "Enum.KeyCode" либо "KeyCode".
		local enumName = (tostring(v.EnumType):gsub("^Enum%.", ""))
		return { __t = "Enum", e = enumName, n = v.Name }
	elseif type(v) == "table" then
		local out = {}
		for i, item in ipairs(v) do out[i] = encodeValue(item) end
		return out
	end
	return v
end

local function decodeValue(v)
	if type(v) == "table" then
		if v.__t == "Nil" then return nil end
		if v.__t == "Color3" then return Color3.new(v.r, v.g, v.b) end
		if v.__t == "Enum" then
			local ok, item = pcall(function() return Enum[v.e][v.n] end)
			return ok and item or nil
		end
		if v.__t ~= nil then error("unknown encoded type") end
		local out = {}
		for i, item in ipairs(v) do out[i] = decodeValue(item) end
		return out
	end
	return v
end

local function safeFilePart(value, fallback)
	local text = asText(value, fallback or "default")
	text = text:gsub("[%z\1-\31<>:\"/\\|%?%*]", "_")
	repeat
		local cleaned, count = text:gsub("%.%.", "_")
		text = cleaned
	until count == 0
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	text = text:gsub("^[%. ]+", ""):gsub("[%. ]+$", "")
	if text == "" then text = fallback or "default" end
	local stem = text:match("^([^%.]+)") or text
	local upperStem = stem:upper()
	if upperStem == "CON" or upperStem == "PRN" or upperStem == "AUX" or upperStem == "NUL"
		or upperStem:match("^COM[1-9]$") or upperStem:match("^LPT[1-9]$") then
		text = "_" .. text
	end
	local valid, cut = pcall(utf8.offset, text, 65)
	if valid and cut then
		text = text:sub(1, cut - 1)
	elseif not valid and #text > 64 then
		text = text:sub(1, 64)
	end
	return text
end

function Window:ConfigFolder()
	return "AuroraUI/" .. safeFilePart(self.ConfigName or game.PlaceId, tostring(game.PlaceId))
end

local function ensureFolder(path)
	if not FS.isdir or not FS.mkdir then return end
	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
		local sub = table.concat(parts, "/")
		local checked, exists = pcall(FS.isdir, sub)
		if not checked or not exists then pcall(FS.mkdir, sub) end
	end
end

function Window:SaveConfig(name)
	if not Library.Alive then return false end
	if not HAS_FS then
		Library:Notify{ Title = "Конфиги недоступны", Content = "Исполнитель не даёт доступ к файлам.", Type = "warn" }
		return false
	end
	name = safeFilePart(name, "default")
	local folder = self:ConfigFolder()
	ensureFolder(folder)

	local ok, encoded = pcall(function()
		local data = {}
		for _, flag in ipairs(self._optionOrder) do
			local element = self._options[flag]
			if element and element.Get then
				local got, value = pcall(element.Get, element)
				if not got then error("failed to read option: " .. tostring(flag)) end
				data[tostring(flag)] = encodeValue(value)
			end
		end
		return HttpService:JSONEncode(data)
	end)
	if not ok then return false end
	local wrote, result = pcall(FS.write, folder .. "/" .. name .. ".json", encoded)
	local written = wrote and result ~= false
	if written then
		Library:Notify{ Title = "Сохранено", Content = "Конфиг «" .. name .. "»", Type = "success" }
	end
	return written
end

function Window:LoadConfig(name)
	if not Library.Alive then return false end
	if not HAS_FS then return false end
	name = safeFilePart(name, "default")
	local path = self:ConfigFolder() .. "/" .. name .. ".json"
	local checked, exists = pcall(FS.isfile, path)
	if not checked or not exists then return false end

	local ok, raw = pcall(FS.read, path)
	if not ok or type(raw) ~= "string" or #raw > 1024 * 1024 then return false end
	local parsed, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not parsed or type(data) ~= "table" then return false end

	local failed = 0
	for _, key in ipairs(self._optionOrder) do
		local value = data[key]
		if value ~= nil then
			local decoded, result = pcall(decodeValue, value)
			local taggedNil = type(value) == "table" and value.__t == "Nil"
			local invalidTagged = type(value) == "table" and value.__t ~= nil and not taggedNil and result == nil
			if decoded and not invalidTagged then
				local element = self._options[key]
				if element and element.Set then
					local called, applied = pcall(element.Set, element, result)
					if not called or applied == false then failed += 1 end
				end
			else
				failed += 1
			end
		end
	end
	if failed > 0 then
		Library:Notify{
			Title = "Конфиг загружен частично",
			Content = "Не удалось применить значений: " .. failed,
			Type = "warn",
		}
		return false
	end
	Library:Notify{ Title = "Загружено", Content = "Конфиг «" .. name .. "»", Type = "success" }
	return true
end

function Window:ListConfigs()
	local out = {}
	local seen = {}
	if not Library.Alive then return out end
	if not HAS_FS or not FS.list then return out end
	local folder = self:ConfigFolder()
	if FS.isdir then
		local checked, exists = pcall(FS.isdir, folder)
		if not checked or not exists then return out end
	end
	local ok, files = pcall(FS.list, folder)
	if not ok or type(files) ~= "table" then return out end
	for _, path in ipairs(files) do
		local name = tostring(path):match("([^/\\]+)%.json$")
		if name and not seen[name] then
			seen[name] = true
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function Window:DeleteConfig(name)
	if not Library.Alive then return false end
	if not HAS_FS or not FS.delete then return false end
	name = safeFilePart(name, "default")
	local path = self:ConfigFolder() .. "/" .. name .. ".json"
	local checked, exists = pcall(FS.isfile, path)
	if not checked or not exists then return false end
	local ok, result = pcall(FS.delete, path)
	return ok and result ~= false
end

-- Готовая вкладка настроек: конфиги, темы, клавиша, выгрузка.
function Window:SettingsTab(opts)
	if not Library.Alive then return nil end
	opts = type(opts) == "table" and opts or {}
	local tab = self:Tab{
		Name = opts.Name or "Настройки",
		Icon = opts.Icon or "settings",
		Desc = "Тема, конфигурации и управление интерфейсом",
		Columns = opts.Columns or 2,
		Pinned = opts.Pinned ~= false,
	}
	if not tab then return nil end

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
		Callback = function(key)
			self.ToggleKey = key
		end,
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

function Library:SetAnimations(state)
	if not self.Alive then return false end
	AnimationsEnabled = state ~= false
	return true
end

function Library:SetAccent(color)
	if not self.Alive or typeof(color) ~= "Color3" then return false end
	Theme.Accent = color
	Theme.Accent2 = color:Lerp(Color3.new(1, 1, 1), 0.22)

	for i = #ThemeRegistry, 1, -1 do
		local entry = ThemeRegistry[i]
		if not entry.inst or not entry.inst.Parent then
			table.remove(ThemeRegistry, i)
		elseif entry.key == "Accent" or entry.key == "Accent2" then
			tween(entry.inst, EASE, { [entry.prop] = Theme[entry.key] })
		end
	end
	for i = #GradientRegistry, 1, -1 do
		local entry = GradientRegistry[i]
		if not entry.inst or not entry.inst.Parent then
			table.remove(GradientRegistry, i)
		elseif entry.a == "Accent" or entry.a == "Accent2"
			or entry.b == "Accent" or entry.b == "Accent2" then
			local ok = pcall(function()
				entry.inst.Color = ColorSequence.new(Theme[entry.a], Theme[entry.b])
			end)
			if not ok then table.remove(GradientRegistry, i) end
		end
	end
	return true
end

function Library:SetTheme(name)
	if not self.Alive then return false end
	local preset = THEMES[name]
	if not preset then return false end
	self.ThemeName = name
	for k, v in next, preset do Theme[k] = v end

	for i = #ThemeRegistry, 1, -1 do
		local entry = ThemeRegistry[i]
		local color = Theme[entry.key]
		if not entry.inst or not entry.inst.Parent or not color then
			table.remove(ThemeRegistry, i)
		else
			tween(entry.inst, EASE, { [entry.prop] = color })
		end
	end

	for i = #GradientRegistry, 1, -1 do
		local entry = GradientRegistry[i]
		local colorA, colorB = Theme[entry.a], Theme[entry.b]
		if not entry.inst or not entry.inst.Parent or not colorA or not colorB then
			table.remove(GradientRegistry, i)
		else
			local ok = pcall(function()
				entry.inst.Color = ColorSequence.new(colorA, colorB)
			end)
			if not ok then table.remove(GradientRegistry, i) end
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
	closePopup()
	self.Alive = false
	activeDrag = nil
	captureTarget = nil
	popupGuard = false

	for _, conn in ipairs(self._conns) do pcall(function() conn:Disconnect() end) end

	table.clear(self._conns)
	table.clear(self._render)
	table.clear(Dispatch.Began)
	table.clear(Dispatch.Changed)
	table.clear(Dispatch.Ended)
	table.clear(keybinds)
	table.clear(ThemeRegistry)
	table.clear(GradientRegistry)
	table.clear(ThemeWatch)
	table.clear(self.SearchIndex)
	table.clear(self.Options)
	table.clear(self.Flags)

	if Blur then pcall(function() Blur:Destroy() end) end
	if Gui then
		pcall(function()
			for _, w in ipairs(self.Windows) do
				tween(w.Frame, EASE_FAST, { Size = UDim2.fromOffset(w.Frame.AbsoluteSize.X, 0) })
			end
		end)
		task.delay(0.2, function() pcall(function() Gui:Destroy() end) end)
	end
	table.clear(self.Windows)

	if ENV.AuroraUI == self then ENV.AuroraUI = nil end
end

Library.Unload = Library.Destroy

ENV.AuroraUI = Library
return Library
