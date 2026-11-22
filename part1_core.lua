--[[
	Dar3x Client | part1_core.lua
	Ядро: тема, стеклянное меню, змейка по контуру, вкладки, док, переключатели.

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
	Version = "0.1.0",
	Flags = {},
	Tabs = {},
	Connections = {},
	IsOpen = false,
}
_G.Dar3xClient = Dar3x
_G.Dar4xClient = Dar3x -- алиас, чтобы старый загрузчик тоже работал

----------------------------------------------------------------
-- Тема
----------------------------------------------------------------
local Theme = {
	Accent = Color3.fromRGB(139, 92, 246),
	Panel = Color3.fromRGB(14, 14, 22),
	Row = Color3.fromRGB(26, 26, 40),
	Text = Color3.fromRGB(235, 235, 245),
	Muted = Color3.fromRGB(125, 125, 148),
	Off = Color3.fromRGB(48, 48, 64),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}
Dar3x.Theme = Theme

local WIN_W, WIN_H = 580, 340

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

-- фиолетовая змейка, плавно бегущая по контуру
local function SnakeBorder(frame, thickness, duration)
	local stroke = New("UIStroke", {
		Thickness = thickness or 2,
		Color = Color3.new(1, 1, 1),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	local grad = New("UIGradient", {
		Color = ColorSequence.new(Theme.Accent),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(0.8, 0.2),
			NumberSequenceKeypoint.new(0.95, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = stroke,
	})
	local tw = TweenService:Create(
		grad,
		TweenInfo.new(duration or 3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Rotation = 360 }
	)
	tw:Play()
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
	local s = math.clamp(math.min(vp.X * 0.92 / WIN_W, vp.Y * 0.85 / WIN_H), 0.5, 1)
	UIScale.Scale = s
	Root.Size = UDim2.fromOffset(WIN_W * s, WIN_H * s)
end
Fit()
if workspace.CurrentCamera then
	Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), Fit)
end

-- стеклянное окно
local Window = New("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.22,
	BorderSizePixel = 0,
	Parent = Scaler,
}, {
	Corner(16),
	New("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(34, 28, 58), Color3.fromRGB(10, 10, 16)),
		Rotation = 70,
	}),
})
SnakeBorder(Window, 2, 3)

-- блик сверху (имитация стекла)
New("Frame", {
	Name = "Gloss",
	Position = UDim2.fromOffset(18, 1),
	Size = UDim2.new(1, -36, 0, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.7,
	BorderSizePixel = 0,
	Parent = Window,
}, {
	New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- шапка
local Header = New("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
	Parent = Window,
})
MakeDraggable(Header, Root)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.fromOffset(70, 46),
	BackgroundTransparency = 1,
	Text = "Dar3x",
	Font = Theme.FontBold,
	TextSize = 17,
	TextColor3 = Theme.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = Header,
})

local TabBar = New("Frame", {
	Name = "TabBar",
	Position = UDim2.fromOffset(92, 0),
	Size = UDim2.new(1, -150, 1, 0),
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

local CloseBtn = New("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = Theme.Row,
	BackgroundTransparency = 0.5,
	Text = "X",
	Font = Theme.FontBold,
	TextSize = 13,
	TextColor3 = Theme.Muted,
	AutoButtonColor = false,
	Parent = Header,
}, { Corner(8) })

-- контент: страницы Modules и Settings
local Content = New("Frame", {
	Name = "Content",
	Position = UDim2.fromOffset(16, 56),
	Size = UDim2.new(1, -32, 1, -116),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = Window,
})

local ModulesPage = New("Frame", {
	Name = "Modules",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = Content,
})
local SettingsPage = New("Frame", {
	Name = "Settings",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = Content,
})

local function NewScroll(parent)
	return New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	}, {
		New("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 38),
			CellPadding = UDim2.fromOffset(10, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		New("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 40) }),
	})
end

-- док снизу
local Dock = New("Frame", {
	Name = "Dock",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(190, 36),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Parent = Window,
}, {
	Corner(12),
	New("UIStroke", { Color = Color3.fromRGB(70, 70, 95), Thickness = 1, Transparency = 0.4 }),
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}),
})

local DockButtons = {}
local function DockButton(name, text, page)
	local b = New("TextButton", {
		Size = UDim2.fromOffset(84, 28),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Muted,
		AutoButtonColor = false,
		Parent = Dock,
	}, { Corner(8) })
	DockButtons[name] = { Button = b, Page = page }
	return b
end

