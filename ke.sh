#!/bin/bash

# --- GitHub Resource URLs ---
GITHUB_KDBX_URL="https://raw.githubusercontent.com/xipid/utils/main/master.kdbx"
GITHUB_INI_URL="https://raw.githubusercontent.com/xipid/utils/main/keepassxc.ini"

# --- 1. Environmental Hardening ---
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
GLOBAL_PATH="/usr/bin/ke.sh"
SCRIPT_PATH="$(readlink -f "$0")"
LOG_FILE="/var/log/ke_pam.log"

# --- Requirement 4: Compare Running vs Installed Script ---
if [ "$1" != "-i" ] && [ -f "$GLOBAL_PATH" ]; then
    if ! cmp -s "$SCRIPT_PATH" "$GLOBAL_PATH" 2>/dev/null; then
        echo -e "\n[!] WARNING: The running script ($SCRIPT_PATH) differs from the installed version ($GLOBAL_PATH)." >&2
        echo -e "[!] Please rerun with: sudo $SCRIPT_PATH -i\n" >&2
    fi
fi

# Ensure log exists and is writable
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE" && sudo chmod 666 "$LOG_FILE" 2>/dev/null
fi

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# --- 2. Identity & Context Resolution ---
# --- Determine Mode & User Context ---
IS_PAM_MODE=0
if [[ "$1" == "-u" ]]; then
    IS_PAM_MODE=1
    shift # Shift arguments to capture user if provided
    [ -n "$1" ] && TARGET_USER="$1"
fi

# Fallback Identity Resolution if not provided explicitly by -u <user>
if [ -z "$TARGET_USER" ]; then
    if [ -n "$PAM_USER" ]; then
        TARGET_USER="$PAM_USER"
    elif [ "$EUID" -eq 0 ]; then
        TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
        [ -z "$TARGET_USER" ] && TARGET_USER="root"
    else
        TARGET_USER="$USER"
    fi
fi

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
DB_DIR="$USER_HOME/.config/keepassxc"
DB_PATH="$DB_DIR/master.kdbx"
CONFIG_PATH="$DB_DIR/keepassxc.ini"

# Helper: Run as target user without invoking the PAM stack
run_as_user() {
    if [ "$EUID" -eq 0 ]; then
        setpriv --reuid="$TARGET_USER" --regid="$TARGET_GID" --init-groups "$@"
    else
        "$@"
    fi
}

# Helper: Ensure gnome-keyring-daemon is dead
ensure_keyring_dead() {
    local target="$1"
    local target_uid=$(id -u "$target")
    killall -q -u "$target" gnome-keyring-daemon 2>/dev/null || true
    for i in {1..3}; do
        if ! pgrep -u "$target_uid" -f gnome-keyring-daemon >/dev/null; then return 0; fi
        sleep 0.2
    done
    pkill -9 -f -u "$target_uid" gnome-keyring-daemon 2>/dev/null || true
}

# --- Desktop Autostart Mode (-d) ---
if [[ "$1" == "-d" ]]; then
    # Runs as the normal user inside the GNOME session
    TARGET_UID=$(id -u)
    TMP_PASS="/dev/shm/kp_pam_tmp_$TARGET_UID"
    DB_PATH="$HOME/.config/keepassxc/master.kdbx"
    
    if [ -f "$TMP_PASS" ]; then
        killall -q gnome-keyring-daemon 2>/dev/null || true
        
        # Spawn a background timer to destroy the password file 
        # while keepassxc runs blocking/non-detached in the foreground
        (sleep 3; rm -f "$TMP_PASS" 2>/dev/null) &
        
        cat "$TMP_PASS" | env QT_LOGGING_RULES="*.debug=false;*.warning=false;*.critical=false" keepassxc --minimized --pw-stdin "$DB_PATH"
    else
        keepassxc --minimized "$DB_PATH"
    fi
    exit 0
fi

