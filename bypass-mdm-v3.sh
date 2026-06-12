#!/bin/bash

# ══════════════════════════════════════════════════════════════════════════════
#  MDM Bypass — By Rekitctrl
#  Requires: macOS Recovery environment, root privileges
# ══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
IFS=$'\n\t'

# ── Constants ─────────────────────────────────────────────────────────────────

readonly VERSION="2.0.0"
readonly UID_MIN=501
readonly UID_MAX=599
readonly MDM_DOMAINS=(
	"deviceenrollment.apple.com"
	"mdmenrollment.apple.com"
	"iprofiles.apple.com"
	"gdmf.apple.com"
	"acmdm.apple.com"
	"albert.apple.com"
)

# ── Colors ────────────────────────────────────────────────────────────────────

if [ -t 1 ] && tput colors &>/dev/null && [ "$(tput colors)" -ge 8 ]; then
	RED='\033[1;31m' GRN='\033[1;32m' BLU='\033[1;34m'
	YEL='\033[1;33m' CYAN='\033[1;36m' DIM='\033[2m' NC='\033[0m'
else
	RED='' GRN='' BLU='' YEL='' CYAN='' DIM='' NC=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────

readonly LOG_FILE="/tmp/mdm_bypass_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log()         { echo -e "$(date '+%H:%M:%S') $*" >> "$LOG_FILE"; }
error_exit()  { echo -e "\n${RED}✖ ERROR: $1${NC}\n" >&2; log "ERROR: $1"; exit 1; }
warn()        { echo -e "${YEL}⚠ WARNING: $1${NC}" >&2; log "WARN: $1"; }
success()     { echo -e "${GRN}✓ $1${NC}"; log "OK: $1"; }
info()        { echo -e "${BLU}ℹ $1${NC}"; log "INFO: $1"; }
section()     { echo -e "\n${CYAN}── $1 ──${NC}"; }
dim()         { echo -e "${DIM}$1${NC}"; }

# ── Preflight checks ──────────────────────────────────────────────────────────

