{ config, pkgs, lib, currentSystem, currentSystemName, ... }:

{
  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';
  };

  nixpkgs.config.permittedInsecurePackages = [
    # Needed for k2pdfopt 2.53.
    "mupdf-1.17.0"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Some VM firmware only supports this being 0, otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  # Define your hostname.
  networking.hostName = "nixdev";

  # Set your time zone.
  time.timeZone = "America/Denver";

  # nixos-generate-config still emits the false-plus-per-interface pair, so
  # expect to see it again on the next bootstrap; it is not what we want here.
  networking.useDHCP = true;

  # Don't require password for sudo
  security.sudo.wheelNeedsPassword = false;

  # Virtualization settings
  virtualisation.docker.enable = true;

  # Select internationalisation properties.
  i18n = {
    defaultLocale = "en_US.UTF-8";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.mutableUsers = false;

  # Manage fonts. Everything here comes from nixpkgs except Consolas, which
  # the flake.nix overlay builds from our own repo -- see below.
  fonts = {
    fontDir.enable = true;
    enableDefaultPackages = true;

    packages = [
      pkgs.consolas-powerline
      pkgs.noto-fonts
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    cachix
    gnumake
    killall
    xclip
    rofi
    dunst
    libnotify # notify-send, for testing dunst
    xss-lock
    lxqt.lxqt-policykit # auth prompts; Plasma used to supply the agent
    xsetroot
    xdg-utils # xdg-open, so "open link" works from dunst and from apps

    # Make the guest resolution follow the hypervisor window.
    (writeShellScriptBin "display-autofit" ''
      export PATH=${lib.makeBinPath [ xrandr xev coreutils gnused gnugrep gawk ]}:$PATH
      set -u

      apply() {
        local out block
        out=$(xrandr | awk '/ connected/ { print $1; exit }')
        [ -n "$out" ] || return 0

        block=$(xrandr | sed -n "/^''${out} /,/^[^[:space:]]/p")
        printf '%s\n' "$block" | grep -q '[*]+' && return 0

        xrandr --output "$out" --auto
      }

      apply
      [ "''${1:-run}" = once ] && exit 0

      while true; do
        stdbuf -oL xev -root -event randr 2>/dev/null |
          while read -r line; do
            case "$line" in
              RRScreenChangeNotify*) apply ;;
            esac
          done
        sleep 2
      done
    '')

    # Manual one-shot, kept for the times you want to force a refit without
    # waiting for an event.
    (writeShellScriptBin "xrandr-auto" ''
      exec display-autofit once
    '')
  ] ++ lib.optionals (currentSystemName == "vm-aarch64") [
    # This is needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this and seeing
    # if the clipboard sill works.
    gtkmm3
  ];

  services.xserver = {
    enable = true;
    xkb.layout = "us";

    # The VM runs at the host's full Retina resolution (see README), so the
    # guest sees ~2x the pixels for the same physical size. This is the one
    # knob that scales i3, rofi, dunst and GTK together -- if everything is
    # comically large or small, change it here and in desktop/Xresources.
    dpi = 192;

    desktopManager.xterm.enable = false;

    displayManager.lightdm.enable = true;

    # Runs as the user, before i3 starts. The vmware-guest module appends its
    # own vmware-user-suid-wrapper line here too (clipboard + auto-resize).
    displayManager.sessionCommands = ''
      ${pkgs.xset}/bin/xset r rate 200 40

      if [ -f "$HOME/.Xresources" ]; then
        ${pkgs.xrdb}/bin/xrdb -merge "$HOME/.Xresources"
      fi
    '';

    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [ i3status i3lock ];
    };
  };

  services.displayManager.defaultSession = "none+i3";

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "no";

  # Enable flatpak. I don't use any flatpak apps but I do sometimes
  # test them so I keep this enabled.
  services.flatpak.enable = true;

  # Disable the firewall since we're in a VM and we want to make it
  # easy to visit stuff in here. We only use NAT networking anyways.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.09"; # Did you read the comment?
}
