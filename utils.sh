# Fetch the latest release asset URL from GitHub
ghr() {
    local repo=$1
    local regex=${2:-"."} # Use "." for match-all in regex
    local page=1

    # We shall sail the seas of pages until we strike gold
    while true; do
        local response=$(curl -s "https://api.github.com/repos/$repo/releases?page=$page")

        # Check if we have hit an empty array or an error
        if [[ -z "$response" || "$response" == "[]" || $(echo "$response" | jq 'type == "array"') == "false" ]]; then
            echo "Fin de la liste. No assets found matching: $regex" >&2
            return 1
        fi

        # Extract the first matching asset's URL
        # We select releases with assets, then find assets matching the regex
        local result=$(echo "$response" | jq -r --arg reg "$regex" '
            .[]? 
            | .assets[]? 
            | select(.browser_download_url | test($reg; "i")) 
            | .browser_download_url' | head -n 1)

        if [[ -n "$result" && "$result" != "null" ]]; then
            echo "$result"
            return 0
        fi

        ((page++))
    done
}


ipkg() {
    local source_path=$1
    local asset_regex=${2:-"."} # Capture the second arg for ghr

    if [[ -z "$source_path" ]]; then
        echo "Error: No source path or URL provided."
        return 1
    fi
    
    if [[ "$source_path" =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]] && [[ ! -e "$source_path" ]]; then
        echo "Detected GitHub handle. Resolving latest asset for: $source_path..."
        local resolved_url=$(ghr "$source_path" "$asset_regex")
        
        if [[ -z "$resolved_url" || "$resolved_url" == "null" ]]; then
            echo "Error: Could not resolve GitHub asset."
            return 1
        fi
        
        source_path="$resolved_url"
        echo "Resolved to: $source_path"
    fi

    # 1. Determine Privilege Level and Paths
    if [[ "$EUID" -eq 0 ]]; then
        local install_base="/opt"
        local bin_base="/usr/local/bin"
        local flatpak_scope="--system"
        local is_root=true
    else
        local install_base="$HOME/.opt"
        local bin_base="$HOME/.local/bin"
        local flatpak_scope="--user"
        local is_root=false
    fi

    # Ensure base directories exist
    mkdir -p "$install_base"
    mkdir -p "$bin_base"

    # 2. Determine Input Type (Local, URL, or Git)
    local is_url=false
    local is_git=false
    local target_file="$source_path"
    local tmp_dir=""

    if [[ "$source_path" == *.git ]] || [[ "$source_path" == git@* ]]; then
        is_git=true
    elif [[ "$source_path" =~ ^https?:// ]]; then
        is_url=true
    else
        if [[ ! -f "$source_path" ]] && [[ ! -d "$source_path" ]]; then
            echo "Error: Local file or directory does not exist: $source_path"
            return 1
        fi
    fi

    # Parse names
    local filename=$(basename "$source_path")
    if [[ "$is_git" == true ]]; then
        filename="${filename%.git}"
    fi
    local name="${filename%%.*}" # Strip all extensions for the directory name

    echo "Initiating installation for package: $name..."

    # 3. Handle Git Repositories
    if [[ "$is_git" == true ]]; then
        local target_dir="$install_base/$name"
        if [[ -d "$target_dir" ]]; then
            echo "Repository already exists at $target_dir. Pulling latest changes..."
            git -C "$target_dir" pull
        else
            echo "Cloning repository to $target_dir..."
            git clone "$source_path" "$target_dir"
        fi
        _link_binary "$target_dir" "$name" "$bin_base"
        echo "Installation completed successfully."
        return 0
    fi

    # 4. Handle HTTP/HTTPS URLs (Download Phase)
    if [[ "$is_url" == true ]]; then
        tmp_dir=$(mktemp -d)
        target_file="$tmp_dir/$filename"
        
        echo "Downloading package from remote URL..."
        if ! curl -fL "$source_path" -o "$target_file"; then
            echo "Error: Download failed."
            rm -rf "$tmp_dir"
            return 1
        fi
    fi

    # 5. Handle Package Formats
    if [[ "$filename" == *.rpm ]]; then
        if [[ "$is_root" == false ]]; then
            echo "Error: RPM packages require global installation (root privileges). Aborting."
            [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"
            return 1
        fi
        echo "Installing RPM package via DNF..."
        dnf install -y "$target_file"

    elif [[ "$filename" == *.flatpak ]] || [[ "$filename" == *.flatpakref ]]; then
        echo "Installing Flatpak package..."
        flatpak install -y $flatpak_scope "$target_file"

    elif [[ "$filename" =~ \.(tar|tar\.gz|tar\.xz|tar\.bz2|tar\.zst|zip)$ ]]; then
        local target_dir="$install_base/$name"
        echo "Extracting archive to $target_dir..."
        mkdir -p "$target_dir"

        if [[ "$filename" == *.zip ]]; then
            unzip -q "$target_file" -d "$target_dir"
        else
            tar axf "$target_file" -C "$target_dir" --strip-components=1
        fi

        _link_binary "$target_dir" "$name" "$bin_base"

    else
        echo "Error: Unsupported file format."
        [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"
        return 1
    fi

    # 6. Cleanup
    if [[ -n "$tmp_dir" ]]; then
        echo "Cleaning up temporary files..."
        rm -rf "$tmp_dir"
    fi

    echo "Installation completed successfully."
}

_link_binary() {
    local target_dir=$1
    local name=$2
    local bin_base=$3

    # 1. Handle Executables (The Multi-Linker)
    echo "Scanning for executables in $target_dir..."
    
    # We find all top-level executables, avoiding hidden files and common non-app dirs
    find "$target_dir" -maxdepth 2 -type f -executable ! -path "*/.*" | while read -r bin_path; do
        local bin_name=$(basename "$bin_path")
        
        # We skip scripts that look like installers/uninstallers to avoid clutter
        if [[ "$bin_name" =~ ^(install|uninstall|setup)\.sh$ ]]; then
            continue
        fi

        echo "Linking $bin_name to $bin_base..."
        ln -sf "$bin_path" "$bin_base/$bin_name"
    done

    # 2. Handle Desktop Files (The Menu Integrator)
    local desktop_dir
    if [[ "$is_root" == true ]]; then
        desktop_dir="/usr/share/applications"
    else
        desktop_dir="$HOME/.local/share/applications"
    fi
    mkdir -p "$desktop_dir"

    find "$target_dir" -maxdepth 2 -name "*.desktop" | while read -r desktop_file; do
        local desktop_name=$(basename "$desktop_file")
        echo "Installing desktop entry: $desktop_name"

        # We must fix the 'Exec' and 'Icon' paths inside the .desktop file
        # so they point to the actual absolute paths in your .opt folder
        local tmp_desktop=$(mktemp)
        cp "$desktop_file" "$tmp_desktop"

        # Update Exec path
        local main_bin=$(find "$target_dir" -maxdepth 2 -type f -executable | head -n 1)
        sed -i "s|^Exec=.*|Exec=$main_bin|" "$tmp_desktop"
        
        # Update Icon path (searching for common image extensions)
        local icon_path=$(find "$target_dir" -maxdepth 2 \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \) | head -n 1)
        if [[ -n "$icon_path" ]]; then
            sed -i "s|^Icon=.*|Icon=$icon_path|" "$tmp_desktop"
        fi

        mv "$tmp_desktop" "$desktop_dir/$desktop_name"
        chmod +x "$desktop_dir/$desktop_name"
    done
}