# --- 3. Installation Mode (-i) ---
if [[ "$1" == "-i" ]]; then
    if [ "$EUID" -ne 0 ]; then echo "Please run with sudo"; exit 1; fi

    echo "[*] Detecting Package Manager & Installing Dependencies..."
    if command -v dnf >/dev/null; then PKG_MGR="dnf install -y"
    elif command -v apt >/dev/null; then PKG_MGR="apt install -y"
    elif command -v pacman >/dev/null; then PKG_MGR="pacman -S --noconfirm"
    fi
    $PKG_MGR keepassxc libsecret util-linux curl wget 2>/dev/null

    echo "[*] Publishing script to $GLOBAL_PATH..."
    cp "$SCRIPT_PATH" "$GLOBAL_PATH"
    chmod 755 "$GLOBAL_PATH"
    [ -x /usr/sbin/chcon ] && chcon -t bin_t "$GLOBAL_PATH" 2>/dev/null

    PAM_LINE="auth optional pam_exec.so expose_authtok $GLOBAL_PATH -u"

    if command -v authselect >/dev/null; then
        echo "[*] Detected authselect system. Configuring custom profile..."
        CURRENT_PROFILE=$(authselect current | grep 'Profile ID:' | cut -d: -f2 | xargs)
        
        if [[ "$CURRENT_PROFILE" != custom/* ]]; then
            NEW_PROFILE="ke-unlock"
            echo "[+] Creating custom profile 'custom/$NEW_PROFILE' based on '$CURRENT_PROFILE'..."
            authselect create-profile "$NEW_PROFILE" -b "$CURRENT_PROFILE"
            authselect select "custom/$NEW_PROFILE" --force
            CURRENT_PROFILE="custom/$NEW_PROFILE"
        fi
        
        PROFILE_DIR="/etc/authselect/$CURRENT_PROFILE"
        echo "[*] Modifying profile at $PROFILE_DIR..."
        
		# Update this part of your installer
	for FILENAME in system-auth password-auth; do
	    FILE_PATH="$PROFILE_DIR/$FILENAME"
	    if [ -f "$FILE_PATH" ]; then
		# 1. Clean out any previous failed attempts
		sed -i "\|$GLOBAL_PATH|d" "$FILE_PATH"
		
		# 2. Inject before pam_unix.so in the template
		# We use a broad match to ensure we catch it despite the template tags
		sed -i "/pam_unix.so/i auth        optional                                     pam_exec.so expose_authtok $GLOBAL_PATH -u" "$FILE_PATH"
		
		echo "[+] Template $FILENAME updated."
	    fi
	done

	# 3. CRITICAL: Re-generate the actual PAM files from the modified templates
	authselect apply-changes
    else
        echo "[*] Manual PAM modification (legacy/non-authselect system)..."
        for PAM_FILE in /etc/pam.d/gdm-password /etc/pam.d/login /etc/pam.d/gnome-screensaver; do
            if [ -f "$PAM_FILE" ]; then
                sed -i "\|$GLOBAL_PATH|d" "$PAM_FILE"
                if grep -q "^auth.*pam_gnome_keyring.so" "$PAM_FILE"; then
                    sed -i "/^auth.*pam_gnome_keyring.so/i $PAM_LINE" "$PAM_FILE"
                elif grep -q "^auth.*pam_unix.so" "$PAM_FILE"; then
                    sed -i "/^auth.*pam_unix.so/i $PAM_LINE" "$PAM_FILE"
                fi
                echo "[+] Processed $PAM_FILE"
            fi
        done
    fi

    echo "[+] Installation complete. Log out and back in to test."
    exit 0
fi

# --- 4. Password Acquisition ---
if [ ! -t 0 ]; then
    read -r PASSWORD
else
    read -rsp "Master Password for $TARGET_USER: " PASSWORD; echo ""
fi

[[ -z "$PASSWORD" ]] && exit 0

# --- 5. Execution Logic (Runs dynamically for ANY user every launch) ---

# Anti-collision lock: Prevent PAM from running this entire block 3 times instantly
LOCK_FILE="/tmp/ke_pam_$TARGET_USER.lock"
if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
(sleep 3; rm -f "$LOCK_FILE" 2>/dev/null) & disown

mkdir -p "$DB_DIR"
chown -R "$TARGET_USER:$TARGET_USER" "$DB_DIR" 2>/dev/null

# 5.1 Clear GNOME Keyring
ensure_keyring_dead "$TARGET_USER"

# 5.2 Auto Config Download
if [[ ! -f "$CONFIG_PATH" ]]; then
    log_msg "keepassxc.ini not found for $TARGET_USER. Downloading..."
    if command -v curl >/dev/null; then 
        curl -sLf "$GITHUB_INI_URL" -o "$CONFIG_PATH" || rm -f "$CONFIG_PATH"
    else 
        wget -qO "$CONFIG_PATH" "$GITHUB_INI_URL" || rm -f "$CONFIG_PATH"
    fi
    [ -f "$CONFIG_PATH" ] && chown "$TARGET_USER:$TARGET_USER" "$CONFIG_PATH"
fi

# 5.3 Auto Database Download & Password Rotation
if [[ ! -f "$DB_PATH" ]]; then
    log_msg "master.kdbx not found for $TARGET_USER. Downloading & Rotating password..."
    TMP_KDBX="${DB_PATH}.tmp"
    
    if command -v curl >/dev/null; then 
        curl -sLf "$GITHUB_KDBX_URL" -o "$TMP_KDBX" || rm -f "$TMP_KDBX"
    else 
        wget -qO "$TMP_KDBX" "$GITHUB_KDBX_URL" || rm -f "$TMP_KDBX"
    fi
    
    if [ -f "$TMP_KDBX" ]; then
        chown "$TARGET_USER:$TARGET_USER" "$TMP_KDBX"
        XML_FILE="/dev/shm/kp_tmp_$TARGET_UID.xml"
        
        # 1. Export downloaded DB using default '1234' (Added --pw-stdin to fix the previous error)
        echo "1234" | run_as_user env QT_LOGGING_RULES="*.debug=false;*.warning=false;*.critical=false" keepassxc-cli export "$TMP_KDBX" 2>/dev/null > "$XML_FILE"
        
        # 2. Import into new DB using the user's live password
        if [ -f "$XML_FILE" ] && grep -q "<?xml" "$XML_FILE" 2>/dev/null; then
            chown "$TARGET_USER:$TARGET_USER" "$XML_FILE"
            printf "$PASSWORD\n$PASSWORD\n" | run_as_user env QT_LOGGING_RULES="*.debug=false;*.warning=false;*.critical=false" keepassxc-cli import "$XML_FILE" "$DB_PATH" --set-password >/dev/null 2>&1
            
            if [ -f "$DB_PATH" ]; then
                log_msg "Successfully downloaded and rotated database password."
            else
                log_msg "Import failed. Reverting."
            fi
        else
            log_msg "Export failed (Invalid download or wrong default pass). Reverting."
        fi
        rm -f "$XML_FILE" "$TMP_KDBX"
    fi
    
    # Fallback to pure creation logic if download/export/import failed
    if [ ! -f "$DB_PATH" ]; then
        log_msg "Creating new blank database instead."
        echo "$PASSWORD" | run_as_user keepassxc-cli db-create -p "$DB_PATH" --pw-stdin >/dev/null 2>&1
        echo "$PASSWORD" | run_as_user keepassxc-cli mkdir "$DB_PATH" "Secret Service" --pw-stdin >/dev/null 2>&1
    fi
    chown "$TARGET_USER:$TARGET_USER" "$DB_PATH" 2>/dev/null
fi

# --- 5.4 Ensure Desktop Autostart Exists ---
AUTOSTART_DIR="$USER_HOME/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/keepassxc-unlock.desktop"

if [ ! -f "$DESKTOP_FILE" ]; then
    log_msg "Creating Desktop Autostart entry for $TARGET_USER"
    mkdir -p "$AUTOSTART_DIR"
    
    cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=KeePassXC Auto-Unlock
Exec=$GLOBAL_PATH -d
X-GNOME-Autostart-enabled=true
EOF
    
    chmod 755 "$DESKTOP_FILE"
    chown -R "$TARGET_USER:$TARGET_USER" "$AUTOSTART_DIR" 2>/dev/null
fi

# --- 5.5 Stash Password ---
log_msg "Saving password to secure shared memory for $TARGET_USER"
TMP_PASS="/dev/shm/kp_pam_tmp_$TARGET_UID"
echo "$PASSWORD" > "$TMP_PASS"
chmod 600 "$TMP_PASS"
chown "$TARGET_USER:$TARGET_USER" "$TMP_PASS" 2>/dev/null
unset PASSWORD

# Failsafe cleanup: 2 mins to read the file before it destructs
(sleep 120; rm -f "$TMP_PASS" 2>/dev/null) & disown

# --- 5.6 Interactive Execution (No-Args Mode) ---
# If ran interactively (not via PAM), call the daemon manually in the background
if [ "$IS_PAM_MODE" -eq 0 ]; then
    log_msg "Interactive mode: Calling $GLOBAL_PATH -d detached"
    if [ "$EUID" -eq 0 ]; then
        run_as_user "$GLOBAL_PATH" -d & disown
    else
        "$GLOBAL_PATH" -d & disown
    fi
fi

exit 0
