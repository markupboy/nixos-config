# Connectivity info for Linux VM
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= blake

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# We need to do some OS switching below.
UNAME := $(shell uname)

# The name of the system configuration in the flake.
ifeq ($(UNAME),Darwin)
NIXNAME ?= macos
else
NIXNAME ?= vm-aarch64
endif

# NixOS configuration built by the cache target, including from Darwin.
NIXCACHE_NAME ?= vm-aarch64

# SSH options
SSH_OPTIONS=-o PubkeyAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

# 1Password vault holding the SSH keys copied into the VM.
OP_VAULT ?= Private

# Where secrets/backup writes and secrets/restore reads. Override to point at
# removable media: make secrets/backup SECRETS_ARCHIVE=/Volumes/usb/secrets.tar.gz.gpg
SECRETS_ARCHIVE ?= $(HOME)/secrets.tar.gz.gpg

# vm/secrets opens one connection per key, so multiplex: the VM password (or
# Touch ID prompt) is only answered once. Unlike SSH_OPTIONS this leaves pubkey
# auth enabled, since vm/bootstrap runs vm/switch first and the authorized keys
# are already in place by the time we get here.
SECRETS_SSH_OPTIONS=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	-o ControlMaster=auto -o ControlPath=/tmp/nixos-config-secrets-%C -o ControlPersist=120

.PHONY: switch
switch:
ifeq ($(UNAME), Darwin)
	nix build ".#darwinConfigurations.${NIXNAME}.system"
	sudo ./result/sw/bin/darwin-rebuild switch --flake "$$(pwd)#${NIXNAME}"
else
	sudo nixos-rebuild switch --flake ".#${NIXNAME}"
endif

.PHONY: test
test:
ifeq ($(UNAME), Darwin)
	nix build ".#darwinConfigurations.${NIXNAME}.system"
	sudo ./result/sw/bin/darwin-rebuild test --flake "$$(pwd)#${NIXNAME}"
else
	sudo nixos-rebuild test --flake ".#$(NIXNAME)"
endif

.PHONY: check
check:
	nix flake check --all-systems --no-build
	nix eval --raw '.#nixosConfigurations.vm-aarch64.config.system.build.toplevel.drvPath' >/dev/null
	nix eval --raw '.#nixosConfigurations.vm-aarch64-utm.config.system.build.toplevel.drvPath' >/dev/null
	nix eval --raw '.#nixosConfigurations.wsl.config.system.build.toplevel.drvPath' >/dev/null
	nix eval --raw '.#darwinConfigurations.macos.config.system.build.toplevel.drvPath' >/dev/null

# This builds the given NixOS configuration and pushes the results to the
# cache. This does not alter the current running system. This requires
# cachix authentication to be configured out of band.
.PHONY: cache
cache:
	# TODO

# Backup secrets so that we can transer them to new machines via
# sneakernet or other means. 1Password is the source of truth; this is the
# hedge against losing access to it. Unlike vm/secrets this has to stage the
# keys on disk, because tar needs real files, so the staging directory is
# removed on every exit path.
.PHONY: secrets/backup
secrets/backup:
	@command -v op >/dev/null || { echo "op CLI not found: brew install 1password-cli"; exit 1; }
	@tmp=$$(mktemp -d) && \
		trap 'rm -rf "$$tmp"' EXIT INT TERM && \
		( umask 077; \
			op item list --vault "$(OP_VAULT)" --categories "SSH Key" --format json \
				| jq -r '.[].title' \
				| while IFS= read -r title; do \
					dest=$$(printf '%s' "$$title" | tr ' ' '_'); \
					echo "==> $$title"; \
					op read "op://$(OP_VAULT)/$$title/private key?ssh-format=openssh" > "$$tmp/$$dest" || exit 1; \
					op read "op://$(OP_VAULT)/$$title/public key" > "$$tmp/$$dest.pub" || exit 1; \
				done ) && \
		cp $(HOME)/.ssh/known_hosts "$$tmp/known_hosts" && \
		tar -C "$$tmp" -czf - . \
			| gpg --symmetric --cipher-algo AES256 --output "$(SECRETS_ARCHIVE)" && \
		echo "wrote $(SECRETS_ARCHIVE)"

