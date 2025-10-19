#!/bin/bash
# Profile Nix evaluation für verschiedene Teile

set -e

echo "=== Nix Evaluation Profiling ==="
echo ""

# 1. Nur die Basis-Config
echo "1. Base config only (ohne Module):"
time nix eval '.#nixosConfigurations.yorke.config.system' --apply 'x: 1' > /dev/null 2>&1
echo ""

# 2. Mit NixOS Modulen
echo "2. With NixOS modules:"
time nix eval '.#nixosConfigurations.yorke.config.my.nixos' --json > /dev/null 2>&1
echo ""

# 3. Home Manager User Config
echo "3. Home Manager user config:"
time nix eval '.#nixosConfigurations.yorke.config.home-manager.users.philipp' --apply 'x: 1' > /dev/null 2>&1
echo ""

# 4. Einzelne teure Module testen
echo "4. Testing individual Home Manager modules:"
echo ""

echo "  a) nixvim:"
time nix eval '.#nixosConfigurations.yorke.config.home-manager.users.philipp.programs.nixvim' --apply 'x: 1' > /dev/null 2>&1
echo ""

echo "  b) spicetify:"
time nix eval '.#nixosConfigurations.yorke.config.home-manager.users.philipp.programs.spicetify' --apply 'x: 1' > /dev/null 2>&1
echo ""

echo "  c) vscode:"
time nix eval '.#nixosConfigurations.yorke.config.home-manager.users.philipp.programs.vscode' --apply 'x: 1' > /dev/null 2>&1
echo ""

echo "  d) niri:"
time nix eval '.#nixosConfigurations.yorke.config.home-manager.users.philipp.programs.niri' --apply 'x: 1' > /dev/null 2>&1
echo ""

# 5. Full config
echo "5. Full system config (toplevel):"
time nix eval '.#nixosConfigurations.yorke.config.system.build.toplevel' --apply 'x: 1' > /dev/null 2>&1