preflight() {
	# Root
	[ "$(id -u)" -eq 0 ] || error_exit "Must be run as root. Use: sudo $0"

	# Bash version (need 4+ for modern features; Recovery ships 3.x so we stay compat)
	[ "${BASH_VERSINFO[0]}" -ge 3 ] || error_exit "Bash 3.0+ required."

	# Recovery environment (launchd not running as PID 1 / no SpringBoard)
	if pgrep -x "Finder" &>/dev/null || pgrep -x "SpringBoard" &>/dev/null; then
		error_exit "Must be run from macOS Recovery, not a live system."
	fi

	# Required binaries
	local deps=(dscl diskutil grep touch mkdir rm chown tee cut date pgrep reboot)
	local missing=()
	for bin in "${deps[@]}"; do
		command -v "$bin" &>/dev/null || missing+=("$bin")
	done
	[ ${#missing[@]} -eq 0 ] || error_exit "Missing required tools: ${missing[*]}"

	# Disk space (need at least 10 MB free in /tmp)
	local free_kb
	free_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2{print $4}')
	[ -n "$free_kb" ] && [ "$free_kb" -lt 10240 ] && warn "Low disk space in /tmp (${free_kb}KB free)"
}

# ── Volume detection ──────────────────────────────────────────────────────────

detect_volumes() {
	local sys="" data=""

	# Strategy 1: canonical APFS system volume (has /System/Library/CoreServices)
	for vol in /Volumes/*/; do
		[ -d "$vol" ] || continue
		local name
		name=$(basename "$vol")
		[[ "$name" =~ Data$    ]] && continue
		[[ "$name" =~ Recovery ]] && continue
		[ -d "$vol/System/Library/CoreServices" ] || continue
		sys="$name"
		info "Found system volume: $sys"
		break
	done

	# Strategy 2: any volume with /System
	if [ -z "$sys" ]; then
		for vol in /Volumes/*/; do
			[ -d "$vol/System" ] || continue
			sys=$(basename "$vol")
			warn "Fallback system volume: $sys"
			break
		done
	fi

	[ -z "$sys" ] && error_exit "Cannot detect system volume. Ensure macOS is installed."

	# Data volume: prefer "<sys> - Data", then "Data", then any *Data volume
	if   [ -d "/Volumes/${sys} - Data" ]; then data="${sys} - Data"
	elif [ -d "/Volumes/Data"           ]; then data="Data"
	else
		for vol in /Volumes/*Data/; do
			[ -d "$vol" ] && data=$(basename "$vol") && break
		done
	fi

	[ -z "$data" ] && error_exit "Cannot detect data volume."

	info "Data volume: $data"
	printf '%s|%s' "$sys" "$data"
}

# ── dscl helpers ──────────────────────────────────────────────────────────────

dscl_cmd() { dscl -f "$DSCL_PATH" localhost "$@" 2>/dev/null; }

user_exists() { dscl_cmd -read "/Local/Default/Users/$1" &>/dev/null; }

find_available_uid() {
	local uid=$UID_MIN
	while [ $uid -le $UID_MAX ]; do
		dscl_cmd -search /Local/Default/Users UniqueID "$uid" | grep -q "UniqueID" \
			|| { echo "$uid"; return 0; }
		uid=$((uid + 1))
	done
	error_exit "No available UID in range ${UID_MIN}–${UID_MAX}."
}

# ── Validation ────────────────────────────────────────────────────────────────

validate_username() {
	local u="$1"
	[ -z "$u" ]                                && echo "Username cannot be empty"                                                                 && return 1
	[ ${#u} -gt 31 ]                           && echo "Username too long (max 31 chars)"                                                         && return 1
	[[ "$u" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]   || { echo "Must start with letter/underscore; only letters, numbers, hyphens, underscores allowed"; return 1; }
	# Reserved names
	local reserved=(root daemon nobody www ftp mail)
	for r in "${reserved[@]}"; do
		[ "$u" = "$r" ] && echo "Username '$u' is reserved" && return 1
	done
	return 0
}

validate_password() {
	local p="$1"
	[ -z "$p" ]     && echo "Password cannot be empty"             && return 1
	[ ${#p} -lt 4 ] && echo "Password too short (min 4 chars)"     && return 1
	[ ${#p} -gt 64 ] && echo "Password too long (max 64 chars)"    && return 1
	return 0
}

# ── User creation ─────────────────────────────────────────────────────────────

rollback_user() {
	local username="$1"
	warn "Rolling back user '$username'..."
	dscl_cmd -delete "/Local/Default/Users/$username" || true
	dscl_cmd -delete "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || true
	[ -d "$DATA_PATH/Users/$username" ] && rm -rf "$DATA_PATH/Users/$username" && info "Removed home directory"
}

create_user() {
	local username="$1" realName="$2" passw="$3" uid="$4"
	local home="$DATA_PATH/Users/$username"

	info "Creating user account: $username (UID $uid)"

	# Rollback on any failure in this function
	trap 'rollback_user "$username"' ERR

	dscl_cmd -create  "/Local/Default/Users/$username"                                   || error_exit "Failed to create user record"
	dscl_cmd -create  "/Local/Default/Users/$username" UserShell        "/bin/zsh"       || warn "Failed to set shell"
	dscl_cmd -create  "/Local/Default/Users/$username" RealName         "$realName"      || warn "Failed to set real name"
	dscl_cmd -create  "/Local/Default/Users/$username" UniqueID         "$uid"           || error_exit "Failed to set UID"
	dscl_cmd -create  "/Local/Default/Users/$username" PrimaryGroupID   "20"             || error_exit "Failed to set GID"
	dscl_cmd -create  "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" || warn "Failed to set home path"
	dscl_cmd -create  "/Local/Default/Users/$username" IsHidden         "0"              || true
	dscl_cmd -passwd  "/Local/Default/Users/$username" "$passw"                          || error_exit "Failed to set password"
	dscl_cmd -append  "/Local/Default/Groups/admin"    GroupMembership  "$username"      || error_exit "Failed to add to admin group"

	# Home directory
	if [ ! -d "$home" ]; then
		mkdir -p "$home"       || error_exit "Failed to create home directory"
	fi
	chown -R "${uid}:20" "$home" || warn "Failed to set home ownership"
	chmod 755 "$home"            || warn "Failed to set home permissions"

	trap - ERR
	success "User '$username' created successfully"
}

# ── MDM blocking ──────────────────────────────────────────────────────────────

block_mdm_domains() {
	local hosts="$SYS_PATH/etc/hosts"

	[ -f "$hosts" ] || { touch "$hosts" || error_exit "Cannot create hosts file"; }

	# Backup hosts file
	cp "$hosts" "${hosts}.bak.$(date +%Y%m%d_%H%M%S)" && info "Hosts file backed up" || warn "Could not back up hosts file"

	local added=0
	for domain in "${MDM_DOMAINS[@]}"; do
		if ! grep -q "$domain" "$hosts"; then
			printf '0.0.0.0 %s\n' "$domain" >> "$hosts" && added=$((added + 1))
		else
			dim "  Already blocked: $domain"
		fi
	done
	success "MDM domains blocked ($added new entries)"
}

# ── MDM bypass markers ────────────────────────────────────────────────────────

apply_mdm_bypass() {
	local cfg="$SYS_PATH/var/db/ConfigurationProfiles/Settings"
	local setup_done="$DATA_PATH/private/var/db/.AppleSetupDone"

	mkdir -p "$cfg" || error_exit "Cannot create ConfigurationProfiles directory"

	# Mark initial setup as complete
	touch "$setup_done" && success "Marked setup complete" || warn "Could not mark setup complete"

	# Remove DEP/MDM activation markers
	local to_remove=(
		"$cfg/.cloudConfigHasActivationRecord"
		"$cfg/.cloudConfigRecordFound"
		"$SYS_PATH/var/db/ConfigurationProfiles/MDMEnrollment.plist"
		"$SYS_PATH/var/db/ConfigurationProfiles/MDMEnrollmentInfo.plist"
		"$DATA_PATH/private/var/db/ConfigurationProfiles"
	)
	for f in "${to_remove[@]}"; do
		if [ -e "$f" ]; then
			rm -rf "$f" && success "Removed: $(basename "$f")" || warn "Could not remove: $f"
		else
			dim "  Not present: $(basename "$f")"
		fi
	done

	# Create bypass markers
	local to_create=(
		"$cfg/.cloudConfigProfileInstalled"
		"$cfg/.cloudConfigRecordNotFound"
	)
	for f in "${to_create[@]}"; do
		touch "$f" && success "Created: $(basename "$f")" || warn "Could not create: $(basename "$f")"
	done

	# Lock ConfigurationProfiles directory against re-enrollment
	chflags schg "$cfg" 2>/dev/null && success "Locked ConfigurationProfiles directory" || warn "Could not lock config directory (non-critical)"
}

# ── Input prompts ─────────────────────────────────────────────────────────────

prompt_username() {
	local username msg
	while true; do
		read -rp "Username (default: Apple): " username
		username="${username:-Apple}"
		msg=$(validate_username "$username") && break || warn "$msg"
	done
	while user_exists "$username"; do
		warn "User '$username' already exists on this volume."
		read -rp "Enter a different username: " username
		[ -z "$username" ] && continue
		msg=$(validate_username "$username") || { warn "$msg"; continue; }
	done
	echo "$username"
}

prompt_password() {
	local passw passw2 msg
	while true; do
		read -rsp "Password (default: 1234): " passw; echo
		passw="${passw:-1234}"
		read -rsp "Confirm password: " passw2; echo
		[ "$passw" != "$passw2" ] && { warn "Passwords do not match"; continue; }
		msg=$(validate_password "$passw") && break || warn "$msg"
	done
	echo "$passw"
}

# ── Reboot countdown ──────────────────────────────────────────────────────────

reboot_countdown() {
	local i
	for i in 5 4 3 2 1; do
		printf "  ${YEL}Rebooting in %d...${NC}\r" "$i"
		sleep 1
	done
	echo ""
	reboot
}

# ── Globals (set after volume detection) ─────────────────────────────────────

SYS_PATH=""
DATA_PATH=""
DSCL_PATH=""

# ══════════════════════════════════════════════════════════════════════════════
#  Entry point
# ══════════════════════════════════════════════════════════════════════════════

preflight

vol_info=$(detect_volumes)
SYS_VOL=$(cut  -d'|' -f1 <<< "$vol_info")
DATA_VOL=$(cut -d'|' -f2 <<< "$vol_info")
SYS_PATH="/Volumes/$SYS_VOL"
DATA_PATH="/Volumes/$DATA_VOL"
DSCL_PATH="$DATA_PATH/private/var/db/dslocal/nodes/Default"

[ -d "$SYS_PATH"  ] || error_exit "System volume path not found: $SYS_PATH"
[ -d "$DATA_PATH" ] || error_exit "Data volume path not found: $DATA_PATH"
[ -d "$DSCL_PATH" ] || error_exit "Directory Services path not found: $DSCL_PATH"

clear
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       MDM Bypass v${VERSION} — By Rekitctrl       ║${NC}"
echo -e "${CYAN}║                  Log: $LOG_FILE                   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume : $SYS_VOL"
success "Data Volume   : $DATA_VOL"
success "Log file      : $LOG_FILE"
echo ""

PS3=$'\nYour choice: '
select opt in "Bypass MDM from Recovery" "Reboot & Exit"; do
	case $opt in
	"Bypass MDM from Recovery")

		section "MDM Bypass"

		# Normalize data volume
		if [ "$DATA_VOL" != "Data" ]; then
			info "Renaming data volume to 'Data'..."
			if diskutil rename "$DATA_VOL" "Data" &>/dev/null; then
				success "Renamed to 'Data'"
				DATA_VOL="Data"
				DATA_PATH="/Volumes/Data"
				DSCL_PATH="$DATA_PATH/private/var/db/dslocal/nodes/Default"
			else
				warn "Rename failed — continuing with: $DATA_VOL"
			fi
		fi

		section "Admin User Setup"
		dim "Press Enter to accept defaults"
		echo ""

		read -rp "Full name (default: Apple): " REALNAME
		REALNAME="${REALNAME:-Apple}"

		USERNAME=$(prompt_username)
		PASSWORD=$(prompt_password)

		echo ""
		UID_VAL=$(find_available_uid)
		success "Using UID: $UID_VAL"

		section "Creating User"
		create_user "$USERNAME" "$REALNAME" "$PASSWORD" "$UID_VAL"

		section "Blocking MDM Domains"
		block_mdm_domains

		section "Applying MDM Bypass"
		apply_mdm_bypass

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║         MDM Bypass Completed Successfully!       ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Login credentials:${NC}"
		echo -e "  Username : ${YEL}$USERNAME${NC}"
		echo -e "  Password : ${YEL}$PASSWORD${NC}"
		echo -e "  Log file : ${DIM}$LOG_FILE${NC}"
		echo ""
		reboot_countdown
		break
		;;

	"Reboot & Exit")
		info "Rebooting..."
		reboot
		break
		;;

	*)
		echo -e "${RED}Invalid option: $REPLY${NC}"
		;;
	esac
done
