{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  # We require this because we use lazy.nvim against the best wishes
  # a pure Nix system so this lets those unpatched binaries run.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  users.users.blake = {
    isNormalUser = true;
    home = "/home/blake";
    extraGroups = [ "docker" "lxd" "wheel" ];
    shell = pkgs.fish;
    hashedPassword = "$6$oqtVVUi8u4jQvz2n$5X2BGyHhJOmvIx3WzJ9h1vGjZwkR/8mxl8fbEjtIS0v0NPxNcYtpVvI0k4EwJAHiBiP44KcRJxWszwgmr0Ols0";
    # The keys 1Password serves over its agent on the Mac. Regenerate with:
    #   SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ssh-add -L
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0ABb2H+s+yjin4zZIdZYhg0/Il9+ozB+m8A8tQCMq1srzJlnpIA4ieSiAJbqI/6bOwoiexEAxLCYEll0C9pSYnteAFL1SZZkB9ojB0ujkHA1jZDQgFVHf2rjJewJEefAjhwfcmVO9XdcgRlWJh9OZoMsADfIiBgkdt65b+p7PgzQqO4SraIykhVm56xtexDBKUU0HKeW7oqB+MlSXEoVYCeGj6QZohrkHJZKAu/Zpx+7FxgSXALFI4AUM2/skYTsayEj42FHr9nIwWbTdzFYF3q2P5y/MO25p84uI2c2zF/nHRZUbRQrq/BuhHPBPVTDM0cJ//F54geu15EmsDlTD phobos id_rsa"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPuFf9VwhxKP9WPjNSlMkVzJHyFIU3gsicrwBRJwacoN id_ed25519"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHW89CVoKFkVqJqIwGKZuuU+ejTdAMAK635YR+IDBJJa gitea"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMXiXXxJNRdVUn5cK/E7HnB5CUUjokSczF2IvAavlkXq gitlab"
    ];
  };
}
