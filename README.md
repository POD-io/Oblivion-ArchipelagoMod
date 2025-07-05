# Archipelago Integration for Oblivion Remastered

A UE4SS and .esp mod that randomizes Oblivion's 15 Daedric shrine quests for [Archipelago multiworld](https://archipelago.gg/). 

Players receive shrine unlock tokens to access quests, then send completion status back to the multiworld when shrine quests are completed.

[Download Latest Release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest)

# Mod Manager Installation

MO2 now has support for ue4ss mods. To install with MO2, follow these steps:

1) Download the Dev Branch of MO2.
[This can be acquired on the MO2 Discord](https://discord.gg/Jjprnb5rDJ)
2) [UE4SS for OblivionRemastered](https://www.nexusmods.com/oblivionremastered/mods/32) and [OBSE64](https://www.nexusmods.com/oblivionremastered/mods/282) both **<ins>need to be installed manually</ins>** -- They do not work as MO2 mods directly.

**Note:** <br>
For the **UE4SS mod**, do not install the included dwmapi.dll file.<br>
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
Image example:<br>
![MO2-3](https://github.com/user-attachments/assets/a2aaa4ff-4668-4b8c-ab2d-d606f195bc87)

3) Install the following mods into your mod manager:<br>
[OBSE64 ue4ss Loader](https://www.nexusmods.com/oblivionremastered/mods/3421)<br>
[Runtime EditorIDs](https://www.nexusmods.com/oblivionremastered/mods/1331)<br>
[Address Library for OBSE Plugins](https://www.nexusmods.com/oblivionremastered/mods/4475)

4) [Download the latest release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest) and manually install (Ctrl+M in MO2) both the Archipelago.zip and ArchipelagoBridge.zip into MO2. You should see the ArchipelagoBridge mod under the **UE4SS Mods** tab, and the Archipelago_Oblivion.esp mod under the **Plugins** tab -- be sure it is enabled.

Image example:<br>
![MO2-1](https://github.com/user-attachments/assets/3225988f-9283-46cc-ae69-28308b020b39)

Installation of the mod and pre-requesites is now complete. Please confirm the following 5 mods are installed:<br>

![MO2-2](https://github.com/user-attachments/assets/41ab12a8-9b7f-4d7f-902d-31af8cae029a)

# How to use

For Archipelago instructions, see https://archipelago.gg/tutorial/

1) Generate a new Archipelago multiworld.
2) Launch the Oblivion Remastered Client from the ArchipelagoLauncher.exe.
3) Connect to your server.
4) Once connected, you can launch Oblivion Remastered through your mod manager and start playing.

It is recommended to load a save from just before leaving the sewers. You can also play on an existing save, as long as you have not interacted with the Daedric shrine quests.
