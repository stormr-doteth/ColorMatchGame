-- CIEDE2000-based perceptual color scoring.
-- Pipeline: HSV -> sRGB -> linear RGB -> CIE XYZ (D65) -> CIE Lab -> dE00
-- Score curve: 100 / (1 + (dE / 25.25)^1.55), per dialed.gg.

local PI = math.pi
local DEG = 180 / PI
local RAD = PI / 180

-- ===== HSV -> sRGB (0..1) =====
local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
	if s <= 0 then
		return v, v, v
	end
	local hh = (h % 1) * 6
	local i = math.floor(hh)
	local f = hh - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))
	if i == 0 then return v, t, p
	elseif i == 1 then return q, v, p
	elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v
	elseif i == 4 then return t, p, v
	else return v, p, q
	end
end

-- ===== sRGB -> CIE Lab (D65) =====
local function srgbChannelToLinear(c: number): number
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local LAB_EPSILON = (6 / 29) ^ 3 -- ~0.008856
local LAB_KAPPA = (1 / 3) * (29 / 6) ^ 2 -- ~7.787

local function labF(t: number): number
	if t > LAB_EPSILON then
		return t ^ (1 / 3)
	end
	return LAB_KAPPA * t + 4 / 29
end

local function rgbToLab(r: number, g: number, b: number): (number, number, number)
	local lr = srgbChannelToLinear(r)
	local lg = srgbChannelToLinear(g)
	local lb = srgbChannelToLinear(b)

	-- D65 sRGB matrix
	local X = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb
	local Y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
	local Z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb

	-- Normalize against D65 white point
	local fx = labF(X / 0.95047)
	local fy = labF(Y / 1.00000)
	local fz = labF(Z / 1.08883)

	local L = 116 * fy - 16
	local a = 500 * (fx - fy)
	local bb = 200 * (fy - fz)
	return L, a, bb
end

-- ===== CIEDE2000 =====
local function deltaE2000(L1: number, a1: number, b1: number, L2: number, a2: number, b2: number): number
	local C1 = math.sqrt(a1 * a1 + b1 * b1)
	local C2 = math.sqrt(a2 * a2 + b2 * b2)
	local Cbar = (C1 + C2) / 2

	local Cbar7 = Cbar ^ 7
	local G = 0.5 * (1 - math.sqrt(Cbar7 / (Cbar7 + 25 ^ 7)))

	local a1p = (1 + G) * a1
	local a2p = (1 + G) * a2

	local C1p = math.sqrt(a1p * a1p + b1 * b1)
	local C2p = math.sqrt(a2p * a2p + b2 * b2)

	local function hp(ap: number, bp: number): number
		if ap == 0 and bp == 0 then
			return 0
		end
		local h = math.atan2(bp, ap) * DEG
		if h < 0 then h += 360 end
		return h
	end

	local h1p = hp(a1p, b1)
	local h2p = hp(a2p, b2)

	local dLp = L2 - L1
	local dCp = C2p - C1p

	local dhp
	if C1p * C2p == 0 then
		dhp = 0
	else
		local diff = h2p - h1p
		if diff > 180 then
			dhp = diff - 360
		elseif diff < -180 then
			dhp = diff + 360
		else
			dhp = diff
		end
	end

	local dHp = 2 * math.sqrt(C1p * C2p) * math.sin((dhp / 2) * RAD)

	local Lbarp = (L1 + L2) / 2
	local Cbarp = (C1p + C2p) / 2

	local hbarp
	if C1p * C2p == 0 then
		hbarp = h1p + h2p
	else
		local diff = math.abs(h1p - h2p)
		local sum = h1p + h2p
		if diff <= 180 then
			hbarp = sum / 2
		elseif sum < 360 then
			hbarp = (sum + 360) / 2
		else
			hbarp = (sum - 360) / 2
		end
	end

	local T = 1
		- 0.17 * math.cos((hbarp - 30) * RAD)
		+ 0.24 * math.cos((2 * hbarp) * RAD)
		+ 0.32 * math.cos((3 * hbarp + 6) * RAD)
		- 0.20 * math.cos((4 * hbarp - 63) * RAD)

	local dTheta = 30 * math.exp(-(((hbarp - 275) / 25) ^ 2))
	local Cbarp7 = Cbarp ^ 7
	local RC = 2 * math.sqrt(Cbarp7 / (Cbarp7 + 25 ^ 7))
	local SL = 1 + (0.015 * (Lbarp - 50) ^ 2) / math.sqrt(20 + (Lbarp - 50) ^ 2)
	local SC = 1 + 0.045 * Cbarp
	local SH = 1 + 0.015 * Cbarp * T
	local RT = -math.sin((2 * dTheta) * RAD) * RC

	local termL = dLp / SL
	local termC = dCp / SC
	local termH = dHp / SH

	return math.sqrt(termL * termL + termC * termC + termH * termH + RT * termC * termH)
end

-- ===== Score mapping (dialed.gg S-curve, scaled to 0..100) =====
local function computeScore(tH: number, tS: number, tV: number, gH: number, gS: number, gV: number): number
	local tr, tg, tb = hsvToRgb(tH, tS, tV)
	local gr, gg, gb = hsvToRgb(gH, gS, gV)

	local L1, a1, b1 = rgbToLab(tr, tg, tb)
	local L2, a2, b2 = rgbToLab(gr, gg, gb)

	local dE = deltaE2000(L1, a1, b1, L2, a2, b2)

	local score = 100 / (1 + (dE / 25.25) ^ 1.55)
	return math.clamp(math.floor(score + 0.5), 0, 100)
end

return computeScore
