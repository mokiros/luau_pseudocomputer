local Kernel = require("@kernel")
local compile_lua = require("@yueliang")

local font = (script:WaitForChild("GetFont") :: RemoteFunction):InvokeServer()

local kernel = Kernel.create({
	screen_width = 80 * 8,
	screen_height = 40 * 16,
	font_data = font,
})

local width, height = Kernel.getScreenDimensions(kernel)

local pixelSize = Vector2.new(width, height)

local player = game:GetService("Players").LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Parent = PlayerGui
local label = Instance.new("ImageLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Size = UDim2.fromOffset(pixelSize.X, pixelSize.Y)
label.Position = UDim2.fromScale(0.5, 0.5)
label.ResampleMode = Enum.ResamplerMode.Pixelated
label.Parent = gui

local cursor = Instance.new("Frame")
cursor.Size = UDim2.fromOffset(6, 14)
cursor.BackgroundTransparency = 1
cursor.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Color = Color3.new(1, 1, 1)
stroke.Parent = cursor

local image = game:GetService("AssetService"):CreateEditableImage({
	Size = pixelSize,
})

label.ImageContent = Content.fromObject(image)

local function render()
	local framebuffer = Kernel.getActiveFramebuffer(kernel)
	local cursorX, cursorY = Kernel.getScreenCursorPosition(kernel)
	image:WritePixelsBuffer(Vector2.zero, pixelSize, framebuffer)
	cursor.Position = UDim2.fromOffset(cursorX + 1, cursorY + 1)
end

local example_hello = compile_lua(
	[[
	write("Hello world!\nhi!\n")
]],
	"hello.lua"
)

Kernel.init(kernel, example_hello)

render()
