local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local Slider = require(script.Parent.Slider)

local e = React.createElement

export type SliderGroupProps = {
	guessH: number,
	guessS: number,
	guessV: number,
	onChangeH: (number) -> (),
	onChangeS: (number) -> (),
	onChangeV: (number) -> (),
}

local function SliderGroup(props: SliderGroupProps)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 170),
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),

		Hue = e(Slider, {
			label = "Hue",
			min = 0,
			max = 360,
			value = props.guessH,
			onChange = props.onChangeH,
			LayoutOrder = 1,
		}),

		Saturation = e(Slider, {
			label = "Saturation",
			min = 0,
			max = 100,
			value = props.guessS,
			onChange = props.onChangeS,
			LayoutOrder = 2,
		}),

		Brightness = e(Slider, {
			label = "Brightness",
			min = 0,
			max = 100,
			value = props.guessV,
			onChange = props.onChangeV,
			LayoutOrder = 3,
		}),
	})
end

return SliderGroup
