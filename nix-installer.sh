#!/bin/sh

# ==============================================================================
# Determinate Nix Installer Wrapper
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

info() { printf "${BLUE}[INFO]${NC}\t%s\n" "$1"; }
success() { printf "${GREEN}[OK]${NC}\t%s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC}\t%s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC}\t%s\n" "$1"; exit 1; }

check_deps() {
    if ! command -v curl >/dev/null 2>&1; then
        error "Curl Is Required But Not Found! Please Install Curl."
    fi
}

check_existing_nix() {
    if command -v nix >/dev/null 2>&1 || [ -e "/nix/store" ]; then
        success "Nix Is Already Installed!"
        return 0
    fi
    return 1
}

configure_wsl_systemd() {
    printf "Bernays Needs Systemd To Work Properly. Configure It Now? [Y/n] "
    read -r response
    case "$response" in
        [nN][oO]|[nN])
            warn "Skipping Systemd Configuration."
            exit 0
            ;;
        *)
            info "Modifying /etc/wsl.conf..."
            
            if [ ! -f /etc/wsl.conf ]; then
                printf "[boot]\nsystemd=true\n" | sudo tee /etc/wsl.conf >/dev/null
            elif grep -q "\[boot\]" /etc/wsl.conf; then
                printf "\nsystemd=true\n" | sudo tee -a /etc/wsl.conf >/dev/null
            else
                printf "\n[boot]\nsystemd=true\n" | sudo tee -a /etc/wsl.conf >/dev/null
            fi
            
            warn "Action Required: Restart WSL For Changes To Take Effect."
            error "Please Run 'wsl.exe --shutdown' In PowerShell, Then Run This Script Again."
            ;;
    esac
}

get_install_opts() {
    os="$(uname -s)"

    if [ "$os" = "Linux" ]; then
        if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
            
            if systemctl list-unit-files --type=service >/dev/null 2>&1; then
                return 0
            fi

            configured=0
            
            if [ -f /etc/wsl.conf ] && grep -q "systemd=true" /etc/wsl.conf; then
                configured=1
            fi

            if [ "$configured" -eq 1 ]; then
                warn "Systemd Is Enabled In /etc/wsl.conf But Not Running."
                error "Please Run 'wsl.exe --shutdown' In PowerShell To Apply Changes, Then Run This Script Again."
            else
                configure_wsl_systemd
            fi
        else
            if ! command -v systemctl >/dev/null 2>&1; then
                error "Oooh, You're Using a Non-systemd Linux Distribution! Unfortunately, You'll Need To Install Nix On Your Own."
                # echo "--init none"
            fi
        fi
    fi
}

run_installer() {
    args="$1"
    info "Installing Nix (Needed For Bernays)..."
    
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
      sh -s -- install "$args"
}

check_deps

if ! check_existing_nix; then
    OPTS=$(get_install_opts)
    run_installer "$OPTS"
fi

# ==============================================================================
# Bernays Installer
# ==============================================================================

is_in_path() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1" 2>/dev/null || true
}

pick_install_dir() {
  os="$(uname -s 2>/dev/null || echo unknown)"

  for d in "$HOME/.local/bin" "$HOME/bin" "$HOME/.bin"; do
    [ -n "$d" ] || continue
    if is_in_path "$d"; then
      ensure_dir "$d"
      if [ -d "$d" ] && [ -w "$d" ]; then
        echo "$d"
        return 0
      fi
    fi
  done

  oldIFS=$IFS
  IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -d "$d" ] && [ -w "$d" ]; then
      IFS=$oldIFS
      echo "$d"
      return 0
    fi
  done
  IFS=$oldIFS

  for d in "$HOME/.local/bin" "$HOME/bin" "$HOME/.bin"; do
    [ -n "$d" ] || continue
    ensure_dir "$d"
    if [ -d "$d" ] && [ -w "$d" ]; then
      echo "$d"
      return 0
    fi
  done

  if [ "$os" = "Darwin" ]; then
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
      echo /usr/local/bin
      return 0
    fi
  elif [ "$os" = "Linux" ]; then
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
      echo /usr/local/bin
      return 0
    fi
  fi

  return 1
}

mktemp_file() {
  if command -v mktemp >/dev/null 2>&1; then
    mktemp "${TMPDIR:-/tmp}/bernays.XXXXXX"
    return $?
  fi
  echo "${TMPDIR:-/tmp}/bernays.$$"
}

install_outreach_control() {
  info "Installing Bernays..."

  install_dir="$(pick_install_dir)" || error "Could Not Find A Writable Install Directory For Bernays."
  target="$install_dir/bernays"

  tmp="$(mktemp_file)" || error "Could Not Create Temporary File."
  umask 022

  cat > "$tmp" <<'__OUTREACH_CONTROL_SCRIPT__'

  chmod +x "$tmp" 2>/dev/null || true

  if mv "$tmp" "$target" 2>/dev/null; then
    :
  else
    cat "$tmp" > "$target" || error "Could Not Install Bernays To $target"
    rm -f "$tmp" || true
  fi

  chmod +x "$target" || error "Could Not Mark $target As Executable."
  success "Installed Bernays!"

  if ! is_in_path "$install_dir"; then
    warn "Install Directory Is Not On PATH: $install_dir"
    warn "Add It For This Session:"
    warn "  export PATH=\"$install_dir:\$PATH\""
    warn "Add It Permanently By Editing Your Shell Profile (e.g. ~/.profile, ~/.bashrc, ~/.zshrc)."
  fi
}

install_outreach_control
exit 0