set -g fish_greeting
set -g fish_cursor_default underscore
set -g fish_cursor_insert underscore
set -g fish_cursor_replace_one underscore
set -g fish_cursor_visual underscore

fish_add_path --prepend ~/.local/bin ~/.npm-global/bin ~/Android/Sdk/platform-tools ~/Android/Sdk/cmdline-tools/latest/bin
if not set -q EDITOR
    set -gx EDITOR 'cybexos-apps edit'
end
if not set -q VISUAL
    set -gx VISUAL 'cybexos-apps edit'
end
set -gx ANDROID_HOME "$HOME/Android/Sdk"
set -gx ANDROID_SDK_ROOT "$ANDROID_HOME"
set -gx RUSTC_WRAPPER sccache
set -gx CARGO_INCREMENTAL 0
set -gx SCCACHE_DIR "$HOME/.cache/sccache"

# Every fish sources this file, including `fish -c` and scripts. Those need
# the PATH and variables above, but not the six processes behind a prompt,
# hooks and aliases they never use.
if status is-interactive
    # Keep the prompt icon accurate on NixOS and inside each Distrobox. One
    # builtin read of os-release; the quotes are optional in that format.
    set -l posh_os_id
    set -l posh_os_like
    if test -r /etc/os-release
        while read -l line
            switch $line
                case 'ID=*'
                    set posh_os_id (string replace -r '^ID=' '' -- $line | string trim -c '"\'')
                case 'ID_LIKE=*'
                    set posh_os_like (string replace -r '^ID_LIKE=' '' -- $line | string trim -c '"\'')
            end
        end </etc/os-release
    end
    switch $posh_os_id
        case nixos
            set -gx POSH_OS_ICON ""
        case debian
            set -gx POSH_OS_ICON ""
        case ubuntu
            set -gx POSH_OS_ICON ""
        case arch
            set -gx POSH_OS_ICON ""
        case alpine
            set -gx POSH_OS_ICON ""
        case opensuse-tumbleweed opensuse-leap opensuse
            set -gx POSH_OS_ICON ""
        case '*'
            if string match -q "*debian*" $posh_os_like
                set -gx POSH_OS_ICON ""
            else if string match -q "*nixos*" $posh_os_like
                set -gx POSH_OS_ICON ""
            else if string match -q "*arch*" $posh_os_like
                set -gx POSH_OS_ICON ""
            else
                set -gx POSH_OS_ICON ""
            end
    end

    if command -q oh-my-posh
        oh-my-posh init fish --config ~/.config/oh-my-posh/EDM115-newline2.omp.json | source
    end
    if command -q zoxide
        zoxide init fish | source
    end
    if command -q fzf
        fzf --fish | source 2>/dev/null
    end
    if command -q direnv
        direnv hook fish | source
    end

    alias ls='eza --icons'
    alias ll='eza --icons -la'
    alias la='eza --icons -A'
    alias l='eza --icons -CF'
    alias update='cybex update check'
    alias a='cybex agent'
    # Product default for interactive Codex; `command codex` bypasses this alias.
    alias codex='codex --dangerously-bypass-approvals-and-sandbox'
    alias claude='claude --dangerously-skip-permissions'
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline'
    alias lg='lazygit'
    alias hypr-reload='hyprctl reload'
    alias hypr-monitors='hyprctl monitors'
    alias hypr-workspaces='hyprctl workspaces'
    alias ..='cd ..'
    alias ...='cd ../..'

    # Plain `fastfetch` in kitty shows Wiz through kitty's graphics protocol.
    # The default config's logo is $CYBEXOS_FASTFETCH_LOGO, else the braille
    # logo. This sets it, and the picture's height in rows, only when the config
    # names it, this shell runs in kitty itself (not in tmux, over ssh or in a
    # terminal started from kitty) and fastfetch writes to it. Arguments, a pipe
    # or NO_COLOR keep the braille logo: where fastfetch cannot draw a picture
    # it prints the file as text. `command fastfetch` skips this.
    function fastfetch --wraps fastfetch --description 'fastfetch, with Wiz in kitty'
        set -l wiz /run/current-system/sw/share/cybexos/wiz/terminal/idle.png
        set -l config ~/.config/fastfetch/config.jsonc
        test -n "$XDG_CONFIG_HOME"; and set config $XDG_CONFIG_HOME/fastfetch/config.jsonc
        set -l parent (string replace -rf '^PPid:\s+' '' </proc/$fish_pid/status)
        set -l terminal
        if test (count $argv) -eq 0; and isatty stdout; and not set -q NO_COLOR
            and test -r $wiz -a -r $config -a -n "$parent"
            and string match -q '*${CYBEXOS_FASTFETCH_LOGO:-*' <$config
            and read terminal </proc/$parent/comm
            and contains -- $terminal kitty .kitty-wrapped
            CYBEXOS_FASTFETCH_LOGO=$wiz command fastfetch --logo-height 9
        else
            command fastfetch $argv
        end
    end
end
