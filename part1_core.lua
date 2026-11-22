--[[
	Dar3x Client | part1_core.lua  (v0.3.0)
	Ядро: тема, стеклянное меню, змейка по контуру, вкладки, док, переключатели,
	iOS-полоска для открытия/закрытия меню (тап или свайп).

	API для остальных частей (part2, part3, ...):
		local D = _G.Dar3xClient
		local tab = D.AddTab("Visuals")
		tab:AddToggle("Rain", false, function(on) end)
		tab:AddButton("Do something", function() end)
		D.Flags["Visuals.Rain"]  -- текущее состояние
	Старт меню делает загрузчик: _G.Dar3xClient.Start()
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

-- перезапуск: убираем старую версию
if _G.Dar3xClient and _G.Dar3xClient.Destroy then
	pcall(_G.Dar3xClient.Destroy)
end

local Dar3x = {
	Version = "0.3.0",
	Flags = {},
	Tabs = {},
	Connections = {},
	IsOpen = false,
}
_G.Dar3xClient = Dar3x
_G.Dar4xClient = Dar3x -- алиас для старого загрузчика

----------------------------------------------------------------
-- Иконки (ID картинок) и тема
----------------------------------------------------------------
local ICONS = {
	Logo = 77813700068224,
	Modules = 130250475069907,
	Settings = 109092703857039,
}

local Theme = {
	Accent = Color3.fromRGB(124, 104, 238),
	AccentSoft = Color3.fromRGB(176, 156, 255),
	Panel = Color3.fromRGB(10, 9, 18),
	Row = Color3.fromRGB(30, 27, 48),
	Text = Color3.fromRGB(238, 236, 250),
	Muted = Color3.fromRGB(135, 131, 165),
	Off = Color3.fromRGB(52, 48, 74),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}
Dar3x.Theme = Theme

local WIN_W, WIN_H = 580, 340
local WIN_RADIUS = 28
local PAGE_SLIDE = 26
local DRAG_DIST = 170 -- сколько пикселей свайпа = полное открытие

local Quint = Enum.EasingStyle.Quint
local Back = Enum.EasingStyle.Back

----------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------
local function New(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function Corner(r)
	return New("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function Round()
	return New("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function Tween(inst, t, props, style, dir)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Dar3x.Connections, c)
	return c
end

local function GetGuiParent()
	if gethui then
		local ok, ui = pcall(gethui)
		if ok and ui then
			return ui
		end
	end
	local ok = pcall(function()
		return CoreGui.Name
	end)
	if ok then
		return CoreGui
	end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function ImgId(id)
	return "rbxassetid://" .. tostring(id)
end

-- круглая иконка с запасным текстом, если картинка не загрузилась
local function Icon(parent, id, size, fallback)
	local img = New("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		Image = ImgId(id),
		ImageColor3 = Theme.Muted,
		ScaleType = Enum.ScaleType.Crop,
		Parent = parent,
	}, { Round() })
	local fb = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundTransparency = 1,
		Text = fallback,
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Visible = false,
		Parent = parent,
	})
	task.delay(5, function()
		if img.Parent and not img.IsLoaded then
			fb.Visible = true
		end
	end)
	return img
end

-- фиолетовая змейка по контуру
local function SnakeBorder(frame, thickness, duration)
	local stroke = New("UIStroke", {
		Thickness = thickness or 2,
		Color = Color3.new(1, 1, 1),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	local grad = New("UIGradient", {
		Color = ColorSequence.new(Theme.AccentSoft),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(0.8, 0.2),
			NumberSequenceKeypoint.new(0.95, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = stroke,
	})
	TweenService:Create(
		grad,
		TweenInfo.new(duration or 3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Rotation = 360 }
	):Play()
	return stroke
end

local function MakeDraggable(handle, target)
	local dragging, dragStart, startPos = false, nil, nil
	Connect(handle.InputBegan, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local d = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + d.X,
				startPos.Y.Scale,
				startPos.Y.Offset + d.Y
			)
		end
	end)
end

----------------------------------------------------------------
-- Плавное появление/скрытие страниц (CanvasGroup)
----------------------------------------------------------------
local Tok = setmetatable({}, { __mode = "k" })

local function ShowHolder(h, dir, base)
	base = base or UDim2.new()
	Tok[h] = (Tok[h] or 0) + 1
	h.Visible = true
	h.GroupTransparency = 1
	h.Position = base + UDim2.fromOffset(dir * PAGE_SLIDE, 0)
	Tween(h, 0.45, { GroupTransparency = 0, Position = base }, Quint)
end

local function HideHolder(h, dir, base)
	base = base or UDim2.new()
	Tok[h] = (Tok[h] or 0) + 1
	local tok = Tok[h]
	Tween(h, 0.22, {
		GroupTransparency = 1,
		Position = base + UDim2.fromOffset(-dir * PAGE_SLIDE, 0),
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.24, function()
		if Tok[h] == tok then
			h.Visible = false
		end
	end)
end

----------------------------------------------------------------
-- GUI: корень, окно, шапка, контент, док
----------------------------------------------------------------
local Gui = New("ScreenGui", {
	Name = "Dar3xClient",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
})
if syn and syn.protect_gui then
	pcall(syn.protect_gui, Gui)
end
Gui.Parent = GetGuiParent()

local Root = New("Frame", {
	Name = "Root",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = Gui,
})

local Scaler = New("Frame", {
	Name = "Scaler",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	BackgroundTransparency = 1,
	Parent = Root,
})
local UIScale = New("UIScale", { Parent = Scaler })

local function Fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local s = math.clamp(math.min(vp.X * 0.92 / WIN_W, vp.Y * 0.8 / WIN_H), 0.5, 1)
	UIScale.Scale = s
	Root.Size = UDim2.fromOffset(WIN_W * s, WIN_H * s)
end
Fit()
if workspace.CurrentCamera then
	Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), Fit)
end

-- Shell анимируется при открытии, внутри: окно (CanvasGroup) и контур со змейкой
local Shell = New("Frame", {
	Name = "Shell",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = Scaler,
})

local Window = New("CanvasGroup", {
	Name = "Window",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Parent = Shell,
}, { Corner(WIN_RADIUS) })

-- фон в стиле логотипа: тёмный, фиолетовое свечение из угла
New("Frame", {
	Name = "Bg",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Parent = Window,
}, {
	New("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 54, 128)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 18, 38)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 14)),
		}),
		Rotation = 40,
	}),
})
New("Frame", {
	Name = "GlowTop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
	Parent = Window,
}, {
	New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 45,
	}),
})
New("Frame", {
	Name = "GlowBottom",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(95, 80, 205),
	BorderSizePixel = 0,
	Parent = Window,
}, {
	New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.65, 1),
			NumberSequenceKeypoint.new(1, 0.75),
		}),
		Rotation = 90,
	}),
})

