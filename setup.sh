#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Minimum Neovim version required by plugins (telescope, lspconfig, treesitter)
NVIM_MIN_VERSION="0.10.4"

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
    echo "  deps              - Install external dependencies (ripgrep, fd, tree-sitter, etc.)"
    echo "  pi                - Install Pi agent harness and symlink config"
    echo "  minuet            - Install LiteLLM->Bedrock proxy for minuet AI autocomplete"
    echo "  lazygit           - Install lazygit terminal UI for git"
    echo "  nerd-font         - Install Hack Nerd Font"
    echo "  all               - Run all setup commands"
    echo "  help              - Show this help message"
}

# Detect environment
is_dev_in_docker() {
    [ -d "/home/aurelia" ] && [ -f "/home/aurelia/.zshrc" ]
}

# Compare semver: returns 0 if $1 >= $2
version_gte() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
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

# Ensure tree-sitter-cli is installed via npm (needed for nvim-treesitter main branch)
ensure_tree_sitter_cli() {
    # Remove broken mise shim if it exists
    if [ -f "/mise/shims/tree-sitter" ]; then
        rm -f /mise/shims/tree-sitter
    fi
    # Remove broken mise node_modules version if it exists
    local mise_ts="/mise/installs/node/*/lib/node_modules/tree-sitter-cli"
    rm -rf $mise_ts 2>/dev/null

    # Install via npm if not already working
    if ! tree-sitter --version >/dev/null 2>&1; then
        echo "Installing tree-sitter-cli via npm..."
        npm install -g tree-sitter-cli
    else
        echo "tree-sitter-cli is already installed"
    fi
}

# Create symlinks using stow
create_symlinks() {
    local package=$1
    echo "Creating symlinks for $package..."

    # Ensure stow is installed
    ensure_stow

    # Remove existing config to avoid stow conflicts (trust the repo version)
    local target_dir=""
    case "$package" in
        nvim)
            target_dir="$HOME/.config/nvim"
            ;;
        zsh)
            target_dir="$HOME/.config/zsh"
            ;;
    esac

    if [ -n "$target_dir" ] && [ -d "$target_dir" ] && [ ! -L "$target_dir" ]; then
        echo "Removing existing $package config at $target_dir (trusting repo version)..."
        rm -rf "$target_dir"
    fi

    # Dry-run stow to detect conflicts before applying
    local stow_output
    stow_output=$(stow --no -v -d "$SCRIPT_DIR" -t "$HOME" "$package" 2>&1) || true

    if echo "$stow_output" | grep -q "existing target is not owned by stow"; then
        echo ""
        echo "Stow detected conflicting files for '$package':"
        echo "$stow_output" | grep "existing target is not owned by stow" | sed 's/.*existing target is not owned by stow: /  - /'
        echo ""
        printf "Remove these conflicting files so stow can manage them? [y/N] "
        read -r response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            echo "$stow_output" | grep "existing target is not owned by stow" | sed 's/.*existing target is not owned by stow: //' | while read -r conflict; do
                local conflict_path="$HOME/$conflict"
                if [ -e "$conflict_path" ] || [ -L "$conflict_path" ]; then
                    echo "  Removing: $conflict_path"
                    rm -rf "$conflict_path"
                fi
            done
        else
            echo "Skipping $package symlinks (conflicts unresolved)."
            return 0
        fi
    fi

    # Use stow to create symlinks, targeting $HOME
    stow -R -v -d "$SCRIPT_DIR" -t "$HOME" "$package"
    echo "Symlinks created successfully for $package"
}

