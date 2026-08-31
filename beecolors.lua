-- beecolors.lua  ->  install to /home/lib/beecolors.lua
-- Species -> authentic display color, extracted from mod source.
-- Format: ["Name"]={0xRRGGBB} or {0xRRGGBB,true} for glint species.
-- Duplicate names across mods: GregTech entry wins (listed last).
-- Unknown species fall back to a stable hashed color.

local colors = {}

colors.PALETTE = {
-- Forestry
["Forest"]={0x19D0EC},["Meadows"]={0xEF131E},["Common"]={0xB2B2B2},["Cultivated"]={0x5734EC},
["Noble"]={0xEC9A19},["Majestic"]={0x7F0000},["Imperial"]={0xA3E02F,true},["Diligent"]={0xC219EC},
["Unweary"]={0x19EC5A},["Industrious"]={0xFFFFFF,true},["Steadfast"]={0x4D2B15,true},["Valiant"]={0x626BDD},
["Heroic"]={0xB3D5E4,true},["Sinister"]={0xB3D5E4},["Fiendish"]={0xD7BEE5},["Demonic"]={0xF4E400,true},
["Modest"]={0xC5BE86},["Frugal"]={0xE8DCB1},["Austere"]={0xFFFAC2,true},["Tropical"]={0x378020},
["Exotic"]={0x304903},["Edenic"]={0x393D0D,true},["Ended"]={0xE079FA},["Spectral"]={0xA98BED},
["Phantasmal"]={0xCC00FA,true},["Wintry"]={0xA0FFC8},["Icy"]={0xA0FFFF},["Glacial"]={0xEFFFFF,true},
["Vindictive"]={0xEAFFF3},["Vengeful"]={0xC2DE00},["Avenging"]={0xDDFF00,true},["Leporine"]={0xFEFF8F,true},
["Merry"]={0xFFFFFF,true},["Tipsy"]={0xFFFFFF,true},["Tricky"]={0x49413B,true},["Rural"]={0xFEFF8F},
["Farmerly"]={0xD39728},["Agrarian"]={0xFFCA75,true},["Marshy"]={0x546626},["Miry"]={0x92AF42},
["Boggy"]={0x698948},["Monastic"]={0x42371C},["Secluded"]={0x7B6634},["Hermitic"]={0xFFD46C,true},
-- ExtraBees
["Arid"]={0xBEE854},["Barren"]={0xE0D263},["Desolate"]={0xD1B890,true},["Decomposing"]={0x523711},
["Gnawing"]={0xE874B0},["Rotten"]={0xBFE0B6},["Bone"]={0xE9EDE8},["Creeper"]={0x2CE615},
["Rock"]={0xA8A8A8},["Stone"]={0x757575},["Granite"]={0x695555},["Mineral"]={0x6E757D},
["Copper"]={0xD16308},["Tin"]={0xBDB1BD},["Iron"]={0xA87058},["Lead"]={0xAD8BAB},
["Zinc"]={0xEDEBFF},["Titanium"]={0xB0AAE3},["Tungstate"]={0x131214},["Nickel"]={0xFFDEFC},
["Gold"]={0xE6CC0B},["Silver"]={0x43455B},["Platinum"]={0xDBDBDB},["Lapis"]={0x3D2CDB},
["Emerald"]={0x1CFF03},["Ruby"]={0xD60000},["Sapphire"]={0x0A47FF},["Diamond"]={0x7FBDFA},
["Unstable"]={0x3E8C34},["Nuclear"]={0x41CC2F},["Radioactive"]={0x1EFF00,true},["Yellorium"]={0xD5ED00},
["Cyanite"]={0x0086ED},["Blutonium"]={0x1B00E6},["Ancient"]={0xF2DB8F},["Primeval"]={0xB3A67B},
["Prehistoric"]={0x6E5A40},["Relic"]={0x4D3E16,true},["Coal"]={0x7A7648},["Resin"]={0xA6731B},
["Oil"]={0x574770},["Distilled"]={0x356356},["Fuel"]={0xFFC003,true},["Creosote"]={0x979E13,true},
["Latex"]={0x494A3E,true},["Water"]={0x94A2FF},["River"]={0x83B3D4},["Ocean"]={0x1D2EAD},
["Ink"]={0x0E1447},["Growing"]={0x5BEBD8},["Farm"]={0x75DB60},["Thriving"]={0x34E37D},
["Blooming"]={0x0ABF34},["Sweet"]={0xFC51F1},["Sugar"]={0xE6D3E0},["Ripening"]={0xB2C75D},
["Fruit"]={0xDB5876,true},["Alcohol"]={0xE88A61},["Milk"]={0xE3E8E8},["Coffee"]={0x8C5E30},
["Swamp"]={0x356933},["Boggy"]={0x785C29},["Fungal"]={0xD16200,true},["Basalt"]={0x8C6969},
["Tempered"]={0x8A4848},["Volcanic"]={0x4D0C0C,true},["Glowstone"]={0xE0C61B},["Malicious"]={0x782A77},
["Infectious"]={0xB82EB5},["Virulent"]={0xF013EC,true},["Viscous"]={0x09470E},["Glutinous"]={0x1D8C27},
["Sticky"]={0x17E328,true},["Corrosive"]={0x4A5C0B},["Caustic"]={0x84A11D},["Acidic"]={0xC0F016,true},
["Excited"]={0xFF4545},["Energetic"]={0xE835C7},["Ecstatic"]={0xAF35E8,true},["Artic"]={0xADE0E0},
["Freezing"]={0x7BE3E3},["Shadow"]={0x595959},["Darkened"]={0x332E33},["Abyss"]={0x210821,true},
["Red"]={0xFF0000},["Yellow"]={0xFFDD00},["Blue"]={0x0022FF},["Green"]={0x009900},
["Black"]={0x575757},["White"]={0xFFFFFF},["Brown"]={0x5C350F},["Orange"]={0xFF9D00},
["Cyan"]={0x00FFE5},["Purple"]={0xAE00FF},["Gray"]={0xBABABA},["Lightblue"]={0x009DFF},
["Pink"]={0xFF80DF},["Limegreen"]={0x00FF08},["Magenta"]={0xFF00CC},["Lightgray"]={0xC9C9C9},
["Celebratory"]={0xFA0A6A},["Jaded"]={0xFA0A6A,true},["Chad"]={0x2157DB,true},["Hazardous"]={0xB06C28},
["Quantum"]={0x37C5DB},["Unusual"]={0x59A4BA},["Spatial"]={0x4C1BE0},["Mystical"]={0x46A722},
-- MagicBees
["Mystical"]={0xAFFFB7},["Sorcerous"]={0xEA9A9A},["Unusual"]={0x72D361},["Attuned"]={0x0086A8},
["Eldritch"]={0x8D75A0},["Esoteric"]={0x001099},["Mysterious"]={0x762BC2},["Arcane"]={0xD242DF,true},
["Charmed"]={0x48EEEC},["Enchanted"]={0x18E726},["Supernatural"]={0x005614,true},["Ethereal"]={0xBA3B3B},
["Watery"]={0x313C5E},["Earthen"]={0x78822D},["Firey"]={0xD35119},["Windy"]={0xFFFDBA},
["Pupil"]={0xFFFF00},["Scholarly"]={0x6E0000},["Savant"]={0xFFA042,true},["Aware"]={0x5E95B5},
["Spirit"]={0xB2964B},["Soul"]={0x7D591B,true},["Skulking"]={0x524827},["Ghastly"]={0xCCCCEE},
["Spidery"]={0x088888},["Smouldering"]={0xFFC747},["TCBrainy"]={0x83FF70},["BigBad"]={0xA9344B},
["TCChicken"]={0xFF0000},["TCBeef"]={0xB7B7B7},["TCPork"]={0xF1AEAC},["TCBatty"]={0x5B482B},
["Sheepish"]={0xF7F7F7},["Horse"]={0x906330},["Catty"]={0xECE684},["Timely"]={0xC6AF86},
["Lordly"]={0xC6AF86},["Doctoral"]={0xDDE5FC},["Infernal"]={0xFF1C1C},["Hateful"]={0xDB00DB},
["Spiteful"]={0x5FCC00,true},["Withering"]={0x5B5B5B,true},["Oblivion"]={0xD5C3E5},["Nameless"]={0x8CA7CB},
["Abandoned"]={0xC5CB8C},["Forlorn"]={0xCBA88C,true},["Draconic"]={0x9F56AD,true},["Iron"]={0x686868},
["Gold"]={0x684B01,true},["Copper"]={0x684B01},["Tin"]={0x3E596D},["Silver"]={0x747C81},
["Lead"]={0x96BFC4},["Aluminum"]={0xEDEDED},["Ardite"]={0x720000},["Cobalt"]={0x03265F},
["Manyullyn"]={0x481D6D,true},["Diamond"]={0x209581,true},["Emerald"]={0x005300,true},["Apatite"]={0x2EA7EC},
["Silicon"]={0xADA2A7},["Certus"]={0x93C7FF},["Fluix"]={0xFC639E},["Mutable"]={0xDBB24C},
["Transmuting"]={0xDBB24C},["Crumbling"]={0xDBB24C},["Invisible"]={0xFFCCFF},["TCAir"]={0xD9D636,true},
["TCFire"]={0xE50B0B,true},["TCWater"]={0x36CFD9,true},["TCEarth"]={0x005100,true},["TCOrder"]={0xAA32FC,true},
["TCChaos"]={0xCCCCCC,true},["TCEssentia"]={0xCCCCCC,true},["TCVis"]={0x004C99},["TCRejuvenating"]={0x91D0D9},
["TCEmpowering"]={0x96FFBC},["TCNexus"]={0x15AFAF,true},["TCFlux"]={0x91376A},["TCPure"]={0xE23F65},
["TCHungry"]={0xDCA5E2},["TCWispy"]={0x9CB8D5},["TCVoid"]={0x180A29},["EEMinium"]={0xAC0921},
["AMEssence"]={0x86BBC5},["AMQuintessence"]={0xE3A45B,true},["AMEarth"]={0xAA875E},["AMAir"]={0xD5EB9D},
["AMFire"]={0x93451E},["AMWater"]={0x3B7D8C},["AMLightning"]={0xEBEFA1},["AMPlant"]={0x49B549},
["AMIce"]={0x86BAC6},["AMArcane"]={0x76184D,true},["AMVortex"]={0x71BBE2},["AMWight"]={0xB50000},
["TEBlizzy"]={0x0073C4},["TEGelid"]={0x4AAFF7,true},["TEDante"]={0xF7AC4A},["TEPyro"]={0xFA930C,true},
["TEShocking"]={0xC5FF26},["TEAmped"]={0x8AFFFF,true},["TEGrounded"]={0xCEC1C1},["TERocking"]={0x980000,true},
["TEElectrum"]={0xEAF79E},["TEPlatinum"]={0x9EE7F7},["TENickel"]={0xB4C989},["TEInvar"]={0xCDE3A1},
["TEBronze"]={0xB56D07},["TECoal"]={0x2E2D2D},["TEDestabilized"]={0x5E0203},["TELux"]={0xF1FA89},
["TEWinsome"]={0x096B67},["TEEndearing"]={0x069E97,true},["TESignalus"]={0x5E0203,true},["TELumius"]={0xF1FA89,true},
["RSAFluxed"]={0x9E060D},["BotRooted"]={0x00A800},["BotBotanic"]={0x94C661},["BotBlossom"]={0xA4C193},
["BotFloral"]={0x29D81A},["BotVazbee"]={0xFF6B9C},["BotSomnolent"]={0x2978C6},["BotDreaming"]={0x123456},
["AESkystone"]={0x4B8381},
-- GregTech
["Clay"]={0xC8C8DA},["SlimeBall"]={0x4E9E55},["Peat"]={0x906237},["StickyResin"]={0x2E8F5B},
["Coal"]={0x666666},["Oil"]={0x4C4C4C,true},["Sandwich"]={0x32CD32},["Ash"]={0x1E1A18},
["Apatite"]={0xC1C1F6},["Fertilizer"]={0x7FCEF5},["Phosphorus"]={0xFFC826,true},["Tea"]={0x65D13A,true},
["Mica"]={0xFFC826,true},["Redstone"]={0x7D0F0F},["Lapis"]={0x1947D1},["CertusQuartz"]={0x57CFFB},
["FluixDust"]={0xA375FF},["Diamond"]={0xCCFFFF,true},["Ruby"]={0xE6005C},["Sapphire"]={0x0033CC},
["Olivine"]={0x248F24},["Emerald"]={0x248F24,true},["RedGarnet"]={0xBD4C4C,true},["YellowGarnet"]={0xA3A341,true},
["Firestone"]={0xC00000,true},["Prismatic"]={0x117777,true},["Copper"]={0xFF6600},["Tin"]={0xD4D4D4},
["Lead"]={0x666699},["Iron"]={0xDA9147},["Steel"]={0x808080},["Nickel"]={0x8585AD},
["Zinc"]={0xF0DEF0},["Silver"]={0xC2C2D6},["Cryolite"]={0xBFEFFF},["Gold"]={0xEBC633},
["Arsenic"]={0x736C52},["Aluminium"]={0xB8B8FF},["Titanium"]={0xCC99FF},["Glowstone"]={0xE5CA2A,true},
["Sunnarium"]={0xFFBC5E,true},["Chrome"]={0xEBA1EB},["Manganese"]={0xD5D5D5},["Tungsten"]={0x5C5C8A},
["Platinum"]={0xE6E6E6},["Iridium"]={0xDADADA,true},["Osmium"]={0x2B2BDA,true},["Salt"]={0xF0C8C8},
["Lithium"]={0xF0328C},["Electrotine"]={0x1E90FF},["Sulfur"]={0x6F6F01},["Indium"]={0xFFA9FF},
["Netherite"]={0x31291A,true},["Coolant"]={0x144F5A,true},["Energy"]={0xC11F1F,true},["Lapotron"]={0x6478FF,true},
["Pyrotheum"]={0xFFEBC4,true},["Cryotheum"]={0x2660FF,true},["explosive"]={0x7E270F,true},["RedAlloy"]={0xE60000},
["RedStoneAlloy"]={0xA50808},["ConductiveIron"]={0xCEADA3,true},["EnergeticAlloy"]={0xFF9933},["VibrantAlloy"]={0x86A12D,true},
["ElectricalSteel"]={0x787878},["DarkSteel"]={0x252525},["PulsatingIron"]={0x6DD284},["StainlessSteel"]={0xC8C8DC},
["Enderium"]={0x599087},["Bedrockium"]={0x0C0C0C},["ThaumiumDust"]={0x7A007A},["ThaumiumShard"]={0x9966FF,true},
["Amber"]={0xEE7700,true},["Quicksilver"]={0x7A007A,true},["SalisMundus"]={0xF7ADDE,true},["Tainted"]={0x904BB8,true},
["Mithril"]={0xF0E68C},["AstralSilver"]={0xAFEEEE},["Thauminite"]={0x2E2D79,true},["ShadowMetal"]={0x100322,true},
["Unstable"]={0xF0F0F0,true},["Caelestis"]={0xF0F0F0,true},["NetherStar"]={0x7A007A},["Essentia"]={0x7A007A},
["Drake"]={0x100322},["Uranium"]={0x19AF19},["Plutonium"]={0x570000},["Naquadah"]={0x003300,true},
["Naquadria"]={0x000000,true},["DOB"]={0x003300,true},["Thorium"]={0x005000},["Lutetium"]={0xE6FFE6,true},
["Americium"]={0xE6E6FF,true},["Neutronium"]={0xFFF0F0,true},["Naga"]={0x0D5A0D,true},["Lich"]={0xC5C5C5,true},
["Hydra"]={0x872836,true},["UrGhast"]={0xA7041C,true},["SnowQueen"]={0xD02001,true},["End Dust"]={0xCC00FA,true},
["Endium"]={0xA0FFFF,true},["Star Dust"]={0xFFFF00,true},["Ectoplasma"]={0xDCB0E5,true},["Arcane Shards"]={0x9010AD,true},
["Dragonessence"]={0xFFA12B,true},["Fireessence"]={0xD41238,true},["EndermanHead"]={0x161616,true},["Silverfisch"]={0xEE053D,true},
["Rune"]={0xE31010,true},["Walrus"]={0xD6D580,true},["Machinist"]={0x552582,true},["Space"]={0x003366},
["MeteoricIron"]={0x321928},["Desh"]={0x323232},["Ledox"]={0x0000CD,true},["CallistoIce"]={0x0074FF,true},
["Mytryl"]={0xDAA520,true},["Quantium"]={0x00FF00,true},["Oriharukon"]={0x228B22,true},["Infused Gold"]={0x80641E,true},
["MysteriousCrystal"]={0x3CB371,true},["BlackPlutonium"]={0x000000,true},["Trinium"]={0xB0E0E6,true},["Moon"]={0x373735,true},
["Mars"]={0x220D05,true},["Phobos"]={0x220D05},["Deimos"]={0x220D05},["Ceres"]={0x3CA5B7},
["Jupiter"]={0x734B2E,true},["IO"]={0x734B2E},["Europa"]={0x5982EA},["Ganymede"]={0x3D1B10},
["Callisto"]={0x0F333D},["Saturn"]={0xD2A472,true},["Enceladus"]={0xD2A472,true},["Titan"]={0xA0641B},
["Uranus"]={0x75C0C9,true},["Miranda"]={0x75C0C9},["Oberon"]={0x4A4033},["Neptune"]={0x334CFF,true},
["Proteus"]={0x334CFF},["Triton"]={0x334CFF},["Pluto"]={0x34271E,true},["Haumea"]={0x1C1413},
["MakeMake"]={0x301811},["Centauri"]={0x2F2A14,true},["aCentauri"]={0x2F2A14},["tCeti"]={0x46241A,true},
["tCetiE"]={0x2D561B,true},["SeaWeed"]={0xCBCBCB,true},["Barnarda"]={0x0D5A0D,true},["BarnardaC"]={0x0D5A0D},
["BarnardaE"]={0x0D5A0D},["BarnardaF"]={0x0D5A0D},["Vega"]={0x1A2036,true},["VegaB"]={0x1A2036},
["Mercury"]={0x4A4033,true},["Venus"]={0x4A4033,true},["CosmicNeutronium"]={0x484848,true},["InfinityCatalyst"]={0xFFFFFF,true},
["Infinity"]={0xFFFFFF,true},["Kevlar"]={0x2D542F,true},["Helium"]={0xFFA9FF,true},["Argon"]={0x89D9E1,true},
["Neon"]={0xFFC826,true},["Krypton"]={0x8A97B0,true},["Xenon"]={0x8A97B0,true},["Oxygen"]={0xFFFFFF,true},
["Oxygen"]={0xFFFFFF,true},["Nitrogen"]={0xFFC832,true},["Fluorine"]={0x86AFF0,true},["RareEarth"]={0x555643},
["Neodymium"]={0x555555},["Europium"]={0xDAA0E2},["Air"]={0xFFFF7E,true},["Fire"]={0xED3801,true},
["Water"]={0x0090FF,true},["Earth"]={0x008600,true},["Order"]={0x8A97B0,true},["Chaos"]={0x2E2E41,true},
["NetherShard"]={0xBE0135,true},["EnderShard"]={0x2E2E41,true},["UnknownLiquid"]={0x4333A5,true},["ManaSteel"]={0x4BAFFB},
["MMM"]={0x3F9B7B,true},["Elven"]={0xC72ED9},["TerraSteel"]={0x51BA00},["GAIASPIRIT"]={0x758997,true},
["JaegerMeister"]={0x05AD18,true},
}

local hashCache = {}

local function hashColor(name)
  local c = hashCache[name]
  if c then return c end
  local h = 5381
  for i = 1, #name do
    h = (h * 33 + name:byte(i)) % 0x1000000
  end
  local r = 96 + math.floor(h / 65536) % 140
  local g = 96 + math.floor(h / 256) % 140
  local b = 96 + h % 140
  c = r * 65536 + g * 256 + b
  hashCache[name] = c
  return c
end

-- Display color for a species (authentic if known, hashed otherwise)
function colors.of(name)
  local e = colors.PALETTE[name]
  if e then return e[1] end
  return hashColor(tostring(name))
end

-- True if the species renders with an enchantment glint in-game
function colors.glint(name)
  local e = colors.PALETTE[name]
  return (e and e[2]) or false
end

-- True if we have the authentic color (vs a hashed stand-in)
function colors.known(name)
  return colors.PALETTE[name] ~= nil
end

return colors
