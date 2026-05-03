#!/bin/bash

# ==========================================
# --- INITIALISATION ET COULEURS ---
# ==========================================
set -eo pipefail # Arrête le script en cas d'erreur grave

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==========================================
# --- FONCTION D'AIDE ---
# ==========================================
show_help() {
    echo -e "${CYAN}Usage: $0 [OPTIONS]${NC}"
    echo -e "Script de synchronisation Rclone avancé avec gestion intelligente de filtres.\n"
    echo -e "${YELLOW}Options principales:${NC}"
    echo -e "  ${GREEN}-h, --help${NC}      Affiche ce menu d'aide"
    echo -e "  ${GREEN}-m, --minimal${NC}   Active le mode minimal (inclusions restreintes + exclusions globales)"
    echo -e "  ${GREEN}-p, --pull${NC}      Inverse le sens de synchronisation (Remote -> Local)"
    echo -e "  ${GREEN}-f, --from DIR${NC}  Définit le dossier source (Défaut: $HOME)"
    echo -e "  ${GREEN}-t, --to DEST${NC}   Définit la destination (Défaut: GDrive:)"
    echo -e "  ${GREEN}-u, --usb [NOM]${NC} Utilise une clé USB montée dans /run/media/$USER/ comme destination."
    echo -e "                  Si [NOM] est omis, prend la première clé USB trouvée."
    echo -e "  ${GREEN}-F, --filter F${NC}  Ajoute un fichier entier contenant des règles au filtre rclone."
    echo -e "\n${YELLOW}Exemples d'utilisation:${NC}"
    echo -e "  $0 -m -p                    # Récupère (PULL) depuis GDrive vers $HOME en mode minimal"
    echo -e "  $0 -u                       # Sauvegarde $HOME vers la première clé USB détectée"
    echo -e "  $0 -u MA_CLE -m             # Sauvegarde minimale vers /run/media/$USER/MA_CLE"
    echo -e "  $0 -F /chemin/mon_filtre.txt # Sauvegarde normale en ajoutant un fichier de filtre spécifique"
}

# ==========================================
# --- VÉRIFICATION DE RCLONE ---
# ==========================================
if ! command -v rclone &> /dev/null; then
    echo -e "${YELLOW}⚠️ rclone n'est pas installé. Tentative d'installation via sudo...${NC}"
    sudo -v
    curl https://rclone.org/install.sh | sudo bash
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Erreur lors de l'installation de rclone.${NC}"
        exit 1
    fi
fi

# ==========================================
# --- VARIABLES PAR DÉFAUT ---
# ==========================================
FROM_DIR="$HOME"
TO_REMOTE="GDrive:"
MODE="PUSH"
MINIMAL_MODE=false
EXTRA_FILTERS=()
FILTER_TEMP_FILE="/tmp/rclone-filter-from"

# Nettoyage automatique du fichier temporaire à la sortie (peu importe comment le script se termine)
trap 'rm -f "$FILTER_TEMP_FILE"; echo -e "${BLUE}🧹 Nettoyage: $FILTER_TEMP_FILE supprimé.${NC}"' EXIT

