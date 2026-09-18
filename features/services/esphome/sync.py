#!/usr/bin/env python3
"""VYRX ESPHome Microcontroller Declarative GitOps Sync Engine.

Idempotently validates or flashes ESPHome firmware against a declarative
specification and YAML definition generated hermetically by Nix.
"""

import argparse
import os
import subprocess
import sys


def ping_device(ip):
    """Checks if the microcontroller is reachable via ICMP."""
    res = subprocess.run(
        ["ping", "-c", "1", "-W", "2", ip],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return res.returncode == 0


def main():
    parser = argparse.ArgumentParser(
        description="VYRX ESPHome Microcontroller GitOps Sync Engine"
    )
    parser.add_argument(
        "--config", required=True, help="Path to rendered ESPHome YAML file"
    )
    parser.add_argument(
        "--device", required=True, help="Target device IP address"
    )
    parser.add_argument(
        "--name", default="microcontroller", help="Device name"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate configuration and reachability without flashing",
    )
    parser.add_argument(
        "action",
        nargs="?",
        default="switch",
        choices=["switch", "dry-run", "test", "status"],
        help="Action to execute (default: switch)",
    )
    args = parser.parse_args()

    if args.action == "dry-run":
        args.dry_run = True

    mode_tag = " [DRY RUN]" if args.dry_run else ""
    print(f"==> Inspecting ESPHome target '{args.name}' at {args.device}{mode_tag}")
    print(f"    Configuration: {args.config}")

    if not os.path.exists(args.config):
        sys.exit(f"Error: Configuration file '{args.config}' does not exist.")

    # 1. Hermetic Schema & Syntax Validation via esphome CLI
    print("  [*] Validating ESPHome configuration schema...")
    res = subprocess.run(
        ["esphome", "config", args.config],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        print(f"  [!] ESPHome config validation failed:\n{res.stderr or res.stdout}")
        sys.exit(1)
    print("  [✓] ESPHome configuration schema valid.")

    # 2. Check Device Reachability
    online = ping_device(args.device)
    if online:
        print(f"  [✓] Device {args.device} is ONLINE and reachable via ICMP.")
    else:
        print(f"  [!] Device {args.device} is currently OFFLINE / unreachable.")

    if args.dry_run:
        print(f"  [✓] Dry-run completed successfully. No firmware flashed to {args.device}.")
        return

    if not online:
        sys.exit(f"Error: Cannot flash offline target {args.device}. Aborting.")

    # 3. Flashing via OTA
    print(f"  [*] Compiling and uploading firmware OTA to {args.device}...")
    run_res = subprocess.run(
        ["esphome", "run", "--no-logs", "--device", args.device, args.config]
    )
    if run_res.returncode != 0:
        sys.exit(f"Error: ESPHome OTA deployment to {args.device} failed.")

    print(f"  [✓] Firmware successfully deployed to {args.device}.")


if __name__ == "__main__":
    main()
