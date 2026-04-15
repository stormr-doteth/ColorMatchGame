-- ChairCatalog
-- Single source of truth for purchasable chair skins. Used by:
--   • Server (ChairShop) to set up shop prompts and validate purchases
--   • Server (TableManager) to look up the equipped chair model on seat
--   • Client (InventoryHud) to render owned chairs in the inventory UI
--
-- A chair entry is identified by `id` (a stable string saved in the player
-- profile). `modelName` is the name of the chair Model in workspace, which
-- the server clones into ReplicatedStorage.ChairTemplates at startup.

export type ChairEntry = {
	id: string,
	displayName: string,
	price: number,
	modelName: string,
}

local ChairCatalog: { ChairEntry } = {
	{ id = "red_chair",    displayName = "Red Chair",    price = 100, modelName = "RedChair"    },
	{ id = "yellow_chair", displayName = "Yellow Chair", price = 250, modelName = "YellowChair" },
	{ id = "blue_chair",   displayName = "Blue Chair",   price = 500, modelName = "BlueChair"   },

	-- Mythic tier (lucky block exclusive)
	{ id = "crystal_chair",  displayName = "Crystal Chair",  price = 0, modelName = "CrystalChair"  },
	{ id = "flame_chair",    displayName = "Flame Chair",    price = 0, modelName = "FlameChair"    },
	{ id = "shadow_chair",   displayName = "Shadow Chair",   price = 0, modelName = "ShadowChair"   },
	{ id = "galaxy_chair",   displayName = "Galaxy Chair",   price = 0, modelName = "GalaxyChair"   },

	-- Brainrot God tier (lucky block exclusive)
	{ id = "diamond_chair",    displayName = "Diamond Chair",    price = 0, modelName = "DiamondChair"    },
	{ id = "lava_chair",       displayName = "Lava Chair",       price = 0, modelName = "LavaChair"       },
	{ id = "rainbow_chair",    displayName = "Rainbow Chair",    price = 0, modelName = "RainbowChair"    },
	{ id = "brainrot_throne",  displayName = "Brainrot Throne",  price = 0, modelName = "BrainrotThrone"  },

	-- Common tier (lucky block exclusive)
	{ id = "wood_chair",      displayName = "Wood Chair",      price = 0, modelName = "WoodChair"      },
	{ id = "stone_chair",     displayName = "Stone Chair",     price = 0, modelName = "StoneChair"     },
	{ id = "plastic_chair",   displayName = "Plastic Chair",   price = 0, modelName = "PlasticChair"   },
	{ id = "brick_chair",     displayName = "Brick Chair",     price = 0, modelName = "BrickChair"     },
	{ id = "grass_chair",     displayName = "Grass Chair",     price = 0, modelName = "GrassChair"     },

	-- Uncommon tier
	{ id = "copper_chair",    displayName = "Copper Chair",    price = 0, modelName = "CopperChair"    },
	{ id = "ice_chair",       displayName = "Ice Chair",       price = 0, modelName = "IceChair"       },
	{ id = "sand_chair",      displayName = "Sand Chair",      price = 0, modelName = "SandChair"      },
	{ id = "marble_chair",    displayName = "Marble Chair",    price = 0, modelName = "MarbleChair"    },
	{ id = "moss_chair",      displayName = "Moss Chair",      price = 0, modelName = "MossChair"      },

	-- Rare tier
	{ id = "silver_chair",    displayName = "Silver Chair",    price = 0, modelName = "SilverChair"    },
	{ id = "emerald2_chair",  displayName = "Emerald Chair",   price = 0, modelName = "EmeraldChair2"  },
	{ id = "frost_chair",     displayName = "Frost Chair",     price = 0, modelName = "FrostChair"     },
	{ id = "obsidian_chair",  displayName = "Obsidian Chair",  price = 0, modelName = "ObsidianChair"  },
	{ id = "ruby2_chair",     displayName = "Ruby Chair",      price = 0, modelName = "RubyChair2"     },

	-- Epic tier
	{ id = "golden_chair",    displayName = "Golden Chair",    price = 0, modelName = "GoldenChair"    },
	{ id = "void_chair",      displayName = "Void Chair",      price = 0, modelName = "VoidChair"      },
	{ id = "inferno_chair",   displayName = "Inferno Chair",   price = 0, modelName = "InfernoChair"   },
	{ id = "aqua_chair",      displayName = "Aqua Chair",      price = 0, modelName = "AquaChair"      },
	{ id = "plasma_chair",    displayName = "Plasma Chair",    price = 0, modelName = "PlasmaChair"    },

	-- Legendary tier
	{ id = "cosmic_chair",    displayName = "Cosmic Chair",    price = 0, modelName = "CosmicChair"    },
	{ id = "phoenix_chair",   displayName = "Phoenix Chair",   price = 0, modelName = "PhoenixChair"   },
	{ id = "abyss_chair",     displayName = "Abyss Chair",     price = 0, modelName = "AbyssChair"     },
	{ id = "celestial_chair", displayName = "Celestial Chair", price = 0, modelName = "CelestialChair" },
	{ id = "omega_chair",     displayName = "Omega Chair",     price = 0, modelName = "OmegaChair"     },

	-- TODO: remove after testing — 25 randomized $1 chairs for UI stress test
	{ id = "crimson_chair",  displayName = "Crimson Chair",  price = 1, modelName = "CrimsonChair"  },
	{ id = "azure_chair",    displayName = "Azure Chair",    price = 1, modelName = "AzureChair"    },
	{ id = "emerald_chair",  displayName = "Emerald Chair",  price = 1, modelName = "EmeraldChair"  },
	{ id = "gold_chair",     displayName = "Gold Chair",     price = 1, modelName = "GoldChair"     },
	{ id = "purple_chair",   displayName = "Purple Chair",   price = 1, modelName = "PurpleChair"   },
	{ id = "teal_chair",     displayName = "Teal Chair",     price = 1, modelName = "TealChair"     },
	{ id = "orange_chair",   displayName = "Orange Chair",   price = 1, modelName = "OrangeChair"   },
	{ id = "pink_chair",     displayName = "Pink Chair",     price = 1, modelName = "PinkChair"     },
	{ id = "lime_chair",     displayName = "Lime Chair",     price = 1, modelName = "LimeChair"     },
	{ id = "navy_chair",     displayName = "Navy Chair",     price = 1, modelName = "NavyChair"     },
	{ id = "coral_chair",    displayName = "Coral Chair",    price = 1, modelName = "CoralChair"    },
	{ id = "mint_chair",     displayName = "Mint Chair",     price = 1, modelName = "MintChair"     },
	{ id = "violet_chair",   displayName = "Violet Chair",   price = 1, modelName = "VioletChair"   },
	{ id = "amber_chair",    displayName = "Amber Chair",    price = 1, modelName = "AmberChair"    },
	{ id = "cyan_chair",     displayName = "Cyan Chair",     price = 1, modelName = "CyanChair"     },
	{ id = "magenta_chair",  displayName = "Magenta Chair",  price = 1, modelName = "MagentaChair"  },
	{ id = "olive_chair",    displayName = "Olive Chair",    price = 1, modelName = "OliveChair"    },
	{ id = "rust_chair",     displayName = "Rust Chair",     price = 1, modelName = "RustChair"     },
	{ id = "sky_chair",      displayName = "Sky Chair",      price = 1, modelName = "SkyChair"      },
	{ id = "peach_chair",    displayName = "Peach Chair",    price = 1, modelName = "PeachChair"    },
	{ id = "indigo_chair",   displayName = "Indigo Chair",   price = 1, modelName = "IndigoChair"   },
	{ id = "sage_chair",     displayName = "Sage Chair",     price = 1, modelName = "SageChair"     },
	{ id = "ruby_chair",     displayName = "Ruby Chair",     price = 1, modelName = "RubyChair"     },
	{ id = "jade_chair",     displayName = "Jade Chair",     price = 1, modelName = "JadeChair"     },
	{ id = "sunset_chair",   displayName = "Sunset Chair",   price = 1, modelName = "SunsetChair"   },
}

local byId: { [string]: ChairEntry } = {}
for _, entry in ChairCatalog do
	byId[entry.id] = entry
end

local M = {}

function M.GetAll(): { ChairEntry }
	return ChairCatalog
end

function M.Get(id: string): ChairEntry?
	return byId[id]
end

return M
