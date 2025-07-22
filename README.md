# Archipelago Integration for Oblivion Remastered

A UE4SS and .esp mod that randomizes Oblivion's 15 Daedric shrine quests for [Archipelago multiworld](https://archipelago.gg/). 

Players receive shrine unlock tokens to access quests, then send completion status back to the multiworld when shrine quests are completed.

[Download Latest Release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest)

# Mod Manager Installation

MO2 now has support for ue4ss mods. To install with MO2, follow these steps:

1) Download the Dev Branch of MO2.
[This can be acquired on the MO2 Discord](https://discord.gg/Jjprnb5rDJ)

2) [UE4SS for OblivionRemastered](https://www.nexusmods.com/oblivionremastered/mods/32) and [OBSE64](https://www.nexusmods.com/oblivionremastered/mods/282) both **need to be installed MANUALLY** -- They do not work as MO2 mods directly.

**Note:** 
For the **UE4SS mod**, do not install the included dwmapi.dll file. 
For the **OBSE64 mod**, you only need the obse64_xxx_xxx.dll and obse64_loader.exe files.

Your folder should look like this:
```
Oblivion Remastered
|--OblivionRemastered
|--|--Binaries
|--|--|--Win64
|--|--|--|--UE4SS
|--|--|--|--obse64__xxx_xxx.dll
|--|--|--|--obse64_loader.exe
```
Image example: 

3) Install the following mods into your mod manager:
[OBSE64 ue4ss Loader](https://www.nexusmods.com/oblivionremastered/mods/3421).
[Runtime EditorIDs](https://www.nexusmods.com/oblivionremastered/mods/1331)
[Address Library for OBSE Plugins](https://www.nexusmods.com/oblivionremastered/mods/4475)

4) [Download the latest release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest) and manually install (Ctrl+M in MO2) both the Archipelago.zip and ArchipelagoBridge.zip into MO2. You should see the ArchipelagoBridge mod under the UE4SS Mods tab, and the Archipelago_Oblivion.esp mod under the Plugins tab -- be sure it is enabled.

Image example:

# How to use

For Archipelago instructions, see https://archipelago.gg/tutorial/

1) Generate a new Archipelago multiworld.
2) Launch the Oblivion Remastered Client from the ArchipelagoLauncher.exe.
3) Connect to your server.
4) Once connected, you can launch Oblivion Remastered through your mod manager and start playing.

The mod is best experienced by loading a save from just before leaving the sewers, or you can start a new game.

# Troubleshooting: 

This is Oblivion, so we have some recovery options in the event of a crash, untimely death, or other issues.
The best advice is to Quicksave(F5) any time you receive a new item from the multiworld.

## Resending Items
```
Messsage "Resend X"
```
where X is the number of items you need re-sent.
You can check the bridge status file to see what items you have received.
It will look like this:
```
Item1,Item2,Item3,Item4,Item5
```
If you wanted to resend items 3 - 5, you would type:
```
Messsage "Resend 3"
```
NOTE: Progressive shop items are received in a set of 3, so if you received a Progressive Shop Stock, add 3 to the number you want to resend.

If you need to do a full reset, you can type the following command in the console:

```
Messsage "APReset"
```

Then reconnect in the Oblivion Remastered Client. The game will receive all previous items and reinitialize world state.