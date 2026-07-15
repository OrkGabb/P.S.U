--!strict
-- @Author @OrkGabb
-- Single source of truth for the panel palette. Controllers still build their
-- own widgets; this only fixes the shared chrome colors (surfaces, accent,
-- text, danger) so a palette change is one edit instead of ten.

local UITheme = {
	-- Surfaces (graphite, neutral — no violet tint)
	PanelBackground = Color3.fromRGB(18, 21, 28),
	PanelGradientTop = Color3.fromRGB(24, 29, 38),
	PanelGradientBottom = Color3.fromRGB(11, 13, 18),
	CardBackground = Color3.fromRGB(20, 24, 31),
	CardStroke = Color3.fromRGB(30, 68, 70),

	-- Accent (cyan)
	Accent = Color3.fromRGB(47, 217, 200),
	AccentBright = Color3.fromRGB(90, 235, 222),
	AccentDeep = Color3.fromRGB(27, 140, 130),
	AccentShadow = Color3.fromRGB(18, 96, 92),

	-- Text
	TitleText = Color3.fromRGB(234, 246, 244),
	BodyText = Color3.fromRGB(200, 214, 216),
	MutedText = Color3.fromRGB(126, 148, 152),

	-- Destructive / close
	DangerIdle = Color3.fromRGB(224, 80, 60),
	DangerHover = Color3.fromRGB(255, 106, 82),
	DangerStroke = Color3.fromRGB(120, 34, 24),
}

return UITheme