# Install external dependencies required by kickstart.nvim
ensure_deps() {
    echo "Checking external dependencies..."

    OS="$(uname -s)"
    case "$OS" in
        Darwin)
            # Ensure Xcode CLI tools are installed (needed for C compiler / treesitter builds)
            if ! xcode-select -p >/dev/null 2>&1; then
                echo "Installing Xcode Command Line Tools..."
                xcode-select --install
                echo "Please re-run this script after Xcode CLI tools finish installing."
                exit 0
            fi

            if command -v brew >/dev/null 2>&1; then
                echo "Installing dependencies via Homebrew..."
                brew install ripgrep fd
            else
                echo "Error: Homebrew is required to install dependencies on macOS."
                exit 1
            fi
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update
                sudo apt-get install -y ripgrep fd-find build-essential unzip
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y ripgrep fd-find gcc make unzip
            else
                echo "Warning: Unsupported package manager. Install ripgrep, fd, and a C compiler manually."
            fi
            ;;
    esac

    # tree-sitter CLI (brew only has the library, not the CLI)
    if ! command -v tree-sitter >/dev/null 2>&1; then
        echo "Installing tree-sitter CLI..."
        if command -v npm >/dev/null 2>&1; then
            npm install -g tree-sitter-cli
        elif command -v cargo >/dev/null 2>&1; then
            cargo install tree-sitter-cli
        else
            echo "Warning: npm or cargo required to install tree-sitter CLI. Install it manually."
        fi
    else
        echo "tree-sitter CLI is already installed"
    fi

    echo "Dependencies check complete!"
}

# Install a Nerd Font
nerd_font_setup() {
    echo "Setting up Nerd Font..."

    OS="$(uname -s)"
    case "$OS" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                brew install --cask font-hack-nerd-font
            else
                echo "Error: Homebrew is required to install Nerd Font on macOS."
                exit 1
            fi
            ;;
        Linux)
            local font_dir="$HOME/.local/share/fonts"
            if [ ! -f "$font_dir/HackNerdFont-Regular.ttf" ]; then
                echo "Downloading Hack Nerd Font..."
                mkdir -p "$font_dir"
                cd /tmp
                curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip
                unzip -o Hack.zip -d "$font_dir"
                rm -f Hack.zip
                fc-cache -fv
            else
                echo "Hack Nerd Font is already installed"
            fi
            ;;
    esac

    echo ""
    echo "Nerd Font setup complete!"
    echo "  → Set your terminal font to 'Hack Nerd Font'"
    echo "  → Set vim.g.have_nerd_font = true in your init.lua"
}

install_nvim_appimage() {
    ARCH=$(uname -m)
    echo "Installing Neovim from AppImage for $ARCH architecture..."

    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        NVIM_RELEASE=https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.appimage
    else
        NVIM_RELEASE=https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.appimage
    fi

    NVIM_PATH=/usr/local/bin/nvim

    # Remove old installation
    sudo rm -f "$NVIM_PATH"
    sudo rm -rf /opt/nvim

    # Download and extract AppImage (FUSE not available in containers)
    cd /tmp
    wget "$NVIM_RELEASE" -O nvim.appimage
    chmod +x nvim.appimage
    ./nvim.appimage --appimage-extract
    sudo mv squashfs-root /opt/nvim
    sudo ln -sf /opt/nvim/usr/bin/nvim "$NVIM_PATH"
    rm -f nvim.appimage

    # Set as default editor on Debian-based systems
    if command -v update-alternatives >/dev/null 2>&1; then
        echo "Setting up Neovim as default editor..."
        sudo update-alternatives --install /usr/bin/editor editor "$NVIM_PATH" 35 && \
        sudo update-alternatives --set editor "$NVIM_PATH"
    fi

    echo "Neovim installation completed via AppImage extract!"
}

# Install or upgrade Neovim to meet minimum version
install_or_upgrade_nvim() {
    OS="$(uname -s)"
    case "$OS" in
        Darwin)
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
}

# Function for Neovim
nvim_setup() {
    UPDATE_FLAG=false

    if [ "$1" = "--update" ]; then
        UPDATE_FLAG=true
        echo "Update flag detected. Will reinstall Neovim."
    fi

    # Install dependencies first
    ensure_deps

    if command -v nvim >/dev/null 2>&1 && [ "$UPDATE_FLAG" = false ]; then
        # Check minimum version
        NVIM_VERSION=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        if version_gte "$NVIM_VERSION" "$NVIM_MIN_VERSION"; then
            echo "Neovim $NVIM_VERSION is installed and meets minimum version ($NVIM_MIN_VERSION)."
        else
            echo "Neovim $NVIM_VERSION is too old (need >= $NVIM_MIN_VERSION). Upgrading..."
            install_or_upgrade_nvim
        fi
    elif [ "$UPDATE_FLAG" = true ] || ! command -v nvim >/dev/null 2>&1; then
        install_or_upgrade_nvim
    fi

    # Ensure tree-sitter-cli is available (for nvim-treesitter main branch)
    if [ "$(uname -s)" = "Linux" ]; then
        ensure_tree_sitter_cli
    fi

    # Create symlinks
    create_symlinks "nvim"
    echo "Neovim setup complete!"
}

