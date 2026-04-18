#!/bin/bash

# --- 1. Environmental Hardening ---
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
GLOBAL_PATH="/usr/bin/ke.sh"
SCRIPT_PATH="$(readlink -f "$0")"
LOG_FILE="/var/log/ke_pam.log"

# Ensure log exists and is writable
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE" && sudo chmod 666 "$LOG_FILE"
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

# Helper: Run as target user without invoking the PAM stack (unlike sudo/su)
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
    # Try normal kill first
    killall -q -u "$target" gnome-keyring-daemon 2>/dev/null || true
    # Wait a bit for it to exit
    for i in {1..5}; do
        # Use -f to avoid the 15-character limit for process names
        if ! pgrep -u "$target_uid" -f gnome-keyring-daemon >/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    # Force kill if still alive
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
    $PKG_MGR keepassxc libsecret util-linux 2>/dev/null

    echo "[*] Injecting Optimized KeePassXC Configuration..."
    mkdir -p "$DB_DIR"
    cat <<'EOF' > "$CONFIG_PATH"
[General]
ConfigVersion=2
EnableDbus=true
MinimizeAfterUnlock=false
UseAtomicSaves=true

[Browser]
AlwaysAllowAccess=true
AlwaysAllowUpdate=true
Enabled=true
UnlockDatabase=true

[FdoSecrets]
ConfirmAccessItem=false
Enabled=true

[GUI]
MinimizeOnClose=true
MinimizeOnStartup=false
TrayIconAppearance=monochrome-light

[SSHAgent]
Enabled=true

[Security]
ClearClipboard=false
LockDatabaseIdle=false
LockDatabaseScreenLock=false
EOF
    chown -R "$TARGET_USER:$TARGET_USER" "$DB_DIR"

    echo "[*] Publishing script to $GLOBAL_PATH..."
    cp "$SCRIPT_PATH" "$GLOBAL_PATH"
    chmod 755 "$GLOBAL_PATH"
    [ -x /usr/sbin/chcon ] && chcon -t bin_t "$GLOBAL_PATH" 2>/dev/null

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
        
        for FILENAME in system-auth password-auth; do
            FILE_PATH="$PROFILE_DIR/$FILENAME"
            if [ -f "$FILE_PATH" ] && ! grep -q "$GLOBAL_PATH" "$FILE_PATH"; then
                # Remove any old session-stack or duplicate entries first
                sed -i "\|$GLOBAL_PATH|d" "$FILE_PATH"
                
                # Insert into auth stack
                if grep -q "pam_gnome_keyring.so" "$FILE_PATH"; then
                    sed -i "/pam_gnome_keyring.so/i $PAM_LINE" "$FILE_PATH"
                else
                    sed -i "/pam_unix.so/a $PAM_LINE" "$FILE_PATH"
                fi
                echo "[+] Updated $FILENAME in $CURRENT_PROFILE"
            fi
        done
        
        echo "[*] Applying authselect changes..."
        authselect apply-changes
    else
        echo "[*] Manual PAM modification (legacy/non-authselect system)..."
        # Target GDM and TTY login specifically
        for PAM_FILE in /etc/pam.d/gdm-password /etc/pam.d/login; do
            if [ -f "$PAM_FILE" ] && ! grep -q "$GLOBAL_PATH" "$PAM_FILE"; then
                # Insert before gnome_keyring to ensure we intercept the password
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

# --- 5. Execution Logic ---

# 5.1 Kill GNOME Keyring so KeePassXC can claim the Secret Service (libsecret)
ensure_keyring_dead "$TARGET_USER"

# 5.2 Auto Database Creation (If it doesn't exist yet)
if [[ ! -f "$DB_PATH" ]]; then
    log_msg "First run: Creating database for $TARGET_USER"
    mkdir -p "$DB_DIR"
    chown "$TARGET_USER:$TARGET_USER" "$DB_DIR"
    echo "$PASSWORD" | run_as_user keepassxc-cli db-create -p "$DB_PATH" --pw-stdin >/dev/null 2>&1
    echo "$PASSWORD" | run_as_user keepassxc-cli mkdir "$DB_PATH" "Secret Service" --pw-stdin >/dev/null 2>&1
fi

# 5.3 The Background Launcher
if ! pgrep -u "$TARGET_UID" -x keepassxc >/dev/null; then
    
    # Anti-collision: PAM often triggers 3+ times (fingerprint, password, etc.)
    LOCK_FILE="/tmp/ke_pam_$TARGET_USER.lock"
    if [ -f "$LOCK_FILE" ]; then exit 0; fi
    touch "$LOCK_FILE"
    (sleep 20; rm -f "$LOCK_FILE" 2>/dev/null) & disown

    log_msg "Triggering background unlock for $TARGET_USER"

    if [ "$EUID" -eq 0 ]; then
        # PAM Context: Escape cgroup using systemd-run
        systemd-run --uid="$TARGET_USER" --gid="$TARGET_GID" \
            --setenv="XDG_RUNTIME_DIR=/run/user/$TARGET_UID" \
            --setenv="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$TARGET_UID/bus" \
            --setenv="KP_PASS=$PASSWORD" \
            --setenv="KP_DB=$DB_PATH" \
            --setenv="T_UID=$TARGET_UID" \
            bash -c '
                exec >> "/var/log/ke_pam.log" 2>&1
                
                # Wait for Wayland socket to appear
                for i in {1..60}; do
                    if [ -S "/run/user/$T_UID/bus" ]; then
                        W_SOCK=$(ls /run/user/$T_UID/wayland-* 2>/dev/null | grep -v "\.lock" | head -n 1)
                        if [ -n "$W_SOCK" ]; then
                            export WAYLAND_DISPLAY=$(basename "$W_SOCK")
                            export DISPLAY=:0
                            break
                        fi
                    fi
                    sleep 1
                done
                
                sleep 2
                pkill -9 -f -u "$T_UID" gnome-keyring-daemon 2>/dev/null || true
                
                TMP_PASS="/dev/shm/kp_pam_tmp_$T_UID"
                echo "$KP_PASS" > "$TMP_PASS" && chmod 600 "$TMP_PASS"
                (sleep 5; rm -f "$TMP_PASS") &
                
                exec keepassxc --minimized --pw-stdin "$KP_DB" < "$TMP_PASS"
            ' &
    else
        # Shell/Interactive Context
        (
            export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
            W_SOCK=$(ls /run/user/$TARGET_UID/wayland-* 2>/dev/null | grep -v "\.lock" | head -n 1)
            [ -n "$W_SOCK" ] && export WAYLAND_DISPLAY=$(basename "$W_SOCK")
            export DISPLAY=:0

            TMP_PASS="/dev/shm/kp_pam_tmp_$TARGET_UID"
            echo "$PASSWORD" > "$TMP_PASS" && chmod 600 "$TMP_PASS"
            (sleep 5; rm -f "$TMP_PASS") &
            
            exec keepassxc --minimized --pw-stdin "$DB_PATH" < "$TMP_PASS" >> "$LOG_FILE" 2>&1
        ) & disown
    fi
fi

# Securely clear variables
unset PASSWORD
unset KP_PASS
exit 0
