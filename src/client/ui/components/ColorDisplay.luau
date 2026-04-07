local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local e = React.createElement

export type ColorDisplayProps = {
	color: Color3,
	Size: UDim2?,
	LayoutOrder: number?,
	label: string?,
}

local function ColorDisplay(props: ColorDisplayProps)
	local size = props.Size or UDim2.fromOffset(200, 200)

	return e("Frame", {
		Size = size,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Swatch = e("Frame", {
			Size = size,
			BackgroundColor3 = props.color,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(255, 255, 255),
				Thickness = 2,
				Transparency = 0.7,
			}),
		}),

		Label = props.label and e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.new(0, 0, 1, 6),
			BackgroundTransparency = 1,
			Text = props.label,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 14,
			Font = Enum.Font.FredokaOne,
			LayoutOrder = 2,
		}),
	})
end

return ColorDisplay
