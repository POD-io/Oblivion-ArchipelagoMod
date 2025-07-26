## Archipelago Mod for Oblivion Remastered

A UE4SS and .esp mod that adds [Archipelago multiworld](https://archipelago.gg/) support for Oblivion Remastered.

[Download Latest Release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest)

## Mod Manager Installation

MO2 now has support for ue4ss mods. To install with MO2, follow these steps:

##### 1. Install the Dev Branch of MO2:
[This can be acquired on the MO2 Discord](https://discord.gg/Jjprnb5rDJ)

##### 2. [UE4SS for OblivionRemastered](https://www.nexusmods.com/oblivionremastered/mods/32) and [OBSE64](https://www.nexusmods.com/oblivionremastered/mods/282) both **need to be installed MANUALLY** -- They do not work as MO2 mods directly.

> **Note:**  
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

<img width="332" height="216" alt="image" src="https://github.com/user-attachments/assets/3c92122c-6725-4e32-97b7-29553064135d" />


##### 3. Install the following mods into your mod manager:  

- [OBSE64 ue4ss Loader](https://www.nexusmods.com/oblivionremastered/mods/3421)  
- [Runtime EditorIDs](https://www.nexusmods.com/oblivionremastered/mods/1331)  
- [Address Library for OBSE Plugins](https://www.nexusmods.com/oblivionremastered/mods/4475)  
- [NL Tag Remover](https://www.nexusmods.com/oblivionremastered/mods/473)

##### 4. [Download the latest release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest) and manually install (Right Click --> Install Mod) both the Archipelago.zip and ArchipelagoBridge.zip into MO2.  
You should see the **ArchipelagoBridge** mod under the UE4SS Mods tab, and the **Archipelago_Oblivion.esp** mod under the Plugins tab -- be sure it is enabled.

<img width="356" height="116" alt="image" src="https://github.com/user-attachments/assets/f229fcb9-4488-4022-aba7-108b0d37feae" />
<img width="175" height="125" alt="image" src="https://github.com/user-attachments/assets/2ca5bb2c-17d6-4523-9234-ddbf1e86b21b" />

## How to use

> **Note**:
> The mod is best experienced by loading a save from just before leaving the sewers, or you can start a new game.

For Archipelago instructions, see https://archipelago.gg/tutorial/

1) Generate a new Archipelago multiworld.
2) Launch the Oblivion Remastered Client from the ArchipelagoLauncher.exe.
3) Connect to your server.
4) Once connected, you can launch Oblivion Remastered through your mod manager and start playing.

Make sure to launch through using the obse64_loader, as seen here:

<img width="500" height="100" alt="image" src="https://github.com/user-attachments/assets/4816d8c9-f41a-4bd5-a5a3-9094593fa712" />


## Troubleshooting: 

This is Oblivion, so we have some recovery options in the event of a crash, untimely death, or other issues.
The best advice is to Quicksave(F5) any time you receive a new item from the multiworld.

#### Resending Items

You can use the console(~) to resend recent items. Type:

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
