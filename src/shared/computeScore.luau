local function computeScore(tH: number, tS: number, tV: number, gH: number, gS: number, gV: number): number
	local hueDiff = math.abs(tH - gH)
	hueDiff = math.min(hueDiff, 1 - hueDiff)
	local hueError = hueDiff / 0.5

	local satError = math.abs(tS - gS)
	local valError = math.abs(tV - gV)

	local totalError = (hueError * 0.4) + (satError * 0.3) + (valError * 0.3)
	return math.clamp(math.floor((1 - totalError) * 100 + 0.5), 0, 100)
end

return computeScore
