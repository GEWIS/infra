{ pkgs, ... }:
{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -g fish_greeting

      set -g fish_color_command 87afff
      set -g fish_color_param d7d7af
      set -g fish_color_quote afd787
      set -g fish_color_redirection ffafd7
      set -g fish_color_end ff8700
      set -g fish_color_error ff5f5f
      set -g fish_color_comment 6c6c6c
      set -g fish_color_autosuggestion 585858
      set -g fish_pager_color_prefix 87afff
      set -g fish_pager_color_description 6c6c6c

      set -g __fish_git_prompt_showdirtystate 1
      set -g __fish_git_prompt_showstashstate 1
      set -g __fish_git_prompt_showuntrackedfiles 1
      set -g __fish_git_prompt_showupstream informative
      set -g __fish_git_prompt_char_dirtystate '*'
      set -g __fish_git_prompt_char_stagedstate '+'
      set -g __fish_git_prompt_char_untrackedfiles '?'
      set -g __fish_git_prompt_char_stashstate '$'
      set -g __fish_git_prompt_char_upstream_ahead '>'
      set -g __fish_git_prompt_char_upstream_behind '<'
      set -g __fish_git_prompt_char_upstream_prefix ' '
      set -g __fish_git_prompt_color_branch d7afff
      set -g __fish_git_prompt_color_dirtystate ffaf5f
      set -g __fish_git_prompt_color_stagedstate afd787
      set -g __fish_git_prompt_color_untrackedfiles 6c6c6c
    '';

    promptInit = ''
      function fish_prompt
          set -l last_status $status
          set -l dim (set_color 585858)
          set -l reset (set_color normal)

          set -l marker_color 5fd75f
          if fish_is_root_user
              set marker_color ff5f5f
          end

          set -l failure
          if test $last_status -ne 0
              set failure (set_color ff5f5f) "[$last_status] "
          end

          set -l shell
          if set -q IN_NIX_SHELL
              set shell " " (set_color 5fd7d7) "nix"
          end

          echo -s $dim "┌ " (set_color 87afff) $USER $dim "@" (set_color 5fafd7) (prompt_hostname) \
              " " (set_color d7d7af) (prompt_pwd --full-length-dirs=2) \
              (fish_git_prompt " %s") $shell $reset
          echo -s $dim "└ " $failure (set_color $marker_color) "» " $reset
      end

      function fish_right_prompt
          if test $CMD_DURATION -gt 1000
              echo -s (set_color 6c6c6c) (printf '%.1fs' (math "$CMD_DURATION / 1000")) (set_color normal)
          end
      end
    '';
  };

  users.defaultUserShell = pkgs.fish;
  users.users.root.shell = pkgs.bashInteractive;
  environment.shells = [ pkgs.fish ];

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
