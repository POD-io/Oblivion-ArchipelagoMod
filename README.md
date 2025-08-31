## Archipelago Mod for Oblivion Remastered

A UE4SS and .esp mod that adds [Archipelago multiworld](https://archipelago.gg/) support for Oblivion Remastered.

[Download Latest Release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest)

## Mod Manager Installation

MO2 now has support for ue4ss mods. To install with MO2, follow these steps:

##### 1. Install the Dev Branch of MO2:
This can be acquired on the [MO2 Discord](https://discord.gg/Jjprnb5rDJ)  
[Direct link to version 2.5.3](https://discord.com/channels/265929299490635777/379225566122999808/1377090478515945524)

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
You should see the **ArchipelagoBridge** mod under the UE4SS Mods tab, and the **Archipelago_Oblivion.esp** mod under the Plugins tab.


<img width="280" height="160" alt="image" src="https://github.com/user-attachments/assets/9f5790b7-2973-4867-812c-64f3cbfd5769" />  
<img width="220" height="190" alt="image" src="https://github.com/user-attachments/assets/a753b271-43f8-4036-b9c2-6d5f263424d7" />  
<img width="300" height="600" alt="image" src="https://github.com/user-attachments/assets/624feb8e-01e8-411c-88e1-72545190134e" />  


### Finally, with everything installed -- Please ensure the above -four- checkboxes are ticked.

## How to use

> **Note**:
> In the latest version, it is recommended you start a new character for each playthrough.  

For Archipelago instructions, see https://archipelago.gg/tutorial/

1) Generate a new Archipelago multiworld.
2) Launch the Oblivion Remastered Client from the ArchipelagoLauncher.exe.
3) Connect to your server.
4) Once connected, you can launch Oblivion Remastered through your mod manager and start playing.

### Make sure to launch through OBSE64, as seen here:

<img width="615" height="200" alt="image" src="https://github.com/user-attachments/assets/242bc578-8b05-40e6-a0a0-4fca16e038e6" />

**If you do not see OBSE64** as an option, please try restarting MO2.


## Troubleshooting: 

In the newest update, all Archipelago items will be automatically re-synced with you in the event of a death, crash, or other loss of state.
The client will also warn you if you are disconnected, and handle recovery in a more graceful manner.
In the event something is not running as you expect, please check `%userprofile%\Documents\My Games\Oblivion Remastered\Saved\Archipelago\archipelago_debug.log`