function Dar3x.ShowPage(name)
	for n, d in pairs(DockButtons) do
		local on = n == name
		d.Page.Visible = on
		Tween(d.Button, 0.2, {
			BackgroundTransparency = on and 0 or 1,
			TextColor3 = on and Color3.new(1, 1, 1) or Theme.Muted,
		})
	end
	TabBar.Visible = name == "Modules"
end

Connect(DockButton("Modules", "Modules", ModulesPage).MouseButton1Click, function()
	Dar3x.ShowPage("Modules")
end)
Connect(DockButton("Settings", "Settings", SettingsPage).MouseButton1Click, function()
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
	}, { Corner(9) })
end

local function RowLabel(row, text, color)
	return New("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -70, 1, 0),
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
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(36, 18),
		BackgroundColor3 = state and Theme.Accent or Theme.Off,
		BorderSizePixel = 0,
		Parent = row,
	}, { Corner(9) })
	local knob = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = state and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	}, { Corner(7) })
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
		Tween(track, 0.2, { BackgroundColor3 = state and Theme.Accent or Theme.Off })
		Tween(knob, 0.2, { Position = state and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) })
		Tween(label, 0.2, { TextColor3 = state and Theme.Text or Theme.Muted })
		Tween(row, 0.2, { BackgroundTransparency = state and 0.3 or 0.55 })
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
		Position = UDim2.new(1, -14, 0.5, 0),
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
		Tween(row, 0.1, { BackgroundTransparency = 0.2 })
		task.delay(0.12, function()
			Tween(row, 0.2, { BackgroundTransparency = 0.55 })
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
	ActiveTab = tab
	for _, t in ipairs(Dar3x.Tabs) do
		local on = t == tab
		t.Page.Visible = on
		Tween(t.Button, 0.2, { TextColor3 = on and Theme.Text or Theme.Muted })
		Tween(t.Underline, 0.2, { BackgroundTransparency = on and 0 or 1 })
	end
end

function Dar3x.AddTab(name)
	local tab = setmetatable({ Name = name }, Section)
	tab.Page = NewScroll(ModulesPage)
	tab.Button = New("TextButton", {
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = name,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		LayoutOrder = #Dar3x.Tabs + 1,
		Parent = TabBar,
	}, {
		New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	tab.Underline = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, -20, 0, 2),
		BackgroundColor3 = Theme.Accent,
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
local Settings = setmetatable({ Name = "Settings", Page = NewScroll(SettingsPage) }, Section)
Settings.Page.Visible = true

local Blur
local function UpdateBlur()
	local want = Dar3x.IsOpen and Dar3x.Flags["Settings.Background blur"]
	if want then
		if not Blur then
			Blur = New("BlurEffect", { Name = "Dar3xBlur", Size = 0, Parent = Lighting })
		end
		Tween(Blur, 0.25, { Size = 14 })
	elseif Blur then
		local b = Blur
		Blur = nil
		Tween(b, 0.2, { Size = 0 })
		task.delay(0.25, function()
			b:Destroy()
		end)
	end
end

Settings:AddToggle("Background blur", true, function()
	UpdateBlur()
end)
Settings:AddButton("Unload Dar3x", function()
	Dar3x.Destroy()
end)

----------------------------------------------------------------
-- Открыть / закрыть
----------------------------------------------------------------
function Dar3x.Open()
	Dar3x.IsOpen = true
	Root.Visible = true
	Window.Size = UDim2.fromScale(0.94, 0.94)
	Tween(Window, 0.28, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
	UpdateBlur()
end

function Dar3x.Close()
	Dar3x.IsOpen = false
	Tween(Window, 0.18, { Size = UDim2.fromScale(0.94, 0.94) })
	task.delay(0.18, function()
		if not Dar3x.IsOpen then
			Root.Visible = false
		end
	end)
	UpdateBlur()
end

function Dar3x.Toggle()
	if Dar3x.IsOpen then
		Dar3x.Close()
	else
		Dar3x.Open()
	end
end

Connect(CloseBtn.MouseButton1Click, Dar3x.Close)

-- плавающая кнопка (для телефона)
local Fab = New("TextButton", {
	Name = "Fab",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.35, 0),
	Size = UDim2.fromOffset(42, 42),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.2,
	Text = "D",
	Font = Theme.FontBold,
	TextSize = 18,
	TextColor3 = Theme.Accent,
	AutoButtonColor = false,
	Parent = Gui,
}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) })
SnakeBorder(Fab, 2, 3)
Connect(Fab.MouseButton1Click, Dar3x.Toggle)

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
	if Blur then
		pcall(function()
			Blur:Destroy()
		end)
		Blur = nil
	end
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
