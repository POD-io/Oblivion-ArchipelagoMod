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
        
        -- Arena Rank Tokens
        ["APArenaPitDogUnlock"] = "APArenaPitDogUnlock",
        ["APArenaBrawlerUnlock"] = "APArenaBrawlerUnlock",
        ["APArenaBloodletterUnlock"] = "APArenaBloodletterUnlock",
        ["APArenaMyrmidonUnlock"] = "APArenaMyrmidonUnlock",
        ["APArenaWarriorUnlock"] = "APArenaWarriorUnlock",
        ["APArenaGladiatorUnlock"] = "APArenaGladiatorUnlock",
        ["APArenaHeroUnlock"] = "APArenaHeroUnlock",
        
        -- Potions
        ["Strong Potion of Healing"] = "PotionRestoreHealthS",
        ["Strong Potion of Speed"] = "PotionFortifySpeedS",
        ["Skooma"] = "PotionSkooma",
        
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
        ["Mace of Molag Bal"] = "DAMolagBalMace",
        
        -- Oblivion Gate Key
        ["Oblivion Gate Key"] = "APOblivionGateKey",
        
        
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
        
        -- Damage Scrolls
        ["Scroll of Fire Storm"] = "ScrollStandardFireDamageArea4Expert",
        ["Scroll of Flame Tempest"] = "ScrollStandardFireDamageArea5Master",
        ["Scroll of Ice Storm"] = "ScrollStandardFrostDamageArea4Expert",
        ["Scroll of Blizzard"] = "ScrollStandardFrostDamageArea5Master",
        ["Scroll of Lightning Storm"] = "ScrollStandardShockDamageArea5Master",
        ["Scroll of Shocking Burst"] = "ScrollStandardShockDamageArea3Journeyman",
        
        -- Protection Scrolls
        ["Scroll of Fire Shield"] = "ScrollStandardFireShield4Expert",
        ["Scroll of Frost Shield"] = "ScrollStandardFrostShield3Journeyman",
        ["Scroll of Lightning Wall"] = "ScrollStandardShockShield4Expert",
        ["Scroll of Aegis"] = "ScrollStandardShield5Master",
        
        -- Fortify Scrolls
        ["Scroll of Greater Fortify Health"] = "ScrollStandardFortifyHealth2Expert",
        ["Scroll of Greater Fortify Magicka"] = "ScrollStandardFortifyMagicka2Expert",
        
        
        -- Additional Helpful Scrolls
        ["Scroll of Invisibility"] = "ScrollStandardInvisibility4Expert",
        ["Scroll of Telekinesis"] = "ScrollStandardTelekinesis3Expert",
        ["Scroll of Unlock"] = "ScrollStandardOpen4Expert",
        ["Scroll of Light"] = "ScrollStandardLight4Expert",
        ["Scroll of Water Walking"] = "ScrollStandardWaterWalking3Expert",
        ["Scroll of Beast of Burden"] = "ScrollStandardFeather5Master",
        
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
    
    -- Merchant chest references for progressive shop stock
    -- These are all the supported Innkeeper chests in the game
    merchantChests = {
        "MerchantsInnVelusChest",
        "LuthorBroadPublicanChest", 
        "MoslinPublicanChestRef",
        "OakandCrosierTalasmaChest",
        "GreyMareEmfridChest",
        "FlowingBowlMaenlornChest",
        "CountsArmsWilburChest",
        "SilverhomeGilgondorinChest",
        "JerallViewHafidChest",
        "BridgeInnMarianaChest",
        "ThreeSistersInnShuvariChest",
        "WestWealdInnErinaChest",
        "KingandQueenTavernLeyChest",
        "FaregylInnAbhukiChest",
        "WitseidutseiChestFood",
        "WilletMerchantChestRef",
        "AugustaMerchantChest",
        "FlavinusMerchantChest",
        "FiveClawsWitseidutseiChest",
        "ManheimDrinkCHest",
        "TwoSistersLodgeMogChest",
        "BrinaCrossMerchChest",
        "RoxeyDrinks",
        "AndreasAlcoholChest",
        "OlavsTapandTackOlavChest",
        "NewlandLodgeDerveraChest",
        "KirstenDrinks",
        "ImperialBridgeInnDavelaChest",
        "GottshawInnForochChest",
        "WawnetVendorChest"
    },
    
    -- Shrine offering mappings for free offerings mode
    -- When a shrine token is received, these items are automatically added to help with shrine quests
    shrineOfferings = {
        ["Azura Shrine Token"] = {{"Glow Dust", 1}},
        ["Boethia Shrine Token"] = {{"Daedra Heart", 1}},
        ["Namira Shrine Token"] = {{"Cheap Wine", 5}},
        ["Sanguine Shrine Token"] = {{"Cyrodiilic Brandy", 1}},
        ["Sheogorath Shrine Token"] = {{"Lesser Soul Gem", 1}, {"Lettuce", 1}, {"Yarn", 1}},
        ["Vaermina Shrine Token"] = {{"Black Soul Gem", 1}},
        ["Clavicus Vile Shrine Token"] = {{"Gold", 500}},
        ["Hircine Shrine Token"] = {{"Wolf Pelt", 1}},
        ["Malacath Shrine Token"] = {{"Troll Fat", 1}},
        ["Mephala Shrine Token"] = {{"Nightshade", 1}},
        ["Meridia Shrine Token"] = {{"Ectoplasm", 1}},
        ["Molag Bal Shrine Token"] = {{"Lion Pelt", 1}}
    },
    
    -- Shrine name to lock variable mapping for initialization
    shrineLockMapping = {
        ["Azura"] = "APAzuraLocked",
        ["Boethia"] = "APBoethiaLocked",
        ["Clavicus Vile"] = "APClavicusLocked",
        ["Hermaeus Mora"] = "APHermaeusLocked",
        ["Hircine"] = "APHircineLocked",
        ["Malacath"] = "APMalacathLocked",
        ["Mephala"] = "APMephalaLocked",
        ["Meridia"] = "APMeridiaLocked",
        ["Molag Bal"] = "APMolagBalLocked",
        ["Namira"] = "APNamiraLocked",
        ["Nocturnal"] = "APNocturnalLocked",
        ["Peryite"] = "APPeryiteLocked",
        ["Sanguine"] = "APSanguineLocked",
        ["Sheogorath"] = "APSheogorathLocked",
        ["Vaermina"] = "APVaerminaLocked"
    },
    
    -- Gate vision messages
    gateVisionMessages = {
        "The Sight awakens. All Oblivion Gates are revealed to you.",
        "You can now see every Oblivion Gate scorched across Tamriel.",
        "The fires of Oblivion spread through the land, and you know where they burn."
    },
    
    -- Shop stock messages
    shopStockMessages = {
        "New items have arrived at the inn, sent from distant shores.",
        "The innkeeper's stock has grown - goods traded from another realm.",
        "Supplies from far-off lands are now for sale at the inn."
    },
    
    -- Arena unlock messages
    arenaMessages = {
        "Your reputation grows. More challengers await you in the Arena.",
        "You may now compete in higher ranked Arena battles.",
        "The Arena beckons - new matches have been unlocked.",
        "You are now eligible for more Arena battles.",
        "The next tier of Arena combatants await you.",
        "You can now take on stronger Arena challengers.",
        "Additional Arena matches are now unlocked.",
        "Arena access expanded. New fights unlocked."
    }
}

return config 