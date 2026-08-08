{
  description = "NixOS systems and tools by blake";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # https://github.com/cpick/nix-rosetta-builder
    nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
    nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };

    # Non-flakes

    # Our actual dotfiles. This is the source of truth for all shell wiring:
    # fish conf.d/functions, neovim, ghostty, tmux. Nix installs the binaries,
    # this repo decides how they're configured. Update with:
    #   nix flake update dotfiles
    dotfiles.url = "github:markupboy/dotfiles";
    dotfiles.flake = false;

    # The prompt. conf.d/prompt.fish only sets theme_* variables and prepends
    # ~/.local/share/theme-bobthefish/functions *if it exists*, so supplying the
    # theme through home-manager's plugin mechanism satisfies it unmodified.
    theme-bobthefish.url = "github:oh-my-fish/theme-bobthefish/e3b4d4eafc23516e35f162686f08a42edf844e40";
    theme-bobthefish.flake = false;

    # Consolas patched with Nerd Fonts 3.1.1 + Powerline glyphs. The overlay
    # below turns this into a font package. The family name fontconfig and
    # pango see is "Consolas 7NF" -- NOT the Consolas7NF of the filenames.
    consolas-powerline.url = "github:markupboy/consolas-powerline";
    consolas-powerline.flake = false;
  };

  outputs = { nixpkgs, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      (_final: prev: let
        system = prev.stdenv.hostPlatform.system;
        unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        # gh CLI on stable has bugs.
        gh = unstable.gh;

        # Want the latest version of these
        claude-code = unstable.claude-code;
        cursor-cli = unstable.cursor-cli;

        # Consolas isn't in nixpkgs (it ships with Windows), so we build our
        # own patched copy from the flake input. Going through an input rather
        # than fetchFromGitHub means the hash lives in flake.lock and is
        # updated by `nix flake update consolas-powerline`, not by hand.
        consolas-powerline = prev.stdenvNoCC.mkDerivation {
          pname = "consolas-powerline";
          version = "3.1.1"; # Nerd Fonts patch level, per the repo README

          src = inputs.consolas-powerline;

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            install -Dm444 -t $out/share/fonts/truetype *.ttf
            runHook postInstall
          '';

          meta = {
            description = "Consolas patched with Nerd Fonts (family: Consolas 7NF)";
            license = prev.lib.licenses.unfree;
            platforms = prev.lib.platforms.all;
          };
        };
      })
    ];

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };
  in {
    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "blake";
    };

    nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" {
      system = "aarch64-linux";
      user   = "blake";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
      system = "x86_64-linux";
      user   = "blake";
      wsl    = true;
    };

    darwinConfigurations.macos = mkSystem "macos" {
      system = "aarch64-darwin";
      user   = "blake";
      darwin = true;
    };
  };
}