.PHONY: secrets/restore
secrets/restore:
	@test -f "$(SECRETS_ARCHIVE)" || { echo "no archive at $(SECRETS_ARCHIVE)"; exit 1; }
	umask 077; mkdir -p $(HOME)/.ssh && \
		gpg --decrypt "$(SECRETS_ARCHIVE)" | tar -C $(HOME)/.ssh -xzf -

# bootstrap a brand new VM. The VM should have NixOS ISO on the CD drive
# and just set the password of the root user to "root". This will install
# NixOS. After installing NixOS, you must reboot and set the root password
# for the next step.
vm/bootstrap0:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
		parted /dev/nvme0n1 -- mklabel gpt; \
		parted /dev/nvme0n1 -- mkpart primary 512MB -8GB; \
		parted /dev/nvme0n1 -- mkpart primary linux-swap -8GB 100\%; \
		parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 512MB; \
		parted /dev/nvme0n1 -- set 3 esp on; \
		sleep 1; \
		mkfs.ext4 -L nixos /dev/nvme0n1p1; \
		mkswap -L swap /dev/nvme0n1p2; \
		mkfs.fat -F 32 -n boot /dev/nvme0n1p3; \
		sleep 1; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount /dev/disk/by-label/boot /mnt/boot; \
		nixos-generate-config --root /mnt; \
		sed --in-place '/system\.stateVersion = .*/a \
			nix.package = pkgs.nixVersions.latest;\n \
			nix.extraOptions = \"experimental-features = nix-command flakes\";\n \
			services.openssh.enable = true;\n \
			services.openssh.settings.PasswordAuthentication = true;\n \
			services.openssh.settings.PermitRootLogin = \"yes\";\n \
			users.users.root.initialPassword = \"root\";\n \
		' /mnt/etc/nixos/configuration.nix; \
		nixos-install --no-root-passwd && reboot; \
	"

# after bootstrap0, run this to finalize. After this, do everything else
# in the VM unless secrets change.
vm/bootstrap:
	NIXUSER=root $(MAKE) vm/copy
	NIXUSER=root $(MAKE) vm/switch
	$(MAKE) vm/secrets
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo reboot; \
	"

# copy our secrets into the VM. The private keys live in 1Password and are
# streamed straight over ssh, so they are never written to the Mac's disk.
# The Mac's ~/.ssh/config is deliberately not copied: its IdentityAgent points
# at a 1Password socket that doesn't exist inside the VM.
vm/secrets:
	@command -v op >/dev/null || { echo "op CLI not found: brew install 1password-cli"; exit 1; }
	@ssh $(SECRETS_SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) "umask 077; mkdir -p ~/.ssh"
	@op item list --vault "$(OP_VAULT)" --categories "SSH Key" --format json \
		| jq -r '.[].title' \
		| while IFS= read -r title; do \
			dest=$$(printf '%s' "$$title" | tr ' ' '_'); \
			echo "==> $$title -> ~/.ssh/$$dest"; \
			priv=$$(op read "op://$(OP_VAULT)/$$title/private key?ssh-format=openssh") || exit 1; \
			pub=$$(op read "op://$(OP_VAULT)/$$title/public key") || exit 1; \
			printf '%s\n' "$$priv" | ssh $(SECRETS_SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) \
				"umask 077; cat > ~/.ssh/$$dest"; \
			printf '%s\n' "$$pub" | ssh $(SECRETS_SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) \
				"cat > ~/.ssh/$$dest.pub && chmod 644 ~/.ssh/$$dest.pub"; \
		done
	rsync -av -e 'ssh $(SECRETS_SSH_OPTIONS) -p$(NIXPORT)' \
		$(HOME)/.ssh/known_hosts $(NIXUSER)@$(NIXADDR):.ssh/known_hosts
	-@ssh $(SECRETS_SSH_OPTIONS) -p$(NIXPORT) -O exit $(NIXUSER)@$(NIXADDR) 2>/dev/null

# copy the Nix configurations into the VM.
vm/copy:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='.git/' \
		--exclude='.git-crypt/' \
		--exclude='iso/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# run the nixos-rebuild switch command. This does NOT copy files so you
# have to run vm/copy before.
vm/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo nixos-rebuild switch --flake \"/nix-config#${NIXNAME}\" \
	"

# Build a WSL installer
.PHONY: wsl
wsl:
	 nix build ".#nixosConfigurations.wsl.config.system.build.installer"
