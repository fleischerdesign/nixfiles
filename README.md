# My NixOS Configuration

This repository contains my personal configuration for NixOS and Home Manager, managed using [Nix Flakes](https://nixos.wiki/wiki/Flakes).

## Structure

The configuration is structured as follows:

-   `flake.nix`: The main entry point. Defines the outputs (e.g., NixOS systems, Home Manager configurations) and inputs (dependencies like nixpkgs).
-   `hosts/`: Contains the specific configurations for each machine.
    -   `hostname/`: Directory for a specific host.
        -   `configuration.nix`: The main NixOS configuration for this host.
        -   `hardware-configuration.nix`: Hardware-specific settings (often generated).
-   `home-manager/`: Contains Home Manager configurations, structured per-user.
    -   `user/`: Directory for a specific user.
        - `home.nix`: The main Home Manager entrypoint for the user.
        - `packages.nix`: A list of packages to be installed for the user.
        - `modules/`: User-specific modules for configuring applications like `nixvim` or `codium`.
-   `modules/`: Reusable NixOS modules that can be imported into different host configurations.
-   `packages/`: Contains custom package definitions that are not in nixpkgs.
-   `secrets/`: Contains encrypted secrets managed with `sops-nix`.
    -   `main.yaml`: (As provided by you) Encrypted API keys (OpenAI, Codestral) and other sensitive data.
    -   `.sops.yaml` (optional, can also be configured directly in `flake.nix`): Configuration for `sops`, e.g., which keys are used.

## Automation with `helper.nix`

The `lib/helper.nix` file contains functions that automate the management of modules for both NixOS and Home Manager.

-   **Automatic Module Discovery:** All `.nix` files within the `modules/nixos` and `home-manager/` directories are automatically discovered and imported.
-   **Dynamic `enable` Options:** For each discovered module, a corresponding `enable` option is automatically generated. For example, a module at `modules/nixos/desktop/gnome.nix` creates an option `my.nixos.desktop.gnome.enable`. This allows for easy activation and deactivation of modules within the main configuration.
-   **Layered Home Manager Configuration:** Home Manager modules are structured in two layers: a `default` directory for settings that apply to all users, and a user-specific directory (e.g., `philipp/`) for individual settings. User-specific modules override the default ones.

## Installation / Usage

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd <repository-name>
    ```

2.  **Apply the configuration:**
    Ensure Nix is installed with Flakes enabled. Then run the following command to apply the configuration for a specific host (replace `hostname` with your system's name as defined in `flake.nix`):

    ```bash
    # Apply system configuration and switch to the new system
    sudo nixos-rebuild switch --flake .#hostname

    # Only build and test, without switching
    # nixos-rebuild build --flake .#hostname

    # Apply Home Manager configuration (if defined separately)
    # home-manager switch --flake .#user@hostname
    ```

## Secrets Management (sops-nix)

Secrets are encrypted using [sops](https://github.com/mozilla/sops) and integrated into the NixOS configuration via [sops-nix](https://github.com/Mic92/sops-nix).

-   The secrets are stored encrypted in the `secrets/` directory. The file `secrets/main.yaml` uses `age` for encryption.
-   The recipient's public `age` key is declared within the `secrets/main.yaml` file itself (under `sops.age[].recipient`) or potentially in a separate `.sops.yaml` file in the root directory.
-   To edit the secrets, use the `sops` command:
    ```bash
    sops secrets/main.yaml
    ```
    This opens the decrypted file in your default editor (`$EDITOR`). Upon saving, the file is automatically re-encrypted.
-   The required private `age` key must be accessible, typically located at `~/.config/sops/age/keys.txt`.
-   `sops-nix` ensures that the decrypted secrets are securely passed to the appropriate services or configuration files at build time. Permissions for the decrypted files in the Nix store are also managed by `sops-nix`. Currently, secrets for `openai` and `codestral` are managed in `secrets/main.yaml`.

## Highlights

This configuration includes:

*   **Desktop:** GNOME as the primary desktop environment.
*   **Audio:** Pipewire for modern audio handling.
*   **Development:**
    *   Pre-configured editors like NixVim and VS Codium.
    *   NixVim is set as the default editor.
*   **Gaming:** A dedicated gaming setup to install and manage games.
*   **Custom Packages:** Several applications are packaged manually:
    *   `ficsit`: A Satisfactory mod manager.
    *   `karere`: A GTK4 wrapper for WhatsApp Web.
    *   `lychee-slicer`: A slicer for resin 3D printers.

---