-- контур со змейкой (снаружи CanvasGroup, чтобы обводка не обрезалась)
local Outline = New("Frame", {
	Name = "Outline",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = Shell,
}, { Corner(WIN_RADIUS) })
local OutlineStroke = SnakeBorder(Outline, 2, 3.2)
OutlineStroke.Transparency = 1

-- шапка (без логотипа, только вкладки)
local Header = New("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundTransparency = 1,
	Parent = Window,
})
MakeDraggable(Header, Root)

local TabBar = New("CanvasGroup", {
	Name = "TabBar",
	Position = UDim2.fromOffset(24, 0),
	Size = UDim2.new(1, -48, 1, 0),
	BackgroundTransparency = 1,
	Parent = Header,
}, {
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local TabBarBase = TabBar.Position

-- контент
local Content = New("Frame", {
	Name = "Content",
	Position = UDim2.fromOffset(24, 64),
	Size = UDim2.new(1, -48, 1, -132),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = Window,
})

local function NewHolder(parent)
	return New("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = parent,
	})
end

local function NewScroll(parent)
	return New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		New("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 40),
			CellPadding = UDim2.fromOffset(10, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		New("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }),
	})
end

local ModulesPage = NewHolder(Content)
local SettingsPage = NewHolder(Content)
local SettingsScroll = NewScroll(SettingsPage)

-- док снизу: круглые иконки и скользящая круглая подсветка
local SLOT = 56
local Dock = New("Frame", {
	Name = "Dock",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(SLOT * 2, 52),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Parent = Window,
}, {
	Corner(26),
	New("UIStroke", { Color = Color3.fromRGB(90, 82, 150), Thickness = 1, Transparency = 0.5 }),
})

local DockHighlight = New("Frame", {
	Position = UDim2.fromOffset(7, 5),
	Size = UDim2.fromOffset(42, 42),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
	Parent = Dock,
}, {
	Round(),
	New("UIGradient", {
		Color = ColorSequence.new(Theme.AccentSoft, Theme.Accent),
		Rotation = 90,
	}),
})

local DockButtons = {}
local function DockButton(name, slot, iconId, fallback, page)
	local b = New("TextButton", {
		Position = UDim2.fromOffset((slot - 1) * SLOT, 0),
		Size = UDim2.fromOffset(SLOT, 52),
		BackgroundTransparency = 1,
		Text = "",
		Parent = Dock,
	})
	local img = Icon(b, iconId, UDim2.fromOffset(34, 34), fallback)
	DockButtons[name] = { Button = b, Icon = img, X = (slot - 1) * SLOT + 7, Page = page }
	return b
end

local PageOrder = { Modules = 1, Settings = 2 }
local CurrentPage

function Dar3x.ShowPage(name)
	if name == CurrentPage then
		return
	end
	local old = CurrentPage
	CurrentPage = name
	local dir = (PageOrder[name] > (old and PageOrder[old] or 0)) and 1 or -1

	for n, d in pairs(DockButtons) do
		local on = n == name
		Tween(d.Icon, 0.25, { ImageColor3 = on and Color3.new(1, 1, 1) or Theme.Muted })
		if on then
			Tween(DockHighlight, 0.45, { Position = UDim2.fromOffset(d.X, 5) }, Back)
			ShowHolder(d.Page, dir)
		elseif n == old then
			HideHolder(d.Page, dir)
		end
	end

	if name == "Modules" then
		ShowHolder(TabBar, 0, TabBarBase)
	elseif old then
		HideHolder(TabBar, 0, TabBarBase)
	end
end

Connect(DockButton("Modules", 1, ICONS.Modules, "M", ModulesPage).MouseButton1Click, function()
	Dar3x.ShowPage("Modules")
end)
Connect(DockButton("Settings", 2, ICONS.Settings, "S", SettingsPage).MouseButton1Click, function()
	Dar3x.ShowPage("Settings")
end)

----------------------------------------------------------------
-- Секции: переключатели и кнопки
----------------------------------------------------------------
local Section = {}
Section.__index = Section

local function Row(parent)
	return New("Frame", {
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Corner(16) })
end

local function RowLabel(row, text, color)
	return New("TextLabel", {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -78, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
end

function Section:AddToggle(name, default, callback)
	local key = self.Name .. "." .. name
	local state = default and true or false
	Dar3x.Flags[key] = state

	local row = Row(self.Page)
	local label = RowLabel(row, name, state and Theme.Text or Theme.Muted)
	local track = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(38, 20),
		BackgroundColor3 = state and Theme.Accent or Theme.Off,
		BorderSizePixel = 0,
		Parent = row,
	}, { Corner(10) })
	local knob = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = state and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	}, { Corner(8) })
	local hit = New("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})

	local obj = {}
	function obj:Set(v, silent)
		state = v and true or false
		Dar3x.Flags[key] = state
		Tween(track, 0.25, { BackgroundColor3 = state and Theme.Accent or Theme.Off })
		Tween(knob, 0.35, {
			Position = state and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}, Back)
		Tween(label, 0.25, { TextColor3 = state and Theme.Text or Theme.Muted })
		Tween(row, 0.25, { BackgroundTransparency = state and 0.3 or 0.55 })
		if callback and not silent then
			task.spawn(function()
				local ok, err = pcall(callback, state)
				if not ok then
					warn("[Dar3x] " .. key .. ": " .. tostring(err))
				end
			end)
		end
	end
	function obj:Get()
		return state
	end

	Connect(hit.MouseButton1Click, function()
		obj:Set(not state)
	end)
	if state then
		row.BackgroundTransparency = 0.3
		if callback then
			task.spawn(pcall, callback, state)
		end
	end
	return obj
end

function Section:AddButton(name, callback)
	local row = Row(self.Page)
	RowLabel(row, name, Theme.Text)
	New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Text = ">",
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Accent,
		Parent = row,
	})
	local hit = New("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})
	Connect(hit.MouseButton1Click, function()
		Tween(row, 0.1, { BackgroundTransparency = 0.15 })
		task.delay(0.12, function()
			Tween(row, 0.3, { BackgroundTransparency = 0.55 })
		end)
		if callback then
			task.spawn(function()
				local ok, err = pcall(callback)
				if not ok then
					warn("[Dar3x] " .. name .. ": " .. tostring(err))
				end
			end)
		end
	end)
end

----------------------------------------------------------------
-- Вкладки
----------------------------------------------------------------
local ActiveTab

local function SelectTab(tab)
	if tab == ActiveTab then
		return
	end
	local old = ActiveTab
	ActiveTab = tab
	local dir = (not old or tab.Index > old.Index) and 1 or -1
	for _, t in ipairs(Dar3x.Tabs) do
		local on = t == tab
		Tween(t.Button, 0.25, { TextColor3 = on and Theme.Text or Theme.Muted })
		Tween(t.Underline, 0.4, {
			Size = on and UDim2.new(1, -20, 0, 2) or UDim2.new(0, 0, 0, 2),
			BackgroundTransparency = on and 0 or 1,
		}, Quint)
		if on then
			ShowHolder(t.Holder, dir)
		elseif t == old then
			HideHolder(t.Holder, dir)
		end
	end
end

function Dar3x.AddTab(name)
	local tab = setmetatable({ Name = name, Index = #Dar3x.Tabs + 1 }, Section)
	tab.Holder = NewHolder(ModulesPage)
	tab.Page = NewScroll(tab.Holder)
	tab.Button = New("TextButton", {
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = name,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		LayoutOrder = tab.Index,
		Parent = TabBar,
	}, {
		New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	tab.Underline = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Theme.AccentSoft,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = tab.Button,
	}, { Corner(1) })

	table.insert(Dar3x.Tabs, tab)
	Connect(tab.Button.MouseButton1Click, function()
		SelectTab(tab)
	end)
	if not ActiveTab then
		SelectTab(tab)
	end
	return tab
end

----------------------------------------------------------------
-- Настройки (страница Settings)
----------------------------------------------------------------
local Prog, ApplyProgress -- прогресс открытия меню 0..1 (объявлены заранее)

local Settings = setmetatable({ Name = "Settings", Page = SettingsScroll }, Section)
Settings:AddToggle("Background blur", true, function()
	if Prog and ApplyProgress then
		ApplyProgress(Prog.Value)
	end
end)
Settings:AddButton("Unload Dar3x", function()
	Dar3x.Destroy()
end)

----------------------------------------------------------------
-- iOS-полоска: тап открывает/закрывает, свайп вверх/вниз ведёт меню за пальцем
----------------------------------------------------------------
local Bar = New("TextButton", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -4),
	Size = UDim2.fromOffset(180, 34),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Parent = Gui,
})
local Pill = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(96, 5),
	BackgroundColor3 = Theme.Text,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Parent = Bar,
}, {
	Round(),
	New("UIStroke", { Color = Theme.Accent, Thickness = 1, Transparency = 0.45 }),
})

