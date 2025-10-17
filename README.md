# My NixOS Configuration

This repository contains my personal configuration for NixOS and Home Manager, managed using [Nix Flakes](https://nixos.wiki/wiki/Flakes).

## Structure

The configuration is highly modular and automated, with the following directory structure:

-   `flake.nix`: The main entry point. It defines the NixOS systems (`yorke` and `jello`) and pulls in all necessary inputs like `nixpkgs`, `home-manager`, and other dependencies.

-   `lib/helper.nix`: The core of the automation. It contains helper functions to build systems, discover modules, and generate configuration options dynamically.

-   `hosts/`: Contains the machine-specific configurations.
    -   `base.nix`: A foundational configuration that is applied to all hosts. It sets up things like flakes, timezone, and basic system packages.
    -   `yorke/`, `jello/`: Directories for specific hosts, each containing a `configuration.nix` to define host-specific settings and enable desired modules.

-   `home-manager/`: Contains Home Manager configurations, structured in a layered approach.
    -   `default/`: Contains modules with default settings and packages (`direnv`, `fish`, `nil`) that apply to all users.
    -   `philipp/`: A user-specific directory containing personal configurations for packages, `codium`, `nixvim`, and GNOME settings via `dconf`.

-   `modules/nixos/`: A collection of reusable NixOS modules that can be enabled on a per-host basis. This includes modules for `boot`, `audio` (Pipewire), `desktop` (GNOME), and `gaming`.

-   `overlays/`: Contains Nixpkgs overlays. For example, `pip-on-top/` patches the `pip-on-top` GNOME extension for German localization.

-   `packages/`: Contains custom package definitions for applications not found in `nixpkgs`, such as `ficsit`, `karere`, and `lychee-slicer`.

## Automation with `helper.nix`

The `lib/helper.nix` file is central to this configuration and provides several key functions:

-   **`mkSystem`:** This function builds a complete NixOS system. It takes the system's architecture, hostname, inputs, user configurations, and overlays as arguments, and assembles the final system configuration from the various parts (`base.nix`, host-specific configuration, and modules).

-   **Automatic Module Discovery:** The helper automatically scans the `modules/nixos/` directory and generates a corresponding `enable` option for each `.nix` file. For example, a module at `modules/nixos/desktop/gnome.nix` creates an option `my.nixos.desktop.gnome.enable`. This allows for easy activation and deactivation of modules within a host's `configuration.nix`.

-   **Layered Home Manager Configuration:** The `mkSystem` function also manages Home Manager configurations. It combines a `default` profile (from `home-manager/default`) with user-specific profiles (e.g., `home-manager/philipp`). User-specific modules in `home-manager/<user>/modules/` also get dynamic `enable` options under the `my.homeManager` attribute set.

## Installation / Usage

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd <repository-name>
    ```

2.  **Apply the configuration:**
    Ensure Nix is installed with Flakes enabled. Then run the following command to apply the configuration for a specific host (e.g., `yorke` or `jello`):

    ```bash
    # Apply system configuration and switch to the new system
    sudo nixos-rebuild switch --flake .#yorke

    # Only build and test the configuration without switching
    nixos-rebuild dry-build --flake .#jello
    ```

    Home Manager configurations are automatically applied as part of the system build, so a separate `home-manager switch` is not necessary.

## Highlights

-   **Systems:** The configuration manages two systems: `yorke` (AMD) and `jello` (Intel).
-   **Desktop Environment:** A customized GNOME desktop with several extensions like `blur-my-shell`, `gsconnect`, `dash-to-dock`, and `paperwm`.
-   **Development:** A pre-configured development environment including:
    -   **NixVim:** Set as the default editor with plugins for LSP, fuzzy finding (Telescope), and more.
    -   **VS Codium:** Configured with a set of extensions for web development, Nix, Java, and more.
-   **Gaming:** A dedicated gaming setup with Steam, Lutris, and Sunshine for game streaming.
-   **Shell:** Fish is the default shell, integrated with `direnv` for automatic environment loading.
-   **Custom Packages:** Several applications are packaged manually:
    -   `ficsit`: A Satisfactory mod manager.
    -   `karere`: A GTK4 wrapper for WhatsApp Web.
    -   `lychee-slicer`: A slicer for resin 3D printers.
-   **Overlays:** Includes an overlay to patch the `pip-on-top` GNOME extension for German localization.
