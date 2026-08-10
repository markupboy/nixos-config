# NixOS System Configurations

This repository contains my NixOS system configurations - a heavily modified
version of [Mitchell Hashimoto's](https://github.com/mitchellh/nixos-config).

## How I Work

I'm using macOS as the host OS and NixOS within a VM as development environment.
I use the graphical applications on the host (browser, calendars, mail app,
iMessage, etc.) but am shifting more and more dev-related tasks to the VM
(editor, compilation, databases, etc.).

Here is what it ends up looking like:

![Screenshot](https://raw.githubusercontent.com/markupboy/nixos-config/main/.github/images/screenshot.jpg)

## Setup (VM)

Video: <https://www.youtube.com/watch?v=ubDMLoWz76U>

**Note:** This setup guide covers VMware Fusion because that is the hypervisor
I use day to day. A separate UTM configuration is also available.

You can download the NixOS ISO from the
[official NixOS download page](https://nixos.org/download.html#nixos-iso).
Use the `aarch64` ISO with the maintained VM configurations in this repository.

Create a VMware Fusion VM with the following settings. The primary VM
configuration targets VMware Fusion; use the separate UTM target for UTM.

* ISO: NixOS 25.05 or later.
* Disk: NVME 150 GB+
* CPU/Memory: I give at least half my cores and half my RAM, as much as you can.
* Graphics: Full acceleration, full resolution, maximum graphics RAM.
* Network: Shared with my Mac.
* Remove sound card, remove video camera, remove printer.
* Profile: Disable almost all keybindings
* Boot Mode: UEFI

Boot the VM, and using the graphical console, change the root password to "root":

```
$ sudo su
$ passwd
# change to root
```

At this point, verify `/dev/nvme0n1` exists. This is the expected block device
where the Makefile will install the OS.

Also at this point, I recommend making a snapshot in case anything goes wrong.
I usually call this snapshot "prebootstrap0". This is entirely optional,
but it'll make it super easy to go back and retry if things go wrong.

Run `ip addr` and get the IP address of the first device. It is probably
`192.168.58.XXX`, but it can be anything. I prefer to use bridge networking
instead of sharing with my mac host in order to get a true IP on the network
(and ensure no DNS weirdness) but that's all personal choice. In a terminal with
this repository set this to the `NIXADDR` env var:

```
export NIXADDR=<VM ip address>
```

The Makefile defaults to the macOS configuration when run on Darwin. Before
bootstrapping an ARM-based VM, set `NIXNAME` to the appropriate VM
configuration:

```
export NIXNAME=vm-aarch64
```

**Other Hypervisors:** If you are using UTM, use `vm-aarch64-utm`. Note that
the UTM environment isn't exactly equivalent to VMware, but both work.

Perform the initial bootstrap. This will install NixOS on the VM disk image
but will not setup any other configurations yet. This prepares the VM for
any NixOS customization:

```
make vm/bootstrap0
```

After the VM reboots, run the full bootstrap, this will finalize the
NixOS customization using this configuration:

```
make vm/bootstrap
```

You should have a graphical functioning dev VM.

## Setup (macOS/Darwin)

**THIS IS OPTIONAL AND UNRELATED TO THE VM WORK.** I recommend you ignore
this unless you're interested in using Nix to manage your Mac too.

I share some of my Nix configurations with my Mac host and use Nix
to manage _some_ aspects of my macOS installation, too. This uses the
[nix-darwin](https://github.com/LnL7/nix-darwin) project. I don't manage
_everything_ with Nix, for example I don't manage apps, some of my system
settings, Homebrew, etc. I plan to migrate some of those in time.

To utilize the Mac setup, first install Nix using some Nix installer.
There are two great installers right now:
[nix-installer](https://github.com/DeterminateSystems/nix-installer)
by Determinate Systems and [Flox](https://floxdev.com/). The point of both
for my configs is just to get the `nix` CLI with flake support installed.

Once installed, clone this repo and run `make`. If there are any errors,
follow the error message (some folders may need permissions changed,
some files may need to be deleted). That's it.

**WARNING: Don't do this without reading the source.** This repository
is and always has been _my_ configurations. If you blindly run this,
your system may be changed in ways that you don't want. Read my source!

## Setup (WSL)

**THIS IS OPTIONAL AND UNRELATED TO THE VM WORK.** I recommend you ignore
this unless you're interested in using Nix to manage your WSL
(Windows Subsystem for Linux) environment, too.

I use Nix to build a WSL root tarball for Windows. I then have my entire
Nix environment on Windows in WSL too, which I use to for example run
Neovim amongst other things. My general workflow is that I only modify
my WSL environment outside of WSL, rebuild my root filesystem, and
recreate the WSL distribution each time there are system changes. My system
changes are rare enough that this is not annoying at all.

To create a WSL root tarball, you must be running on a Linux machine
that is able to build `x86_64` binaries (either directly or cross-compiling).
My `aarch64` VMs are all properly configured to cross-compile to `x86_64`
so if you're using my NixOS configurations you're already good to go.

Run `make wsl`. This will take some time but will ultimately output
a tarball in `./result/tarball`. Copy that to your Windows machine.
Once it is copied over, run the following steps on Windows:

```
$ wsl --import nixos .\nixos .\path\to\tarball.tar.gz
...

$ wsl -d nixos
...

# Optionally, make it the default
$ wsl -s nixos
```

After the `wsl -d` command, you should be dropped into the Nix environment.
_Voila!_