local Blur
ApplyProgress = function(p)
	Root.Visible = p > 0.002
	local s = 0.86 + 0.14 * p
	Shell.Size = UDim2.fromScale(s, s)
	Shell.Position = UDim2.new(0.5, 0, 0.5, (1 - p) * 40)
	Window.GroupTransparency = 1 - math.clamp(p * 1.4, 0, 1)
	OutlineStroke.Transparency = 1 - math.clamp((p - 0.15) / 0.85, 0, 1)
	Pill.Size = UDim2.fromOffset(96 + 44 * p, 5)
	Pill.BackgroundColor3 = Theme.Text:Lerp(Theme.AccentSoft, p)

	local want = p > 0.002 and Dar3x.Flags["Settings.Background blur"]
	if want then
		if not Blur then
			Blur = New("BlurEffect", { Name = "Dar3xBlur", Size = 0, Parent = Lighting })
		end
		Blur.Size = 14 * p
	elseif Blur then
		Blur:Destroy()
		Blur = nil
	end
end

Prog = Instance.new("NumberValue")
Prog.Value = 0
Connect(Prog.Changed, ApplyProgress)
ApplyProgress(0)

local ProgTween
local function GoTo(target, t, style, dir)
	if ProgTween then
		ProgTween:Cancel()
	end
	ProgTween = TweenService:Create(Prog, TweenInfo.new(t, style, dir), { Value = target })
	ProgTween:Play()