# ==========================================
# --- ANALYSE DES ARGUMENTS ---
# ==========================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--minimal)
            MINIMAL_MODE=true
            shift
            ;;
        -p|--pull)
            MODE="PULL"
            shift
            ;;
        -f|--from)
            if [[ -n "${2:-}" && ! "$2" == -* ]]; then
                FROM_DIR="$2"
                shift 2
            else
                echo -e "${RED}❌ Erreur: L'argument --from nécessite un chemin.${NC}"
                exit 1
            fi
            ;;
        -t|--to)
            if [[ -n "${2:-}" && ! "$2" == -* ]]; then
                TO_REMOTE="$2"
                shift 2
            else
                echo -e "${RED}❌ Erreur: L'argument --to nécessite une destination.${NC}"
                exit 1
            fi
            ;;
        -F|--filter)
            if [[ -n "${2:-}" && ! "$2" == -* ]]; then
                if [[ -f "$2" ]]; then
                    EXTRA_FILTERS+=("$2")
                else
                    echo -e "${RED}❌ Erreur: Le fichier de filtre '$2' est introuvable.${NC}"
                    exit 1
                fi
                shift 2
            else
                echo -e "${RED}❌ Erreur: L'argument --filter nécessite un chemin vers un fichier valide.${NC}"
                exit 1
            fi
            ;;
        -u|--usb)
            USB_BASE="/run/media/$USER"
            
            # Vérifie si le paramètre suivant existe et n'est pas un flag
            if [[ -n "${2:-}" && ! "$2" == -* ]]; then
                USB_PATH="$USB_BASE/$2"
                shift 2
            else
                # Aucune valeur fournie, on cherche la première clé USB
                if [[ -d "$USB_BASE" ]]; then
                    FIRST_USB=$(find "$USB_BASE" -mindepth 1 -maxdepth 1 -type d | head -n 1)
                    if [[ -n "$FIRST_USB" ]]; then
                        USB_PATH="$FIRST_USB"
                    else
                        echo -e "${RED}❌ Erreur: Aucune clé USB montée trouvée dans $USB_BASE.${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}❌ Erreur: Le répertoire $USB_BASE n'existe pas. Aucune clé USB détectée.${NC}"
                    exit 1
                fi
                shift 1
            fi

            # Validation du montage USB
            if [[ ! -d "$USB_PATH" ]]; then
                echo -e "${RED}❌ Erreur: Le répertoire USB '$USB_PATH' n'existe pas ou n'est pas monté.${NC}"
                exit 1
            fi
            
            TO_REMOTE="$USB_PATH"
            echo -e "${CYAN}💾 Cible USB détectée et configurée : $TO_REMOTE${NC}"
            ;;
        *)
            echo -e "${RED}❌ Argument inconnu: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# ==========================================
# --- CONFIGURATION DES SOURCES/DESTINATIONS ---
# ==========================================
if [[ "$MODE" == "PULL" ]]; then
    SOURCE="${TO_REMOTE}"
    DEST="${FROM_DIR}"
    echo -e "🔄 ${YELLOW}Mode: PULL${NC} ($SOURCE ${CYAN}->${NC} $DEST)"
else
    SOURCE="${FROM_DIR}"
    DEST="${TO_REMOTE}"
    echo -e "🔄 ${YELLOW}Mode: PUSH${NC} ($SOURCE ${CYAN}->${NC} $DEST)"
fi

# ==========================================
# --- CONSTRUCTION DU FICHIER DE FILTRE ---
# ==========================================
echo -e "⚙️  ${BLUE}Génération du fichier de filtre temporaire...${NC}"
> "$FILTER_TEMP_FILE"

# 1. Si mode MINIMAL, ajout de la whitelist en priorité absolue
if [ "$MINIMAL_MODE" = true ]; then
    cat <<EOF >> "$FILTER_TEMP_FILE"
+ /Documents/**
+ /.config/rclone/**
+ /.config/keepassxc/**
EOF
fi

# 2. Ajout de la liste des exclusions massives (Prepended before any file append)
cat <<EOF >> "$FILTER_TEMP_FILE"
# ==========================================
# --- 1. SYSTÈME ET SÉCURITÉ (CRITIQUE) ---
# ==========================================
- /.ssh/id_*
- /.ssh/known_hosts
- /.ssh/authorized_keys
- **/.gnupg/S.*
- **/.local/share/Trash/**
- **/lost+found/**
- **/.Xauthority
- **/.ICEauthority
- **/.dbus/**
- **/.gvfs/**
- **/gvfs-metadata/**
- **/.flatpak-info

# ==========================================
# --- 2. NAVIGATEURS (BLOAT & TEMP) ---
# ==========================================
- **/Cache/**
- **/Caches/**
- **/GPUCache/**
- **/Code Cache/**
- **/ShaderCache/**
- **/GrShaderCache/**
- **/ScriptCache/**
- **/Service Worker/CacheStorage/**
- **/Service Worker/ScriptCache/**
- **/*.lock
- **/Singleton*
- **/Safe Browsing/**
- **/DIPS/**
- **/Origin Bounds/**
- **/Heavy Ad Intervention Bots/**
- **/AutofillStates/**
- **/storage/default/**
- **/startupCache/**
- **/thumbnails/**
- **/*-journal/**

# ==========================================
# --- 3. DÉVELOPPEMENT (NODE/PHP/VUE) ---
# ==========================================
- **/node_modules/**
- **/vendor/**
- **/deps/**
- **/image/**
- **/.pnpm_store/**
- **/.npm/**
- **/.yarn/**
- **/.composer/**
- **/build/**
- **/dist/**
- **/out/**
- **/.git/**
- **/.github/**
- **/.idea/**
- **/.vscode/.python/
- **/.next/**
- **/.nuxt/**
- **/.turbo/**
- **/storage/framework/views/**
- **/storage/framework/cache/data/**
- **/logs/**
- **/.phpunit.result.cache

