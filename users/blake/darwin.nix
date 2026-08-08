{ inputs, pkgs, ... }:

{
  homebrew = {
    enable = true;
    casks  = [
     # "1password"
     # "claude"
     # "cleanshot"
     # "discord"
     # "fantastical"
     # "google-chrome"
     # "istat-menus"
     # "raycast"
     # "slack"
    ];

    brews = [
      "gnupg"
    ];
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.blake = {
    home = "/Users/blake";
    shell = pkgs.fish;
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "blake";
}
