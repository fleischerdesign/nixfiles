#!/usr/bin/env python3
"""VYRX ESPHome Microcontroller Declarative GitOps Sync Engine.

Validates a hermetically rendered ESPHome configuration, resolves the device on the local
segment by MAC address, renders its credentials from the SOPS-managed secret files, and flashes
it over the air.

Credentials are never passed in on the command line and never stored: ESPHome resolves its
`!secret` references from a `secrets.yaml` next to the configuration, so the engine assembles
one in a private temporary directory, uses it, and deletes it. The compiled firmware therefore
carries the secrets, but the build host only holds them for the duration of a flash.

The device address is the reservation for its MAC in the topology: the firmware takes its lease
from DHCP and that reservation is what pins the address down. During the LAN migration the device
is still on the old subnet, so the address is passed explicitly for the first flash.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

# The build host holds the secrets only while flashing; a per-flash temp dir keeps the code
# simple and leaves nothing behind, at the cost of recompiling (a full ESP8266 build per flash).
SECRET_FILES = {
    "api_key": "api_key",
    "ota_password": "ota_password",
    "fallback_ap_password": "ap_password",
}
PLACEHOLDER = "CHANGE_ME"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def read_secret(path, label):
    if not path or not os.path.exists(path):
        sys.exit(f"Error: missing {label} at {path or '<not configured>'} (is sops-nix active?)")
    value = open(path).read().strip()
    if not value or value == PLACEHOLDER:
        sys.exit(f"Error: {label} at {path} is empty or still the {PLACEHOLDER} placeholder.")
    return value


def local_broadcasts():
    """Broadcast addresses of the IPv4 networks this host is attached to."""
    out = run(["ip", "-4", "-o", "addr", "show"]).stdout
    found = []
    for line in out.splitlines():
        if "brd" in line:
            found.append(line.split("brd")[1].split()[0])
        else:
            m = re.search(r"inet (\d+\.\d+\.\d+\.\d+/\d+)", line)
            if m:
                found.append(str(ipaddress.ip_network(m.group(1), strict=False).broadcast_address))
    return found


def find_by_mac(mac):
    """Current IPv4 address of a MAC on the local segment, or None."""
    mac = mac.lower()

    def lookup():
        for line in run(["ip", "neigh", "show"]).stdout.splitlines():
            if mac in line.lower():
                return line.split()[0]
        return None

    address = lookup()
    if address:
        return address

    # Not in the neighbour table yet: make the segment answer. A broadcast ping reaches every
    # host in one request; a parallel sweep covers the ones that ignore broadcasts.
    for broadcast in local_broadcasts():
        run(["ping", "-c", "2", "-W", "1", "-b", broadcast])
    address = lookup()
    if address:
        return address

    targets = [str(h) for b in local_broadcasts() for h in ipaddress.ip_network(
        b + "/24", strict=False
    ).hosts()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=64) as pool:
        list(pool.map(lambda t: run(["ping", "-c", "1", "-W", "1", t]), targets))
    return lookup()


def render_secrets(config_path, secret_dir, extra):
    """Build the secrets.yaml ESPHome resolves `!secret` against, for the names actually used."""
    config = open(config_path).read()
    names = set(re.findall(r"!secret\s+([A-Za-z0-9_]+)", config))
    values = {}
    for name in names:
        if name in extra:
            values[name] = read_secret(extra[name], name)
        elif name in SECRET_FILES:
            values[name] = read_secret(
                os.path.join(secret_dir, SECRET_FILES[name]), f"{name} ({secret_dir})"
            )
        else:
            sys.exit(f"Error: configuration references !secret {name}, which nothing provides.")
    return "".join(f"{name}: {values[name]}\n" for name in sorted(values))


def main():
    parser = argparse.ArgumentParser(description="VYRX ESPHome Declarative GitOps Sync Engine")
    parser.add_argument("--config", required=True, help="Rendered ESPHome YAML (read-only)")
    parser.add_argument("--name", required=True, help="Device name")
    parser.add_argument(
        "--device",
        required=True,
        help="Address to flash: the reservation from my.topology.devices, or the device's current "
        "old-subnet address for the first flash during the migration",
    )
    parser.add_argument("--secret-dir", help="Directory holding this device's SOPS secrets")
    parser.add_argument(
        "--wifi-psk-file", help="File holding the current WLAN pre-shared key"
    )
    parser.add_argument(
        "--legacy-wifi-psk-file", help="File holding the transitional WLAN pre-shared key"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Validate and resolve, but do not flash"
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
    print(f"==> ESPHome target '{args.name}'{mode_tag}")

    if not os.path.exists(args.config):
        sys.exit(f"Error: configuration '{args.config}' does not exist.")

    workdir = tempfile.mkdtemp(prefix=f"esphome-{args.name}-")
    try:
        # 2. Assemble config plus its secrets. ESPHome resolves !secret relative to the config.
        config_path = os.path.join(workdir, f"{args.name}.yaml")
        shutil.copyfile(args.config, config_path)
        secrets = render_secrets(
            config_path,
            args.secret_dir,
            {
                "wifi_psk": args.wifi_psk_file,
                "wifi_psk_legacy": args.legacy_wifi_psk_file,
            },
        )
        secrets_path = os.path.join(workdir, "secrets.yaml")
        with open(os.open(secrets_path, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600), "w") as f:
            f.write(secrets)
        print(f"  [✓] Secrets rendered for {len(secrets.splitlines())} reference(s).")

        # 3. Validate the configuration, secrets included.
        print("  [*] Validating ESPHome configuration schema...")
        res = run(["esphome", "config", config_path], cwd=workdir)
        if res.returncode != 0:
            print(f"  [!] Validation failed:\n{res.stderr or res.stdout}")
            sys.exit(1)
        print("  [✓] Configuration is valid.")

        address = args.device
        print(f"  [✓] Target address: {address}")

        if args.dry_run:
            print(f"  [✓] Dry-run complete. Nothing flashed to {address}.")
            return

        # 4. Compile and flash over the air.
        print(f"  [*] Compiling and uploading firmware OTA to {address}...")
        if run(["esphome", "run", "--no-logs", "--device", address, config_path], cwd=workdir).returncode != 0:
            sys.exit(f"Error: OTA deployment to {address} failed.")
        print(f"  [✓] Firmware deployed to {args.name} ({address}).")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
