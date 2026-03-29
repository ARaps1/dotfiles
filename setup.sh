#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Show help menu
show_help() {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo "Available commands:"
    echo "  nvim              - Install Neovim and symlink config"
    echo "                      Options:"
    echo "                        --update  Force reinstallation even if already installed"
    echo "  tmux              - Install tmux and tmux plugin manager"
    echo "  zsh               - Install zsh customizations (aliases, env, etc.)"
    echo "  git               - Configure Git with custom settings"
    echo "  all               - Run all setup commands"
    echo "  help              - Show this help message"
}

# Detect environment
is_dev_in_docker() {
    [ -d "/home/aurelia" ] && [ -f "/home/aurelia/.zshrc" ]
}

# Check and install stow if needed
ensure_stow() {
    if ! command -v stow >/dev/null 2>&1; then
        echo "GNU Stow is not installed. Installing it now..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y stow
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y stow
        elif command -v brew >/dev/null 2>&1; then
            brew install stow
        else
            echo "Error: Unable to install GNU Stow. Unsupported package manager."
            exit 1
        fi
    fi
}

# Create symlinks using stow
create_symlinks() {
    local package=$1
    echo "Creating symlinks for $package..."

    # Ensure stow is installed
    ensure_stow

    # Use stow to create symlinks, targeting $HOME
    stow -R -v -d "$SCRIPT_DIR" -t "$HOME" "$package"
    echo "Symlinks created successfully for $package"
}

# Helper function to install Neovim AppImage (for Linux)
install_nvim_appimage() {
    ARCH=$(uname -m)
    echo "Installing Neovim from AppImage for $ARCH architecture..."

    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        NVIM_RELEASE=https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.appimage
    else
        NVIM_RELEASE=https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.appimage
    fi

    NVIM_PATH=/usr/local/bin/nvim

    sudo rm -f "$NVIM_PATH"
    sudo wget "$NVIM_RELEASE" -O "$NVIM_PATH"
    sudo chmod +x "$NVIM_PATH"

    # Set as default editor on Debian-based systems
    if command -v update-alternatives >/dev/null 2>&1; then
        echo "Setting up Neovim as default editor..."
        sudo update-alternatives --install /usr/bin/editor editor "$NVIM_PATH" 35 && \
        sudo update-alternatives --set editor "$NVIM_PATH"
    fi

    echo "Neovim installation completed via AppImage!"
}

# Function for Neovim
nvim_setup() {
    UPDATE_FLAG=false

    if [ "$1" = "--update" ]; then
        UPDATE_FLAG=true
        echo "Update flag detected. Will reinstall Neovim."
    fi

    # Check if nvim is already installed
    if command -v nvim >/dev/null 2>&1 && [ "$UPDATE_FLAG" = false ]; then
        echo "Neovim is already installed. Use --update flag to force reinstallation."
    else
        OS="$(uname -s)"
        case "$OS" in
            Darwin)
                # macOS
                if command -v brew >/dev/null 2>&1; then
                    brew install neovim || brew upgrade neovim
                else
                    echo "Error: Homebrew is required to install Neovim on macOS."
                    exit 1
                fi
                ;;
            Linux)
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y neovim python3-neovim
                else
                    install_nvim_appimage
                fi
                ;;
            *)
                echo "Error: Unsupported OS: $OS"
                exit 1
                ;;
        esac
    fi

    # Create symlinks
    create_symlinks "nvim"
    echo "Neovim setup complete!"
}

# Function for tmux
tmux_setup() {
    echo "Setting up tmux..."

    # Check if tmux is already installed
    if command -v tmux >/dev/null 2>&1; then
        echo "tmux is already installed"
    else
        OS="$(uname -s)"
        case "$OS" in
            Darwin)
                if command -v brew >/dev/null 2>&1; then
                    brew install tmux
                else
                    echo "Error: Homebrew is required to install tmux on macOS."
                    exit 1
                fi
                ;;
            Linux)
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get install -y xsel tmux
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y xsel tmux
                else
                    echo "Error: Unsupported package manager."
                    exit 1
                fi
                ;;
        esac
    fi

    # Install tmux plugin manager if not already installed
    TPM_PATH="$HOME/.tmux/plugins/tpm"
    if [ ! -d "$TPM_PATH" ]; then
        echo "Installing Tmux Plugin Manager..."
        git clone https://github.com/tmux-plugins/tpm "$TPM_PATH"
    else
        echo "Tmux Plugin Manager is already installed"
    fi

    # Create symlinks
    create_symlinks "tmux"
    echo "tmux setup complete!"
}

# Function for zsh customizations
zsh_setup() {
    echo "Setting up zsh customizations..."

    # In dev-in-docker, ~/.config/zsh/ is ZSH_CUSTOM and files auto-source.
    # On personal machines, we need to source them from .zshrc.
    create_symlinks "zsh"

    # If NOT in dev-in-docker, ensure .zshrc sources ~/.config/zsh/*.zsh
    if ! is_dev_in_docker; then
        ZSHRC="$HOME/.zshrc"
        SOURCE_BLOCK='# Source custom zsh config files
if [ -d "$HOME/.config/zsh" ]; then
    for rc in "$HOME/.config/zsh"/*.zsh; do
        [ -f "$rc" ] && . "$rc"
    done
    unset rc
fi'

        if [ -f "$ZSHRC" ] && ! grep -q 'Source custom zsh config files' "$ZSHRC"; then
            echo "" >> "$ZSHRC"
            echo "$SOURCE_BLOCK" >> "$ZSHRC"
            echo "Added zsh config sourcing to $ZSHRC"
        elif [ ! -f "$ZSHRC" ]; then
            echo "$SOURCE_BLOCK" > "$ZSHRC"
            echo "Created $ZSHRC with config sourcing"
        else
            echo "zsh config sourcing already present in $ZSHRC"
        fi
    else
        echo "Dev-in-docker detected: ~/.config/zsh/ is auto-sourced via ZSH_CUSTOM"
    fi

    echo "zsh setup complete!"
}

# Function for Git configuration
git_setup() {
    echo "Setting up Git configuration..."

    # In dev-in-docker, ~/.config/git/config persists (not ~/.gitconfig).
    # On personal machines, stow will create ~/.config/git/config which git reads by default.
    create_symlinks "git"

    echo "Git setup complete!"
    echo ""
    echo "IMPORTANT: Edit ~/.config/git/config (or the file in this repo at git/.config/git/config)"
    echo "and fill in your name and email. Do NOT put work-specific credentials in this public repo."
    echo "Use includeIf to conditionally load work-specific config:"
    echo '  [includeIf "gitdir:~/work/"]'
    echo '      path = ~/.config/git/config-work'
}

# Run all setup commands
all_setup() {
    nvim_setup
    tmux_setup
    zsh_setup
    git_setup
}

# Main execution
case "$1" in
    nvim)
        nvim_setup "$2"
        ;;
    tmux)
        tmux_setup
        ;;
    zsh)
        zsh_setup
        ;;
    git)
        git_setup
        ;;
    all)
        all_setup
        ;;
    help)
        show_help
        ;;
    *)
        echo "Error: Invalid command."
        show_help
        exit 1
        ;;
esac

exit 0
