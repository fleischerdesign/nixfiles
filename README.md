# My NixOS Configuration

This repository contains my personal configuration for NixOS and potentially Home Manager, managed using [Nix Flakes](https://nixos.wiki/wiki/Flakes).

## Structure

The configuration is (typically) structured as follows:

-   `flake.nix`: The main entry point. Defines the outputs (e.g., NixOS systems, Home Manager configurations) and inputs (dependencies like nixpkgs).
-   `hosts/`: Contains the specific configurations for each machine.
    -   `hostname/`: Directory for a specific host.
        -   `configuration.nix`: The main NixOS configuration for this host.
        -   `hardware-configuration.nix`: Hardware-specific settings (often generated).
        -   `home.nix` (optional): The Home Manager configuration for this host.
-   `modules/`: Reusable NixOS modules that can be imported into different host configurations.
-   `home/`: General Home Manager configurations or modules.
-   `overlays/`: Package overlays for customizing or adding packages.
-   `secrets/`: Contains encrypted secrets managed with `sops-nix`.
    -   `main.yaml`: (As provided by you) Encrypted API keys (OpenAI, Codestral) and other sensitive data.
    -   `.sops.yaml` (optional, can also be configured directly in `flake.nix`): Configuration for `sops`, e.g., which keys are used.

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

## Highlights / Notes

* Desktop Environment Gnome

---