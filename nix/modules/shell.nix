{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 50000;

    interactiveShellInit = ''
      setopt prompt_subst hist_ignore_dups hist_ignore_space share_history extended_glob

      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list "" 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*:descriptions' format '%F{#6c6c6c}%d%f'
    '';

    promptInit = ''
      autoload -Uz vcs_info add-zsh-hook
      zmodload zsh/datetime

      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#585858'
      ZSH_HIGHLIGHT_STYLES[command]='fg=#87afff'
      ZSH_HIGHLIGHT_STYLES[builtin]='fg=#87afff'
      ZSH_HIGHLIGHT_STYLES[function]='fg=#87afff'
      ZSH_HIGHLIGHT_STYLES[alias]='fg=#87afff'
      ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#afd787'
      ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#afd787'
      ZSH_HIGHLIGHT_STYLES[redirection]='fg=#ffafd7'
      ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ff5f5f'
      ZSH_HIGHLIGHT_STYLES[comment]='fg=#6c6c6c'
      ZSH_HIGHLIGHT_STYLES[default]='fg=#d7d7af'

      zstyle ':vcs_info:*' enable git
      zstyle ':vcs_info:git:*' check-for-changes true
      zstyle ':vcs_info:git:*' unstagedstr '%F{#ffaf5f}*%f'
      zstyle ':vcs_info:git:*' stagedstr '%F{#afd787}+%f'
      zstyle ':vcs_info:git:*' formats ' (%F{#d7afff}%b%f%u%c%m)'
      zstyle ':vcs_info:git:*' actionformats ' (%F{#d7afff}%b%f|%a%u%c%m)'
      zstyle ':vcs_info:git+set-message:*' hooks untracked stash upstream

      +vi-untracked() {
          if [[ -n $(git ls-files --others --exclude-standard --directory --no-empty-directory 2>/dev/null | head -n 1) ]]; then
              hook_com[misc]+='%F{#6c6c6c}?%f'
          fi
      }

      +vi-stash() {
          if git rev-parse --verify --quiet refs/stash >/dev/null 2>&1; then
              hook_com[misc]+='$'
          fi
      }

      +vi-upstream() {
          local -a counts
          counts=(''${(s: :)$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)})
          (( counts[1] )) && hook_com[misc]+=" >''${counts[1]}"
          (( counts[2] )) && hook_com[misc]+=" <''${counts[2]}"
      }

      _prompt_preexec() {
          _prompt_start=$EPOCHREALTIME
      }

      _prompt_precmd() {
          local elapsed=0
          if (( ''${_prompt_start:-0} )); then
              elapsed=$(( EPOCHREALTIME - _prompt_start ))
              unset _prompt_start
          fi
          if (( elapsed > 1 )); then
              RPROMPT="%F{#6c6c6c}$(printf '%.1fs' $elapsed)%f"
          else
              RPROMPT=""
          fi

          vcs_info

          _prompt_nix=""
          if [[ -n ''${IN_NIX_SHELL-} ]]; then
              _prompt_nix=" %F{#5fd7d7}nix%f"
          fi
      }

      add-zsh-hook preexec _prompt_preexec
      add-zsh-hook precmd _prompt_precmd

      PROMPT='%F{#585858}┌ %F{#87afff}%n%F{#585858}@%F{#5fafd7}%m %F{#d7d7af}%(4~:…/%3~:%~)%f''${vcs_info_msg_0_}''${_prompt_nix}
%F{#585858}└ %(?..%F{#ff5f5f}[%?] )%(!.%F{#ff5f5f}.%F{#5fd75f})» %f'
    '';
  };

  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.bashInteractive;
  environment.shells = [ pkgs.zsh ];

  environment.systemPackages = with pkgs; [
    bat
    btop
    curl
    dnsutils
    ethtool
    eza
    fd
    file
    git
    htop
    jq
    lsof
    ncdu
    neovim
    pciutils
    ripgrep
    rsync
    tcpdump
    tmux
    tree
    unzip
    usbutils
    wget
  ];
}
