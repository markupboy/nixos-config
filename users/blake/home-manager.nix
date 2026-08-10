{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # Link every regular file in `src` individually into `target`, rather than
  # symlinking the directory itself.
  #
  # This matters for fish: home-manager writes its own files into
  # ~/.config/fish/conf.d (one plugin-<name>.fish per entry in
  # programs.fish.plugins), and you cannot have both a directory symlink and
  # generated files inside that directory. Per-file links coexist happily.
  linkInto = target: src:
    lib.mapAttrs'
      (name: _: lib.nameValuePair "${target}/${name}" { source = "${src}/${name}"; })
      (lib.filterAttrs (_: type: type == "regular") (builtins.readDir src));

  # True when this is the graphical Linux VM, which is the only place the i3
  # desktop config applies.
  isDesktop = isLinux && !isWSL;

  # ghostty's config lives in the dotfiles, but the Linux VM needs a few
  # overrides on top of it (i3 draws the borders, and there is no compositor).
  ghosttyConfig =
    if isDesktop then {
      text = builtins.readFile "${inputs.dotfiles}/ghostty/config"
        + "\n"
        + builtins.readFile ./ghostty-linux.conf;
    } else {
      source = "${inputs.dotfiles}/ghostty/config";
    };

  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
    cat "$1" | col -bx | bat --language man --style plain
  ''));
in {
  # Home-manager 22.11 requires this be set. We never set it so we have
  # to use the old state version.
  home.stateVersion = "18.09";

  # Disabled for now since we mismatch our versions. See flake.nix for details.
  home.enableNixpkgsReleaseCheck = false;

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  home.packages = [
    pkgs._1password-cli
    pkgs.asciinema
    pkgs.awscli2
    pkgs.bat
    pkgs.claude-code
    pkgs.cursor-cli
    pkgs.eza
    pkgs.fd
    pkgs.fnm
    pkgs.fzf
    pkgs.gh
    pkgs.gopls
    pkgs.htop
    pkgs.btop
    pkgs.jq # hard dep: fish/functions/{wtpr,wtclean}.fish
    pkgs.mise
    pkgs.ripgrep
    pkgs.tree
    pkgs.watch
    pkgs.wget
    pkgs.vivid # hard dep: fish/conf.d/colors.fish
    pkgs.zoxide
    pkgs.atuin
    pkgs.lazygit
    pkgs.git-lfs
    pkgs.tlrc
    pkgs.tmux
    pkgs.tree-sitter # nvim-treesitter is on `main`, which compiles parsers
    pkgs.luarocks
    pkgs.worktrunk # the `wt` command; fish/functions/wt*.fish drive it

    # Installed as a plain package rather than via programs.neovim, because
    # that module writes ~/.config/nvim/init.lua and we symlink the whole nvim
    # directory out of the dotfiles instead. Mason's unpatched binaries work
    # here because nixos.nix enables programs.nix-ld.
    inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default
  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.cachix
    pkgs.gettext
  ]) ++ (lib.optionals isDesktop [
    pkgs.chromium
    pkgs.clang # treesitter parsers need a C compiler
    pkgs.firefox
    pkgs.ghostty
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  # NOTE: GOPATH/GOROOT are deliberately not set here. fish/conf.d/go.fish
  # owns them (GOPATH=$HOME/Code/go). The upstream config set a conflicting
  # ~/Developer/go, which is why `go install` binaries used to go missing.

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";
  } // (if isDarwin then {
    # See: https://github.com/NixOS/nixpkgs/issues/390751
    DISPLAY = "nixpkgs-390751";
  } else {});

  home.file = {
    ".inputrc".source = ./inputrc;

    # The dotfiles tree itself, read-only out of the nix store.
    # Edits happen on the Mac and arrive here via `nix flake update dotfiles`.
    ".dotfiles".source = inputs.dotfiles;

    ".tmux.conf".source = "${inputs.dotfiles}/tmux/tmux.conf.symlink";
    ".gitignore".source = "${inputs.dotfiles}/git/gitignore.symlink";
  };

  # ~/.Xresources, merged into the X server by the xrdb call in vm-shared.nix's
  # sessionCommands.
  xresources.extraConfig = lib.mkIf isDesktop (builtins.readFile ./desktop/Xresources);

  xdg.configFile =
    # fish: per-file, so home-manager can still drop plugin-*.fish alongside.
    (linkInto "fish/conf.d" "${inputs.dotfiles}/fish/conf.d")
    // (linkInto "fish/functions" "${inputs.dotfiles}/fish/functions")
    // {
      "nvim".source = "${inputs.dotfiles}/nvim";
      "ghostty/config" = ghosttyConfig;
      "ghostty/themes".source = "${inputs.dotfiles}/ghostty/themes";
    }

    # The i3 desktop.
    // lib.optionalAttrs isDesktop {
      "i3/config".source = ./desktop/i3.conf;
      "i3status/config".source = ./desktop/i3status.conf;
      "rofi/config.rasi".source = ./desktop/rofi.rasi;
      "dunst/dunstrc".source = ./desktop/dunstrc;
    }
    ;

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.gpg.enable = !isDarwin;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ./bashrc;
  };

  # The dotfiles own all of fish's behaviour via conf.d
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -g fish_greeting

      function add_blank_line --on-event fish_postexec
        echo ""
      end
    '';

    plugins = [
      { name = "theme-bobthefish"; src = inputs.theme-bobthefish; }
    ];
  };

  # git is the one thing Nix keeps ownership of rather than symlinking from
  # the dotfiles.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
    };
  };

  programs.git = {
    enable = true;

    settings = {
      user.name = "Blake Walters";
      user.email = "blake@markupboy.com";
      github.user = "markupboy";

      core.editor = "nvim";
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      core.excludesFile = "${config.home.homeDirectory}/.gitignore";

      color.ui = true;
      credential.helper = "store"; # want to make this more secure

      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      fetch.prune = true;
      rebase.autoStash = true;
      rerere.enabled = true;

      diff.colorMoved = "default";
      merge.conflictstyle = "zdiff3";
      help.autocorrect = 1;

      alias = {
        co = "checkout";
        cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
      };
    };
  };

  # Per-project flakes. No whitelist
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.npm = {
    enable = isLinux;
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  gtk = lib.mkIf isDesktop {
    enable = true;

    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };

    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.theme = null;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  # The cursor. Size tracks services.xserver.dpi in vm-shared.nix
  home.pointerCursor = lib.mkIf isDesktop {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 48;
    x11.enable = true;
    gtk.enable = true;
  };
}
