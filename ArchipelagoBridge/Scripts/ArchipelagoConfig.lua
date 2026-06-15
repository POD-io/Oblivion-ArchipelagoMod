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

        -- Currency
        ["Gold"] = "F",
        ["Gold (10)"] = "F",  -- Filler item: 10 gold
        
        -- Basic Filler Items
        ["Lockpick"] = "0000000A",
        ["Repair Hammer"] = "0000000C",
        ["Steel Arrows"] = "000229C1",
        ["Torch"] = "0002CF9F",
        ["Common Soul Gem"] = "000382D6",

        -- Special Arrows
        ["Fire Arrow Bundle"] = "EncArrow2SteelFireDamage",
        
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
        ["Lesser Soul Gem"] = "00382D3",
        ["Lettuce"] = "00023D69",
        ["Yarn"] = "00033681",
        ["Black Soul Gem"] = "00000192",
        ["Clavicus Gold"] = "F",
        ["Wolf Pelt"] = "000228E2",
        ["Troll Fat"] = "00026B5C",
        ["Nightshade"] = "00033688",
        ["Ectoplasm"] = "0001EBFE",
        ["Lion Pelt"] = "000228E4",
        ["Greater Soulgem Package"] = "000382DA",
        
        -- Unique Items
        -- WEAPONS
        ["Akavari Sunderblade"] = "000CA154",
        ["Captain Kordan's Saber"] = "000CA158",
        ["Akavari Warblade"] = "000CA155",
        ["Truncheon of Submission"] = "000CA157",
        ["Battleaxe of Hatred"] = "000CA152",
        ["Destarine's Cleaver"] = "000CA159",
        ["Bow of Infliction"] = "000CA156",
        ["Redwave"] = "00095A39",
        ["Calliben's Grim Retort"] = "000CB6F3",
        ["Frostwyrm Bow"] = "000C55E4",
        
        -- SHIELDS
        ["Aegis of the Apocalypse"] = "000CA117",
        ["Birthright of Astalon"] = "000CA110",
        ["Dondoran's Juggernaut"] = "000CA10F",
        
        -- GAUNTLETS
        ["Fists of the Drunkard"] = "000CA11A",
        ["Gauntlets of Gluttony"] = "000CA11C",
        ["Hands of the Atronach"] = "000CA118",
        ["Rasheda's Special"] = "000CA114",
        
        -- HELMETS
        ["Fin Gleam"] = "00082DD8",
        ["Helm of the Deep Delver"] = "000CA119",
        ["Helm of Ferocity"] = "000CA11B",
        ["Tower of the Nine"] = "000CA116",
        
        -- BOOTS
        ["Boots of the Swift Merchant"] = "000CA111",
        ["Quicksilver Boots"] = "000CA113",
        ["Nistor's Boots"] = "000CA12B",
        ["Boots of Springheel Jak"] = "000148D4",
        
        -- GREAVES
        ["Monkeypants"] = "000CA112",
        
        -- CLOTHING
        ["Cowl of the Druid"] = "000CA121",
        ["Mantle of the Woodsman"] = "000CA129",
        ["Imperial Breeches"] = "000CA125",
        ["Apron of the Master Artisan"] = "000CA122",
        ["Robe of Creativity"] = "000CA127",
        ["Vest of the Bard"] = "000CA123",
        
        -- AMULETS
        ["Circlet of Omnipotence"] = "00088FED",
        
        -- RINGS
        ["Ring of Transmutation"] = "000CA126",
        ["Ring of Wortcraft"] = "000CA128",
        ["Spectre Ring"] = "000CA12A",
        ["Ring of the Gray"] = "0000CCC8",
        
        -- STAVES
        ["Apotheosis"] = "000CA153"
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

    -- Birthsign (Doomstone) region mapping for region-gated completion validation
    doomstoneRegions = {
        ["Tower Stone"] = "Heartlands",
        ["Steed Stone"] = "Heartlands",
        ["Warrior Stone"] = "West Weald",
        ["Apprentice Stone"] = "West Weald",
        ["Atronach Stone"] = "Colovian Highlands",
        ["Lord Stone"] = "Colovian Highlands",
        ["Lady Stone"] = "Gold Coast",
        ["Thief Stone"] = "Great Forest",
        ["Shadow Stone"] = "Nibenay Basin",
        ["Mage Stone"] = "Nibenay Basin",
        ["Lover Stone"] = "Nibenay Valley",
        ["Ritual Stone"] = "Blackwood",
        ["Serpent Stone"] = "Blackwood",
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
        ["Clavicus Vile Shrine Token"] = {{"Clavicus Gold", 500}},
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
    
    -- Sidequest location name to game variable mapping
    -- These map location check names to their corresponding APSidequest global variables
    sidequestMappings = {
        ["Acquire Akaviri Sunderblade"] = "APSQAkaviriSunderblade",
        ["Acquire Captain Kordan's Saber"] = "APSQCaptainKordanSaber",
        ["Acquire Battleaxe of Hatred"] = "APSQBattleaxeOfHatred",
        ["Acquire Akavari Warblade"] = "APSQAkavariWarblade",
        ["Acquire Truncheon of Submission"] = "APSQTruncheonOfSubmission",
        ["Acquire Destarine's Cleaver"] = "APSQDestarinesCleaver",
        ["Acquire Bow of Infliction"] = "APSQBowOfInfliction",
        ["Acquire Aegis of the Apocalypse"] = "APSQAegisOfTheApocalypse",
        ["Acquire Helm of the Deep Delver"] = "APSQHelmOfTheDeepDelver",
        ["Acquire Monkeypants"] = "APSQMonkeypants",
        ["Obtain a Varla Stone"] = "APSQVarla",
        ["Obtain Fin Gleam"] = "APSQFinGleam",
        ["Visit Dive Rock"] = "APSQDiveRock",
        ["Obtain Bands of Kwang Lao"] = "APSQBandsOfKwangLao",
        ["Visit an Ayleid Well"] = "APSQAyleidWell"
    },

    -- Mapping from dungeon names to their ShowMap marker IDs
    dungeonMapMarkers = {
        ["Amelion Tomb"] = "AmelionTombMapmarker",
        ["Atatar"] = "AtatarMapmarker",
        ["Bloodrun Cave"] = "BloodrunCaveMapmarker",
        ["Fieldhouse Cave"] = "FieldhouseCaveMapmarker",
        ["Fort Doublecross"] = "FortDoublecrossMapmarker",
        ["Fort Nomore"] = "FortNomoreMapmarker",
        ["Fort Redman"] = "FortRedmanMapmarker",
        ["Fort Redwater"] = "FortRedwaterMapmarker",
        ["Fort Teleman"] = "FortTelemanMapmarker",
        ["Kindred Cave"] = "KindredCaveMapmarker",
        ["Onyx Caverns"] = "OnyxCavernsMapmarker",
        ["Redwater Slough"] = "RedwaterSloughMapmarkerREF",
        ["Reedstand Cave"] = "ReedstandCaveMapmarker",
        ["Rockmilk Cave"] = "RockmilkCaveMapmarker",
        ["Telepe"] = "TelepeMapmarker",
        ["Undertow Cavern"] = "UndertowCavernMapmarker",
        ["Veyond"] = "VeyondMapmarker",
        ["Welke"] = "WelkeMapmarker",
        ["Black Rock Caverns"] = "BlackRockCavernsMapmarker",
        ["Broken Promises Cave"] = "BrokenPromisesCaveMapmarker",
        ["Fort Dirich"] = "FortDirichMapmarker",
        ["Fort Hastrel"] = "FortHastrelMapmarker",
        ["Fort Linchal"] = "FortLinchalMapmarker",
        ["Fort Rayles"] = "FortRaylesMapmarker",
        ["Fort Wariel"] = "FortWarielMapmarker",
        ["Hrotanda Vale"] = "HrotandaValeMapmarker",
        ["Lindai"] = "LindaiMapMarker",
        ["Lipsand Tarn"] = "LipsandTarnMapmarker",
        ["Nonungalo"] = "NonungaloMapmarker",
        ["Rock Bottom Caverns"] = "RockBottomCavernsMapmarker",
        ["Talwinque"] = "TalwinqueMapmarker",
        ["Trumbe"] = "TrumbeMapmarker",
        ["Varondo"] = "VarondoMapmarker",
        ["Wind Cave"] = "WindCaveMapmarker",
        ["Bleak Mine"] = "BleakMineMapmarker",
        ["Garlas Agea"] = "GarlasAgeaMapmaker",
        ["Niryastare"] = "NiryastareMapmarker",
        ["Smoke Hole Cave"] = "SmokeHoleCaveMapmarker",
        ["Ceyatatar"] = "CeyatatarMapmarker",
        ["Charcoal Cave"] = "CharcoalCaveMapmarker",
        ["Crumbling Mine"] = "CrumblingMineMapmarker",
        ["Elenglynn"] = "ElenglynnMapmarker",
        ["Felgageldt Cave"] = "FelgageldtCaveMapmarker",
        ["Fingerbowl Cave"] = "FingerbowlCaveMapmarker",
        ["Fort Ash"] = "FortAshMapmarker",
        ["Fort Carmala"] = "FortCarmalaMapmarker",
        ["Fort Coldcorn"] = "FortColdcornMapmarker",
        ["Fort Wooden Hand"] = "FortWoodenHandMapmarker",
        ["Greenmead Cave"] = "GreenmeadCaveMapmarker",
        ["Moranda"] = "MorandaMapmarker",
        ["Moss Rock Cavern"] = "MossRockCavernMapmarker",
        ["Narfinsel"] = "NarfinselMapmarker",
        ["Outlaw Endre's Cave"] = "OutlawEndresCaveMapmarker",
        ["Piukanda"] = "PiukandaMapmarker",
        ["Robber's Glen Cave"] = "RobbersGlenCaveMapmarker",
        ["Sardavar Leed"] = "SardavarLeedMapmarker",
        ["Serpent Hollow Cave"] = "SerpentHollowCaveMapmarker",
        ["Underpall Cave"] = "UnderpallCaveMapmarker",
        ["Unmarked Cave"] = "UnmarkedCave01Mapmarker",
        ["Vindasel"] = "VindaselMapmarker",
        ["Wendir"] = "WendirMapmarker",
        ["Wenyandawik"] = "WenyandawikMapmarker",
        ["Belda"] = "BeldaMapmarker",
        ["Culotte"] = "CulotteMapmarker",
        ["Dzonot Cave"] = "DzonotCaveMapmarker",
        ["Fanacasecul"] = "FanacaseculMapmarker",
        ["Fatback Cave"] = "FatbackCaveMapmarker",
        ["Fort Alessia"] = "FortAlessiaMapmarker",
        ["Fort Chalman"] = "FortChalmanMapmarker",
        ["Fort Empire"] = "FortEmpireMapmarker",
        ["Fort Homestead"] = "FortHomesteadMapmarker",
        ["Fort Magia"] = "FortMagiaMapmarker",
        ["Fort Nikel"] = "FortNikelMapmarker",
        ["Fort Urasek"] = "FortUrasekMapmarker",
        ["Fort Variela"] = "FortVarielaMapmarker",
        ["Fort Virtue"] = "FortVirtueMapmarker",
        ["Memorial Cave"] = "MemorialCaveMapmarker",
        ["Nagastani"] = "NagastaniMapmaker",
        ["Sercen"] = "SercenMapmarker",
        ["Sideways Cave"] = "SidewaysCaveMapmarker",
        ["Sinkhole Cave"] = "SinkholeCaveMapmarker",
        ["Veyond Cave"] = "VeryondsCaveMapmarker",
        ["Vilverin"] = "VilverinMapmarker01",
        ["Capstone Cave"] = "CapstoneCaveMapmarker",
        ["Fort Horunn"] = "FortHorunnMapmarker",
        ["Ninendava"] = "NinendavaMapmarker",
        ["Rielle"] = "RielleMapmarker",
        ["Silver Tooth Cave"] = "SilverToothCaveMapmarker",
        ["Arrowshaft Cavern"] = "ArrowshaftCavernMapmarker",
        ["Bramblepoint Cave"] = "BramblepointCaveMapmarker",
        ["Cracked Wood Cave"] = "CrackedWoodCaveMapmarker",
        ["Crayfish Cave"] = "CrayfishCaveMapmarker",
        ["Fort Cedrian"] = "FortCedrianMapmarker",
        ["Fort Cuptor"] = "FortCuptorMapmarker",
        ["Fort Entius"] = "FortEntiusMapmarker",
        ["Fort Facian"] = "FortFacianMapmarker",
        ["Fort Naso"] = "FortNasoMapmarker",
        ["Hame"] = "HameMapmarker",
        ["Lost Boy Cavern"] = "LostBoyCavernsMapmarker",
        ["Mackamentain"] = "MackamentainMapmarker",
        ["Nornal"] = "NornalMapmarker",
        ["Ondo"] = "OndoMapmarker",
        ["Rickety Mine"] = "RicketyMineMapmarker",
        ["Sage Glen Hollow"] = "SageGlenHollowMapmarker",
        ["Timberscar Hollow"] = "TimberscarHollowMapmarker",
        ["Wendelbek"] = "WendelbekMapmarker",
        ["Wenderbek Cave"] = "WenderbekCaveMapmarker",
        ["Anutwyll"] = "AnutwyllMapmarker",
        ["Bawn"] = "BawnMapmarker",
        ["Bloodmayne Cave"] = "BloodmayneCaveMapmarker",
        ["Fort Gold-Throat"] = "FortGoldThroatMapmarker",
        ["Morahame"] = "MorahameMapmarker",
        ["Nenalata"] = "NenalataMapmarker",
        ["Dark Fissure"] = "DarkFissureMapmarker",
        ["Fanacas"] = "FanacasMapmarker",
        ["Fort Scinia"] = "FortSciniaMapmarker",
        ["Kemen"] = "KemenMapmarker",
        ["Bloodcrust Cavern"] = "BloodcrustMapmarker",
        ["Cursed Mine"] = "CursedMineMapmarker",
        ["Dasek Moor"] = "DasekMoorMapmarker",
        ["Fort Black Boot"] = "FortBlackBootMapmarker",
        ["Fort Istirus"] = "FortIstirusMapmarker",
        ["Fort Vlastarus"] = "FortVlastarusMapmarker",
        ["Fyrelight Cave"] = "FyrelightCaveMapmarker",
        ["Howling Cave"] = "HowlingCaveMapmarker",
        ["Nornalhorst"] = "NornalhorstMapmarker"
    }
}

return config 