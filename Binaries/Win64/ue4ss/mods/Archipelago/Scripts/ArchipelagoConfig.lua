local config = {
    -- Archipelago Item Name to EDID mappings
    -- These map the item names received from Archipelago server to their Editor IDs in Oblivion
    
    itemMappings = {
        -- Daedric Shrine Unlock Tokens
        ["Azura Shrine Token"] = "APAzuraUnlockToken",
        ["Boethia Shrine Token"] = "APBoethiaUnlockToken", 
        ["Clavicus Vile Shrine Token"] = "APClavicusVileUnlockToken",
        ["Hermaeus Mora Shrine Token"] = "APHermaeusMoraUnlockToken",
        ["Hircine Shrine Token"] = "APHircineUnlockToken",
        ["Malacath Shrine Token"] = "APMalacathUnlockToken",
        ["Mephala Shrine Token"] = "APMephalaUnlockToken",
        ["Meridia Shrine Token"] = "APMeridiaUnlockToken",
        ["Molag Bal Shrine Token"] = "APMolagBalUnlockToken",
        ["Namira Shrine Token"] = "APNamiraUnlockToken",
        ["Nocturnal Shrine Token"] = "APNocturnalUnlockToken",
        ["Peryite Shrine Token"] = "APPeryiteUnlockToken",
        ["Sanguine Shrine Token"] = "APSanguineUnlockToken",
        ["Sheogorath Shrine Token"] = "APSheogorathUnlockToken",
        ["Vaermina Shrine Token"] = "APVaerminaUnlockToken",
        
        -- Potions (3-packs)
        ["PotionRestoreHealthS"] = "PotionRestoreHealthS",
        ["PotionSkooma"] = "PotionSkooma",
        ["PotionFortifySpeedS"] = "PotionFortifySpeedS",
        
        -- Daedric Artifacts/Rewards
        ["Azura's Star"] = "AzurasStar",
        ["Goldbrand"] = "DAGoldBrand",
        ["Masque of Clavicus Vile"] = "DAClavicusMasque",
        ["Oghma Infinium"] = "DAOghmaInfinium",
        ["Savior's Hide"] = "DASaviorsHide",
        ["Volendrung"] = "DAVolendrung",
        ["Ebony Blade"] = "DAEbonyBlade",
        ["Ring of Khajiiti"] = "DARingKhajiiti",
        ["Ring of Namira"] = "DARingNamira",
        ["Skeleton Key"] = "DASkeletonKey",
        ["Spellbreaker"] = "DASpellbreakerShield",
        ["Sanguine Rose"] = "DASanguineRose",
        ["Wabbajack"] = "DAWabbajack01",
        ["Skull of Corruption"] = "DASkullCorruption",
        
        -- Summoning Scrolls
        ["Scroll of Frost Atronach"] = "ScrollStandardSummonAtronachFrostExpert",
        ["Scroll of Fire Atronach"] = "ScrollStandardSummonAtronachFlameJourneyman", 
        ["Scroll of Storm Atronach"] = "ScrollStandardSummonAtronachStormMaster",
        ["Scroll of Dremora Lord"] = "ScrollStandardSummonDremoraLordMaster",
        ["Scroll of Lich"] = "ScrollStandardSummonLichMaster",
        ["Scroll of Xivilai"] = "ScrollStandardSummonXivilaiMaster",
        ["Scroll of Dremora"] = "ScrollStandardSummonDremoraJourneyman",
        
        -- Bound Weapon Scrolls
        ["Scroll of Bound Sword"] = "ScrollStandardBoundSwordExpert",
        ["Scroll of Bound Bow"] = "ScrollStandardBoundBowJourneyman",
        ["Scroll of Bound Axe"] = "ScrollStandardBoundAxeApprentice",
        ["Scroll of Bound Dagger"] = "ScrollStandardBoundDaggerNovice",
        ["Scroll of Bound Mace"] = "ScrollStandardBoundMaceJourneyman",
        ["Scroll of Bound Shield"] = "ScrollStandardBoundShieldExpert",
        
        -- Bound Armor Scrolls
        ["Scroll of Bound Cuirass"] = "ScrollStandardBoundCuirassJourneyman",
        ["Scroll of Bound Boots"] = "ScrollStandardBoundBootsNovice",
        ["Scroll of Bound Gauntlets"] = "ScrollStandardBoundGauntletsNovice",
        ["Scroll of Bound Helmet"] = "ScrollStandardBoundHelmetNovice",
        ["Scroll of Bound Greaves"] = "ScrollStandardBoundGreavesApprentice",
        
        -- Powerful Damage Scrolls
        ["Scroll of Fire Storm"] = "ScrollStandardFireDamageArea4Expert",
        ["Scroll of Flame Tempest"] = "ScrollStandardFireDamageArea5Master",
        ["Scroll of Ice Storm"] = "ScrollStandardFrostDamageArea4Expert",
        ["Scroll of Blizzard"] = "ScrollStandardFrostDamageArea5Master",
        ["Scroll of Lightning Storm"] = "ScrollStandardShockDamageArea5Master",
        ["Scroll of Shocking Burst"] = "ScrollStandardShockDamageArea3Journeyman",
        
        -- Powerful Shield/Protection Scrolls
        ["Scroll of Fire Shield"] = "ScrollStandardFireShield4Expert",
        ["Scroll of Frost Shield"] = "ScrollStandardFrostShield3Journeyman",
        ["Scroll of Lightning Wall"] = "ScrollStandardShockShield4Expert",
        ["Scroll of Aegis"] = "ScrollStandardShield5Master",
        
        -- Powerful Fortify Scrolls
        ["Scroll of Greater Fortify Health"] = "ScrollStandardFortifyHealth2Expert",
        ["Scroll of Greater Fortify Magicka"] = "ScrollStandardFortifyMagicka2Expert",
        ["Scroll of Beast of Burden"] = "ScrollStandardFeather5Master",
        
        -- Additional Helpful Scrolls
        ["Scroll of Invisibility"] = "ScrollStandardInvisibilitySelf2Apprentice",
        ["Scroll of Telekinesis"] = "ScrollStandardTelekinesis4Expert",
        ["Scroll of Unlock"] = "ScrollStandardOpen4Expert",
        ["Scroll of Restore Health"] = "ScrollStandardRestoreHealth4Expert",
        ["Scroll of Light"] = "ScrollStandardLight4Expert",
        ["Scroll of Water Walking"] = "ScrollStandardWaterWalking4Expert",
        ["Scroll of Feather"] = "ScrollStandardFeather2Apprentice",
        
        -- Shrine Offering Items (added automatically with shrine tokens if free_offerings is on)
        ["Glow Dust"] = "0001EBE8",
        ["Daedra Heart"] = "0001EC8F", 
        ["Cheap Wine"] = "00037F7F",
        ["Cyrodiilic Brandy"] = "00033569",
        ["Lesser Soul Gem"] = "00025205",
        ["Lettuce"] = "00023D69",
        ["Yarn"] = "00033681",
        ["Black Soul Gem"] = "00000192",
        ["Gold"] = "F",
        ["Wolf Pelt"] = "000228E2",
        ["Troll Fat"] = "00026B5C",
        ["Nightshade"] = "00033688",
        ["Ectoplasm"] = "0001EBFE",
        ["Lion Pelt"] = "000228E4"
    },
    
    -- Unlock token to completion token mapping (for removal when quest completes)
    unlockToCompletionMapping = {
        ["APAzuraCompletionToken"] = "APAzuraUnlockToken",
        ["APBoethiaCompletionToken"] = "APBoethiaUnlockToken",
        ["APClavicusVileCompletionToken"] = "APClavicusVileUnlockToken",
        ["APHermaeusMoraCompletionToken"] = "APHermaeusMoraUnlockToken",
        ["APHircineCompletionToken"] = "APHircineUnlockToken",
        ["APMalacathCompletionToken"] = "APMalacathUnlockToken",
        ["APMephalaCompletionToken"] = "APMephalaUnlockToken",
        ["APMeridiaCompletionToken"] = "APMeridiaUnlockToken",
        ["APMolagBalCompletionToken"] = "APMolagBalUnlockToken",
        ["APNamiraCompletionToken"] = "APNamiraUnlockToken",
        ["APNocturnalCompletionToken"] = "APNocturnalUnlockToken",
        ["APPeryiteCompletionToken"] = "APPeryiteUnlockToken",
        ["APSanguineCompletionToken"] = "APSanguineUnlockToken",
        ["APSheogorathCompletionToken"] = "APSheogorathUnlockToken",
        ["APVaerminaCompletionToken"] = "APVaerminaUnlockToken",
    },
    
    -- Debug settings
    enableDebugLogging = true,
}

return config 