end

function Dar3x.Open()
	Dar3x.IsOpen = true
	GoTo(1, 0.25 + 0.4 * (1 - Prog.Value), Quint, Enum.EasingDirection.Out)
end

function Dar3x.Close()
	Dar3x.IsOpen = false
	GoTo(0, 0.15 + 0.2 * Prog.Value, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

function Dar3x.Toggle()
	if Dar3x.IsOpen then
		Dar3x.Close()
	else
		Dar3x.Open()
	end
end

local dragging, moved = false, false
local startY, startProg, lastY, lastT, velocity = 0, 0, 0, 0, 0

local function EndDrag()
	if not dragging then
		return
	end
	dragging = false
	if not moved then
		Dar3x.Toggle() -- обычный тап
		return
	end
	if velocity > 450 then
		Dar3x.Open()
	elseif velocity < -450 then
		Dar3x.Close()
	elseif Prog.Value > 0.5 then
		Dar3x.Open()
	else
		Dar3x.Close()
	end
end

Connect(Bar.InputBegan, function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragging, moved, velocity = true, false, 0
		startY = input.Position.Y
		startProg = Prog.Value
		lastY, lastT = startY, os.clock()
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				EndDrag()
			end
		end)
	end
end)

Connect(UserInputService.InputChanged, function(input)
	if
		dragging
		and (
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		)
	then
		local y = input.Position.Y
		local dy = startY - y -- вверх = положительное
		if not moved and math.abs(dy) > 8 then
			moved = true
			if ProgTween then
				ProgTween:Cancel()
			end
		end
		if moved then
			Prog.Value = math.clamp(startProg + dy / DRAG_DIST, 0, 1)
			local now = os.clock()
			local dt = math.max(now - lastT, 1 / 120)
			velocity = velocity * 0.6 + ((lastY - y) / dt) * 0.4
			lastY, lastT = y, now
		end
	end
end)

-- клавиша для ПК
Connect(UserInputService.InputBegan, function(input, gpe)
	if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
		Dar3x.Toggle()
	end
end)

----------------------------------------------------------------
-- Старт и выгрузка
----------------------------------------------------------------
function Dar3x.Start()
	Dar3x.ShowPage("Modules")
	Dar3x.Open()
end

function Dar3x.Destroy()
	for _, c in ipairs(Dar3x.Connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(Dar3x.Connections)
	if ProgTween then
		pcall(function()
			ProgTween:Cancel()
		end)
	end
	if Blur then
		pcall(function()
			Blur:Destroy()
		end)
		Blur = nil
	end
	pcall(function()
		Prog:Destroy()
	end)
	pcall(function()
		Gui:Destroy()
	end)
	if _G.Dar3xClient == Dar3x then
		_G.Dar3xClient = nil
		_G.Dar4xClient = nil
	end
end

Dar3x.ShowPage("Modules")
print("[Dar3x] core loaded v" .. Dar3x.Version)
