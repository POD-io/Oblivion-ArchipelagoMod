## Archipelago Mod for Oblivion Remastered

A UE4SS and .esp mod that adds [Archipelago multiworld](https://archipelago.gg/) support for Oblivion Remastered.

[Download Latest Release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest)  

## **NEW** — All-in-One Installation (Option 1)

This method is ideal for users who wish to avoid using a mod manager or prefer the simplest installation method.

If you plan to use a mod manager, please use [Option 2](#mod-manager-installation-option-2) instead.

### To use the all-in-one installer:

1. Download **Batch_Installer.zip** from the [Latest Release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest).

2. Extract the folder to any location.

3. Run `install.bat`.

4. When prompted, provide your *Oblivion Remastered* installation directory  
   (or press **Y** to confirm if it is auto-detected).

The script will automatically install or update all required files directly in your Oblivion game folder.  

**IMPORTANT:**  
Once successfully installed, you must launch your game with **obse64_loader.exe**, located in: OblivionRemastered\Binaries\Win64

> **Note:**  If you wish to play Oblivion **without** Archipelago, you'll need to run the uninstall.bat file to return to a Vanilla install state.

## Mod Manager Installation (Option 2)

If you are already using MO2 or prefer to use a mod manager for easy on/off toggling of your mods, please use this option.

If you used Option 1 above, you can [skip](#how-to-use) this section.

##### 1. Install the Dev Branch of MO2:
This can be acquired on the [MO2 Discord](https://discord.gg/Jjprnb5rDJ)  
[Direct link to version 2.5.3](https://discord.com/channels/265929299490635777/379225566122999808/1377090478515945524)

##### 2. [UE4SS for OblivionRemastered](https://www.nexusmods.com/oblivionremastered/mods/32) and [OBSE64](https://www.nexusmods.com/oblivionremastered/mods/282) both **need to be installed manually into your game folder**

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

##### 3. Install the following mods into MO2:  

- [OBSE64 ue4ss Loader](https://www.nexusmods.com/oblivionremastered/mods/3421)  
- [Runtime EditorIDs](https://www.nexusmods.com/oblivionremastered/mods/1331)  
- [Address Library for OBSE Plugins](https://www.nexusmods.com/oblivionremastered/mods/4475)  
- [NL Tag Remover](https://www.nexusmods.com/oblivionremastered/mods/473)

##### 4. Download Archipelago.zip and ArchipelagoBridge.zip from the [latest release](https://github.com/POD-io/Oblivion-ArchipelagoMod/releases/latest) and manually install (Right Click --> Install Mod) both into MO2.  
You should see the **ArchipelagoBridge** mod under the UE4SS Mods tab, and the **Archipelago_Oblivion.esp** mod under the Plugins tab.


<img width="280" height="160" alt="image" src="https://github.com/user-attachments/assets/9f5790b7-2973-4867-812c-64f3cbfd5769" />  
<img width="220" height="190" alt="image" src="https://github.com/user-attachments/assets/a753b271-43f8-4036-b9c2-6d5f263424d7" />  
<img width="300" height="600" alt="image" src="https://github.com/user-attachments/assets/624feb8e-01e8-411c-88e1-72545190134e" />  


### Finally, with everything installed -- Please ensure the above -four- checkboxes are ticked.

## How to use

> **Note**:
> It is recommended you start a new character for each multiworld seed.  

For Archipelago instructions, see https://archipelago.gg/tutorial/

1) Generate a new Archipelago multiworld.
2) Launch the Oblivion Remastered Client from the ArchipelagoLauncher.exe.
3) Connect to your server.
4) Launch Oblivion Remastered through your mod manager or via obse64_loader.exe.

### For MO2: Make sure to launch through MO2 using the OBSE64 option, as seen here:

<img width="602" height="187" alt="image" src="https://github.com/user-attachments/assets/d1ad2ea4-f559-409f-b628-7ea885d75649" />

**If you do not see OBSE64** as an option, please try restarting MO2.

## How to confirm the mod is working as expected
If everything is in order, you will see your Archipelago goal display as a quest as soon as you finish creating your character.  
If the Bridge mod is not communicating as expected, you will see a pop-up ingame after 30 seconds.  
If neither of these happen, please double check that the .ESP mod is installed and activated.

## Troubleshooting: 

In the newest update, all Archipelago items will be automatically re-synced with you in the event of a death, crash, or other loss of state.  
The client will also warn you if you are disconnected, and handle recovery in a more graceful manner.  

In the event something is not running as you expect, please check:  
`%userprofile%\Documents\My Games\Oblivion Remastered\Saved\Archipelago\archipelago_debug.log`
