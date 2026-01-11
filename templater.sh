#!/bin/sh

set -e

TEMPLATE_REPO="https://github.com/ToxicPine/bernays.git"
MAX_SEARCH_DEPTH=5

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

info() { printf "${BLUE}[INFO]${NC}\t%s\n" "$1"; }
success() { printf "${GREEN}[OK]${NC}\t%s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC}\t%s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC}\t%s\n" "$1"; exit 1; }

find_flake_root() {
    dir="$PWD"
    counter=0

    while [ "$counter" -lt "$MAX_SEARCH_DEPTH" ]; do
        if [ -f "$dir/flake.nix" ]; then
            echo "$dir"
            return 0
        fi
        
        if [ "$dir" = "/" ]; then
            return 1
        fi

        dir=$(dirname "$dir")
        counter=$((counter + 1))
    done

    return 1
}

do_enter() {
    PROJECT_ROOT=$(find_flake_root)
    
    if [ -z "$PROJECT_ROOT" ]; then
        error "Project Not Found. You Can Create A New Project With \`bernays create PROJECT_NAME\`"
    fi

    FLAKE_FILE="$PROJECT_ROOT/flake.nix"
    if ! grep -q "\[bernays\]" "$FLAKE_FILE"; then
        error "Invalid Project, Have You Changed The flake.nix Description?"
    fi
    
    cd "$PROJECT_ROOT"
    exec nix develop
}

do_create() {
    target_dir="$1"

    if [ -z "$target_dir" ]; then
        error "Usage: $0 create <folder_name>"
    fi

    if [ -d "$target_dir" ]; then
        error "Cannot Create Project: Directory '$target_dir' Already Exists!"
    fi

    abs_target=$(cd "$(dirname "$target_dir")" 2>/dev/null && pwd)/$(basename "$target_dir")

    rel_target=$(realpath --relative-to="$PWD" "$abs_target" 2>/dev/null || echo "$target_dir")
    
    info "Creating New Project At $rel_target..."

    nix shell nixpkgs#git --command sh -c "
        export GIT_CONFIG_GLOBAL=/dev/null
        export GIT_CONFIG_SYSTEM=/dev/null
        
        git clone --depth 1 \"$TEMPLATE_REPO\" \"$target_dir\"
    "

    if [ ! -d "$target_dir" ]; then
        error "Cannot Create Project: Perhaps Your Internet Connection Is Down?"
    fi

    rm -rf "$target_dir/.git"
    
    cd "$target_dir"
    
    nix shell nixpkgs#git --command sh -c "
        export GIT_CONFIG_GLOBAL=/dev/null
        export GIT_CONFIG_SYSTEM=/dev/null
        
        git init -q
        git add -A
        git commit -q -m 'Initial Commit'
    "

    success "Project Created!"
    
    exec nix develop
}

if ! command -v nix >/dev/null 2>&1; then
    error "Nix Is Not Installed! Try Running: \`/nix/nix-installer install\`"
fi

COMMAND="$1"
ARG="$2"

case "$COMMAND" in
    create)
        do_create "$ARG"
        ;;
    "")
        do_enter
        ;;
    "develop")
        do_enter
        ;;
    *)
        echo "Usage:"
        echo "  $0              (Enter Bernays Shell)"
        echo "  $0 create <dir> (Create New Bernays Project)"
        echo "  $0 develop      (Enter Bernays Development Shell)"
        exit 1
        ;;
esac