install_lazygit_binary() {
    ARCH=$(uname -m)
    echo "Installing lazygit binary for $ARCH architecture..."

    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        LAZYGIT_ARCH=arm64
    else
        LAZYGIT_ARCH=x86_64
    fi

    # Release asset filenames embed the version, so resolve the latest tag first
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')

    cd /tmp
    curl -fLo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit -D -t /usr/local/bin/
    rm -f lazygit lazygit.tar.gz

    echo "lazygit installation completed!"
}

# Function for lazygit
lazygit_setup() {
    echo "Setting up lazygit..."

    if command -v lazygit >/dev/null 2>&1; then
        echo "lazygit is already installed"
        return 0
    fi

    OS="$(uname -s)"
    case "$OS" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                brew install lazygit
            else
                echo "Error: Homebrew is required to install lazygit on macOS."
                exit 1
            fi
            ;;
        Linux)
            install_lazygit_binary
            ;;
        *)
            echo "Error: Unsupported OS: $OS"
            exit 1
            ;;
    esac

    echo "lazygit setup complete!"
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

# Function for Pi agent harness
pi_setup() {
    echo "Setting up Pi agent harness..."

    # Install Pi globally via npm if not present
    if command -v pi >/dev/null 2>&1; then
        echo "Pi is already installed"
    else
        if command -v npm >/dev/null 2>&1; then
            echo "Installing Pi agent harness via npm..."
            npm install -g @earendil-works/pi-coding-agent
        else
            echo "Error: npm is required to install Pi. Install Node.js/npm first."
            exit 1
        fi
    fi

    # Create the sessions directory (runtime directory, not stowed)
    mkdir -p "$HOME/.pi/agent/sessions"

    # Symlink settings.json and mcp.json via stow
    create_symlinks "pi"

    echo "Pi setup complete!"
    echo "  → Config: ~/.pi/agent/settings.json"
    echo "  → Skills: /src/.claude/skills, ~/.claude/skills"
    echo "  → Alias: pi wraps with AWS_PROFILE=dev.ai-inference (via pi.zsh)"
}

# Ensure uv (Python tool manager) is available for installing the LiteLLM proxy
ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
}

# Function for minuet AI autocomplete: a local OpenAI-compatible LiteLLM proxy fronting
# AWS Bedrock. A single shared proxy serves every Neovim instance (all tabs/worktrees).
minuet_setup() {
    echo "Setting up minuet AI autocomplete (LiteLLM -> Bedrock)..."

    ensure_uv

    if uv tool list 2>/dev/null | grep -q '^litellm'; then
        echo "LiteLLM is already installed"
    else
        echo "Installing LiteLLM proxy via uv..."
        uv tool install 'litellm[proxy]'
    fi

    # Link the proxy autostart/helpers (bedrock-proxy.zsh lives in the zsh package)
    create_symlinks "zsh"

    # Pre-install Neovim plugins (minuet) so completion is ready on first launch
    if command -v nvim >/dev/null 2>&1; then
        echo "Pre-installing Neovim plugins (minuet)..."
        if command -v timeout >/dev/null 2>&1; then
            timeout 300 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true
        else
            nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true
        fi
    else
        echo "Neovim not found; run '$0 nvim' first to install the minuet plugin."
    fi

    echo "minuet setup complete!"
    echo "  → Neovim starts the shared proxy on launch and stops it when the last nvim exits"
    echo "  → Manual control: bedrock-proxy / bedrock-proxy-stop"
    echo "  → Needs 'aws sso login' for completions; accept suggestions with <Tab>"
}

# Run all setup commands
all_setup() {
    ensure_deps
    nvim_setup
    tmux_setup
    zsh_setup
    pi_setup
    minuet_setup
    lazygit_setup
    nerd_font_setup
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
    deps)
        ensure_deps
        ;;
    pi)
        pi_setup
        ;;
    minuet)
        minuet_setup
        ;;
    lazygit)
        lazygit_setup
        ;;
    nerd-font)
        nerd_font_setup
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