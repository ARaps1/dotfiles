# LiteLLM proxy for minuet-ai autocomplete (OpenAI-compatible -> AWS Bedrock).
# Auto-sourced in dev-in-docker (via ZSH_CUSTOM) and from .zshrc on personal machines.
#
# Neovim manages the proxy lifecycle (starts it on launch, stops it when the last nvim
# exits); these functions are manual overrides. The proxy binds 127.0.0.1:4000 and uses
# the dev.ai-inference AWS profile (same as pi). Completions need a live `aws sso login`.

# Start the proxy in the background unless it is already running.
bedrock-proxy() {
    if curl -s -o /dev/null --max-time 2 http://127.0.0.1:4000/health/liveliness 2>/dev/null; then
        echo "bedrock proxy already running on 127.0.0.1:4000"
        return 0
    fi
    mkdir -p "$HOME/.local/state"
    PYTHONPATH="$HOME/dotfiles${PYTHONPATH:+:$PYTHONPATH}" AWS_PROFILE=dev.ai-inference nohup litellm \
        --config "$HOME/dotfiles/litellm.yaml" --host 127.0.0.1 --port 4000 \
        >"$HOME/.local/state/bedrock-proxy.log" 2>&1 &
    disown
    echo "bedrock proxy started on 127.0.0.1:4000 (log: ~/.local/state/bedrock-proxy.log)"
}

# Stop the proxy.
bedrock-proxy-stop() {
    if pkill -f 'litellm --config' 2>/dev/null; then
        echo "bedrock proxy stopped"
    else
        echo "bedrock proxy not running"
    fi
}

