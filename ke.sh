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
if [ -n "$PAM_USER" ]; then
    TARGET_USER="$PAM_USER"
elif [ "$EUID" -eq 0 ]; then
    TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
    [ -z "$TARGET_USER" ] && TARGET_USER="root"
else
    TARGET_USER="$USER"
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
    for i in {1..5}; do
        if ! pgrep -u "$target_uid" -f gnome-keyring-daemon >/dev/null; then return 0; fi
        sleep 0.2
    done
    pkill -9 -f -u "$target_uid" gnome-keyring-daemon 2>/dev/null || true
}

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

    # Requirement 1: This is a system-wide PAM injection, naturally targeting all existing & future users.
    PAM_LINE="auth optional pam_exec.so expose_authtok $GLOBAL_PATH"

    if command -v authselect >/dev/null; then
        echo "[*] Detected authselect system. Configuring custom profile..."
        CURRENT_PROFILE=$(authselect current | grep 'Profile ID:' | cut -d: -f2 | xargs)
        
        if [[ "$CURRENT_PROFILE" != custom/* ]]; then
            NEW_PROFILE="ke-unlock"
            echo "[+] Creating custom profile 'custom/$NEW_PROFILE' based on '$CURRENT_PROFILE'..."
            authselect create-profile "$NEW_PROFILE" -b "$CURRENT_PROFILE" --force
            authselect select "custom/$NEW_PROFILE" --force
            CURRENT_PROFILE="custom/$NEW_PROFILE"
        fi
        
        PROFILE_DIR="/etc/authselect/$CURRENT_PROFILE"
        echo "[*] Modifying profile at $PROFILE_DIR..."
        
        for FILENAME in system-auth password-auth smartcard-auth; do
            FILE_PATH="$PROFILE_DIR/$FILENAME"
            if [ -f "$FILE_PATH" ] && ! grep -q "$GLOBAL_PATH" "$FILE_PATH"; then
                sed -i "\|$GLOBAL_PATH|d" "$FILE_PATH"
                if grep -q "pam_gnome_keyring.so" "$FILE_PATH"; then
                    sed -i "/pam_gnome_keyring.so/i $PAM_LINE" "$FILE_PATH"
                else
                    sed -i "/pam_unix.so/a $PAM_LINE" "$FILE_PATH"
                fi
                echo "[+] Updated $FILENAME in $CURRENT_PROFILE"
            fi
        done
        authselect apply-changes
    else
        echo "[*] Manual PAM modification (legacy/non-authselect system)..."
        for PAM_FILE in /etc/pam.d/gdm-password /etc/pam.d/login /etc/pam.d/gnome-screensaver; do
            if [ -f "$PAM_FILE" ] && ! grep -q "$GLOBAL_PATH" "$PAM_FILE"; then
                if grep -q "pam_gnome_keyring.so" "$PAM_FILE"; then
                    sed -i "/pam_gnome_keyring.so/i $PAM_LINE" "$PAM_FILE"
                else
                    sed -i "/pam_unix.so/a $PAM_LINE" "$PAM_FILE"
                fi
                echo "[+] Injected into $PAM_FILE"
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

# 5.1 Clear GNOME Keyring
ensure_keyring_dead "$TARGET_USER"

# 5.2 Auto Database & Config Check (Requirement 2 & 3: Happens every time without -i)
if [[ ! -f "$CONFIG_PATH" ]]; then
    log_msg "keepassxc.ini not found for $TARGET_USER. Downloading..."
    mkdir -p "$DB_DIR"
    if command -v curl >/dev/null; then curl -sL "$GITHUB_INI_URL" -o "$CONFIG_PATH"
    else wget -qO "$CONFIG_PATH" "$GITHUB_INI_URL"; fi
    chown "$TARGET_USER:$TARGET_USER" "$CONFIG_PATH" 2>/dev/null
fi

if [[ ! -f "$DB_PATH" ]]; then
    log_msg "master.kdbx not found for $TARGET_USER. Downloading & Rotating password..."
    mkdir -p "$DB_DIR"
    TMP_KDBX="${DB_PATH}.tmp"
    
    if command -v curl >/dev/null; then curl -sL "$GITHUB_KDBX_URL" -o "$TMP_KDBX"
    else wget -qO "$TMP_KDBX" "$GITHUB_KDBX_URL"; fi
    chown "$TARGET_USER:$TARGET_USER" "$TMP_KDBX" 2>/dev/null
    
    XML_FILE="/dev/shm/kp_tmp_$TARGET_UID.xml"
    
    # Export using default '1234'
    echo "1234" | run_as_user keepassxc-cli export "$TMP_KDBX" "$XML_FILE" >/dev/null 2>&1
    
    if [ -f "$XML_FILE" ] && [ -s "$XML_FILE" ]; then
        # Re-import DB via XML using the newly provided PAM password
        echo "$PASSWORD" | run_as_user keepassxc-cli import "$XML_FILE" "$DB_PATH" --pw-stdin >/dev/null 2>&1
        rm -f "$XML_FILE" "$TMP_KDBX"
        log_msg "Successfully downloaded and rotated database password."
    else
        log_msg "Download/export failed. Creating new blank database instead."
        rm -f "$XML_FILE" "$TMP_KDBX"
        echo "$PASSWORD" | run_as_user keepassxc-cli db-create -p "$DB_PATH" --pw-stdin >/dev/null 2>&1
        echo "$PASSWORD" | run_as_user keepassxc-cli mkdir "$DB_PATH" "Secret Service" --pw-stdin >/dev/null 2>&1
    fi
    chown "$TARGET_USER:$TARGET_USER" "$DB_PATH" 2>/dev/null
fi

# 5.3 The Background Launcher (Fixed for GNOME login)
LOCK_FILE="/tmp/ke_pam_$TARGET_USER.lock"
if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
(sleep 3; rm -f "$LOCK_FILE" 2>/dev/null) & disown

log_msg "Triggering background launch/unlock for $TARGET_USER"

# Safely stash password for the daemon
TMP_PASS="/dev/shm/kp_pam_tmp_$TARGET_UID"
echo "$PASSWORD" > "$TMP_PASS"
chmod 600 "$TMP_PASS"
chown "$TARGET_USER:$TARGET_USER" "$TMP_PASS" 2>/dev/null

# Clean up variables securely
unset PASSWORD

if [ "$EUID" -eq 0 ]; then
    # Completely detach from the PAM execution phase so we don't freeze the login screen
    # Using `setsid` and strict I/O redirection is the most reliable way to background in PAM
    setsid setpriv --reuid="$TARGET_USER" --regid="$TARGET_GID" --init-groups bash -c "
        exec 0</dev/null
        exec 1>>'$LOG_FILE'
        exec 2>&1

        # We must establish the exact user environment for GUI apps
        export HOME='$USER_HOME'
        export USER='$TARGET_USER'

        # Absolute safety net: delete temp pass after 120 seconds if display never comes up
        (sleep 120; rm -f '$TMP_PASS') &

        DISPLAY_UP=0
        # Wait up to 60 seconds for GNOME Shell to start Wayland/X11
        for i in {1..60}; do
            if [ -S '/run/user/$TARGET_UID/bus' ]; then
                export XDG_RUNTIME_DIR='/run/user/$TARGET_UID'
                export DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/$TARGET_UID/bus'
                
                # Check for Wayland
                W_SOCK=\$(find /run/user/$TARGET_UID -maxdepth 1 -name 'wayland-*' -not -name '*.lock' 2>/dev/null | head -n 1)
                if [ -n \"\$W_SOCK\" ]; then
                    export WAYLAND_DISPLAY=\$(basename \"\$W_SOCK\")
                    export DISPLAY=:0
                    DISPLAY_UP=1
                    break
                fi
                
                # Check for X11 fallback
                X_SOCK=\$(find /tmp/.X11-unix/ -maxdepth 1 -type s -user '$TARGET_UID' 2>/dev/null | head -n 1)
                if [ -n \"\$X_SOCK\" ]; then
                    export DISPLAY=\":\${X_SOCK#/tmp/.X11-unix/X}\"
                    DISPLAY_UP=1
                    break
                fi
            fi
            sleep 1
        done
        
        if [ \"\$DISPLAY_UP\" -eq 0 ]; then
            echo \"[$(date)] No X11/Wayland display found for $TARGET_USER. Quietly exiting.\"
            rm -f '$TMP_PASS'
            exit 0
        fi
        
        # Give GNOME shell 2 seconds to stabilize its DBUS policies
        sleep 2
        killall -q -u '$TARGET_USER' gnome-keyring-daemon 2>/dev/null || true
        
        echo \"[$(date)] Launching/Unlocking KeePassXC for $TARGET_USER...\"
        keepassxc --minimized --pw-stdin '$DB_PATH' < '$TMP_PASS'
        
        # Cleanup immediately after KeePassXC reads it
        rm -f '$TMP_PASS'
    " & disown
else
    # Shell/Interactive Context Fallback
    (
        export HOME="$USER_HOME"
        export USER="$TARGET_USER"
        export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
        
        W_SOCK=$(find /run/user/$TARGET_UID -maxdepth 1 -name 'wayland-*' -not -name '*.lock' 2>/dev/null | head -n 1)
        if [ -n "$W_SOCK" ]; then
            export WAYLAND_DISPLAY=$(basename "$W_SOCK")
            export DISPLAY=:0
        fi

        (sleep 120; rm -f "$TMP_PASS") &
        keepassxc --minimized --pw-stdin "$DB_PATH" < "$TMP_PASS" >> "$LOG_FILE" 2>&1
        rm -f "$TMP_PASS"
    ) & disown
fi

exit 0