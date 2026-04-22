-- SoundCatalog
-- Single UI sound: a click on any button. Keep it simple.

export type SoundDef = {
	id: number,
	volume: number,
	pitch: number?,
}

local SoundCatalog: { [string]: SoundDef } = {
	click = { id = 116080744084010, volume = 0.35 },
}

return SoundCatalog
