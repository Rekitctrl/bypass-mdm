# Bypass-MDM for MacOS (Tested up to MacOS Sequoia 15.6)

![mdm-screen](https://raw.githubusercontent.com/Rekitctrl/bypass-mdm/main/mdm-screen.webp)

#### Advised Approach

- **Erase the hard-drive prior to starting.**
- **Re-install MacOS**
- **Device language needs to be set to English, it can be changed afterwards.**

#### Warnings ⚠️

- **If you only reset all accounts and settings and don't do a re-install of MacOs, the script may not work**
- **I do what I can to ensure these scripts are safe, however, use them at your own risk. I am not responsible for any damage that these scripts could cause**

#### Notes

- **The BadKB/RubberDucky version will not be frequently updated**


#### Follow steps below to bypass MDM setup during a fresh installation of MacOS

> Upon arriving to the setup stage of forced MDM enrollement:

1. Long press Power button to forcefully shut down your Mac.

2. Hold the power button to start your Mac & boot into recovery mode.

> a. **Apple-based Mac**: Hold Power button.\
> b. **Intel-based Mac**: Hold <kbd>CMD</kbd> + <kbd>R</kbd> during boot.

3. Connect to WiFi to activate your Mac.

4. Enter Recovery Mode & Open Safari.

5. Navigate to https://github.com/Rekitctrl/bypass-mdm

6. Copy the command below:

  Current Functional Version:

  ```zsh
  curl https://raw.githubusercontent.com/Rekitctrl/bypass-mdm/main/bypass-mdm.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
  ```
  BadKB/RubberDucky Version:
  
  ```zsh
  curl https://raw.githubusercontent.com/Rekitctrl/bypass-mdm/main/bypass-mdm-badkb.sh -o bypass-mdm-badkb.sh && chmod +x ./bypass-mdm-badkb.sh && ./bypass-mdm-badkb.sh
  ```
  ⚠️ Beta Version:

  ```zsh
  curl https://raw.githubusercontent.com/Rekitctrl/bypass-mdm/main/beta-bypass-mdm.sh -o beta-bypass-mdm.sh && chmod +x ./beta-bypass-mdm.sh && ./beta-bypass-mdm.sh
  ```

7. Launch Terminal (Utilities > Terminal).

8. Paste (<kbd>CMD</kbd> + <kbd>V</kbd>) and Run the script (<kbd>ENTER</kbd>)

9. Input 1 for Autobypass.

10. Preset username 'Apple' (Cannot be changed for reliability).

11. Preset password '1234' (Cannot be changed for reliability).

12. Wait for the script to finish & then reboot your Mac.

13. Sign in with user (Apple) & password (1234)

14. Skip all setup (Apple ID, Siri, Touch ID, Location Services)

15. Once on the desktop navigate to System Settings > Users and Groups, and create your real Admin account.

16. Log out of the Apple profile, and sign in into your real profile.

17. Feel free set up properly now (Apple ID, Siri, Touch ID, Location Services).

18. Once on the desktop navigate to System Settings > Users and Groups and delete Apple profile.

19. You're MDM free

###### Although it's virtually impossible to catch that you've removed the MDM (because it wasn't even configured), be aware that the serial number of the laptop will still be shown in the inventory system of your organization. This script removes MDM capabilities before it's configured locally, so it won't be available as a managed laptop to the organization. Use with caution. Probably a good idea to have a valid excuse as well.