# ==========================================
# --- 4. PYTHON / PYTORCH / C++ ---
# ==========================================
- **/__pycache__/**
- **/.venv/**
- **/venv/**
- **/.ipynb_checkpoints/**
- **/.pio/**
- **/CMakeFiles/**
- **/CMakeCache.txt
- **/cmake-build-debug/**
- **/cmake-build-release/**
- **/*.o
- **/*.a
- **/*.so
- **/*.pyc
- **/.ninja_deps
- **/.ninja_log

# ==========================================
# --- 5. CACHES GÉNÉRIQUES ET ÉTATS ---
# ==========================================
- **/.cache/**
- **/cache/**
- **/*cache/**
- **/*Cache/**
- **/state/**
- **/.local/state/**
- **.sock
- **.tmp
- **.swp
- **/*.bak
- **/.ld.so/**
- **/Trash/**
- **/*LOCK*
- **/*LOG*
- **/.thumbnails/**
- **/thumbs.db
- **/.DS_Store

# ==========================================
# --- 6. UNWANTED DIRS ---
# ==========================================
- **/Downloads/**
- /Downloads/**
- /Download/**
- /.cache/**
- /.bun/**
- /.git/**
- **/waydroid/**
- **/extensions/**
- **/site-packages/**
- /.local/lib/**
- /.local/share/pnpm/**
EOF

# 3. Lecture des fichiers de filtres normaux
FILES_TO_LOAD=("$HOME/.config/rclone/rclone_filter.txt" "$HOME/Documents/rclone_filter.txt")

# 4. Ajout des fichiers minimaux si le mode minimal est activé
if [ "$MINIMAL_MODE" = true ]; then
    FILES_TO_LOAD+=("$HOME/.config/rclone/rclone_filter_minimal.txt" "$HOME/Documents/rclone_filter_minimal.txt")
fi

# 5. Injection du contenu des fichiers locaux (s'ils existent)
for f in "${FILES_TO_LOAD[@]}"; do
    if [ -f "$f" ]; then
        echo -e "📄 ${GREEN}Inclusion du fichier de filtre local : $f${NC}"
        cat "$f" >> "$FILTER_TEMP_FILE"
    fi
done

# 6. Injection des fichiers manuels passés via -F / --filter
for extra_file in "${EXTRA_FILTERS[@]}"; do
    echo -e "📄 ${GREEN}Inclusion du fichier de filtre utilisateur : $extra_file${NC}"
    cat "$extra_file" >> "$FILTER_TEMP_FILE"
done

# 7. Finalisation du mode Minimal (Blacklist globale à la fin)
if [ "$MINIMAL_MODE" = true ]; then
    echo "- *" >> "$FILTER_TEMP_FILE"
    echo -e "🔒 ${YELLOW}Mode Minimal actif : Règle finale '- *' ajoutée.${NC}"
fi

# ==========================================
# --- EXECUTION RCLONE ---
# ==========================================
SPEED_FLAGS="--fast-list --transfers 32 --checkers 64 --drive-chunk-size 128M --buffer-size 64M --use-mmap"
VERBOSE_FLAGS="-vP --stats 1s --stats-one-line"

echo -e "🚀 ${GREEN}Lancement de la synchronisation...${NC}\n"

# La commande finale Rclone
rclone sync "$SOURCE" "$DEST" \
    --filter-from="$FILTER_TEMP_FILE" \
    $SPEED_FLAGS \
    $VERBOSE_FLAGS \
    --drive-pacer-min-sleep 10ms \
    --drive-pacer-burst 200

if [ $? -eq 0 ]; then
    echo -e "\n✅ ${GREEN}Synchronisation terminée avec succès !${NC}"
else
    echo -e "\n❌ ${RED}La synchronisation a rencontré des erreurs. Vérifiez les logs ci-dessus.${NC}"
fi
