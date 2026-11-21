#!/usr/bin/env python3
from __future__ import annotations
import ipaddress
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONFIG = ROOT / "config.json"
EXAMPLE = ROOT / "config.example.json"

def ask_ip():
    while True:
        raw = input("TV IP address: ").strip()
        try:
            ip = ipaddress.ip_address(raw)
            if ip.version != 4: raise ValueError
        except ValueError:
            print("That is not a valid IPv4 address. Please try again.\n")
            continue
        if not ip.is_private:
            answer = input("Warning: this is not a private LAN address. Use it anyway? [y/N]: ").strip().lower()
            if answer not in ("y", "yes"): continue
        return str(ip)

def ask_name():
    while True:
        name = input("Name this TV (example: Living Room TV): ").strip()
        if name: return name[:60]
        print("Please enter a name for the TV.\n")

def main():
    if CONFIG.exists(): return
    try:
        config = json.loads(EXAMPLE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Could not read config.example.json: {exc}")
    print("\nWolffe TV v3 first-run setup")
    print("-----------------------------")
    print("Find the Roku TV IP under Settings > Network > About.\n")
    config["tv_ip"] = ask_ip()
    config["tv_name"] = ask_name()
    config.setdefault("port", 8787)
    CONFIG.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(f"\nCreated config.json for {config['tv_name']} at {config['tv_ip']}.")
    print("Starting Wolffe TV v3...\n")

if __name__ == "__main__": main()
