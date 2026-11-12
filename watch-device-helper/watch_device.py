"""Experimental companion-proxy deployment, separate from xtool dev run."""

import argparse
import asyncio
import json
from pathlib import Path
import plistlib
from zipfile import ZipFile

from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.streaming_zip_conduit import StreamingZipConduitService
from watch_connection import WatchConnection


def package_info(package: Path):
    if package.is_dir() and package.suffix == ".app":
        info = plistlib.loads((package / "Info.plist").read_bytes())
    else:
        with ZipFile(package) as archive:
            candidates = [name for name in archive.namelist()
                          if name.startswith("Payload/") and name.count("/") == 2
                          and name.endswith("/Info.plist")]
            if len(candidates) != 1:
                raise ValueError("Expected a single Watch app payload.")
            info = plistlib.loads(archive.read(candidates[0]))
    if info.get("WKApplication") is not True or info.get("CFBundleSupportedPlatforms") != ["WatchOS"]:
        raise ValueError("Expected a watchOS device app.")
    return info


def write_metadata(path, metadata):
    """Create a private metadata artifact without replacing an existing file."""
    with path.open("x", encoding="utf-8") as destination:
        json.dump(metadata, destination)
        destination.write("\n")


async def lookup_bundle(watch, bundle_id):
    """Use only the read-only Lookup command and return selected app metadata."""
    async with InstallationProxyService(watch) as installer:
        result = await installer.service.send_recv_plist({
            "Command": "Lookup", "ClientOptions": {"BundleIDs": [bundle_id]}
        })
    if not isinstance(result, dict) or result.get("Error"):
        raise RuntimeError("Watch app lookup returned an error.")
    apps = result.get("LookupResult")
    if not isinstance(apps, dict):
        raise RuntimeError("Watch app lookup returned no valid registry result.")
    app = apps.get(bundle_id)
    if app is not None and not isinstance(app, dict):
        raise RuntimeError("Watch app lookup returned invalid app metadata.")
    if app is not None and app.get("CFBundleIdentifier", bundle_id) != bundle_id:
        raise RuntimeError("Watch app lookup returned a different bundle identifier.")
    return {"udid": watch.all_values["UniqueDeviceID"], "bundle_id": bundle_id,
            "version": app.get("CFBundleShortVersionString") if app is not None else None,
            "build": app.get("CFBundleVersion") if app is not None else None,
            "path": app.get("Path") if app is not None else None,
            "found": app is not None, "installed_verified": False}


def verify_installed(metadata, info):
    if not metadata["found"]:
        raise RuntimeError("Installer completed, but Watch app lookup failed.")
    for field, plist_key in (("version", "CFBundleShortVersionString"),
                             ("build", "CFBundleVersion")):
        expected = info.get(plist_key)
        actual = metadata[field]
        if not isinstance(expected, str) or not expected:
            raise ValueError(f"Package Info.plist is missing a valid {plist_key}.")
        if not isinstance(actual, str) or not actual:
            raise RuntimeError(f"Watch app lookup is missing a valid {plist_key}; installation is unverified.")
        if actual != expected:
            raise RuntimeError(f"Watch app lookup {plist_key} does not match the package.")
    metadata["installed_verified"] = True
    return metadata


async def main(args):
    info = package_info(args.install) if args.install else None
    async with WatchConnection(args.state_directory, pair_watch=args.pair) as watch:
        enabled = await watch.get_developer_mode_status()
        print(json.dumps({"watch_connected": True, "developer_mode": enabled}), flush=True)
        if args.device_info:
            # Exclusive creation avoids silently replacing an unrelated target file.
            with args.device_info.open("x", encoding="utf-8") as destination:
                json.dump({"udid": watch.all_values["UniqueDeviceID"],
                           "name": watch.all_values.get("DeviceName", "Apple Watch")}, destination)
            print("Saved private Watch device info.", flush=True)
        if args.reveal_developer_mode:
            service = await watch.start_lockdown_service("com.apple.amfi.lockdown")
            try:
                response = await service.send_recv_plist({"action": 0})
                if not response.get("success"):
                    raise RuntimeError("Watch did not expose the Developer Mode setting.")
            finally:
                await service.close()
            print("Enable Developer Mode in Watch Settings, restart, and confirm on the Watch.", flush=True)
        if getattr(args, "inspect_bundle", None):
            metadata = await lookup_bundle(watch, args.inspect_bundle)
            write_metadata(args.inspect_output, metadata)
            print("Saved Watch app registry metadata.", flush=True)
        if info is None:
            return
        if not enabled:
            raise RuntimeError("Enable and confirm Developer Mode on the Watch before installing.")
        async with StreamingZipConduitService(watch) as conduit:
            await conduit.install(args.install, developer=True,
                                  handler=lambda value: print(f"Install: {value}%", flush=True))
        metadata = verify_installed(await lookup_bundle(watch, info["CFBundleIdentifier"]), info)
        if getattr(args, "receipt", None):
            write_metadata(args.receipt, metadata)
        print("Installed and verified in the Watch app registry. Open the app on the Watch.", flush=True)


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-directory", type=Path, default=Path(".watchos"),
                        help="Private directory for the watch-pairing cache (default: .watchos)")
    parser.add_argument("--pair", action="store_true", help="Request Watch trust if not already paired")
    parser.add_argument("--device-info", type=Path, help="Create private JSON for xtool dev sign-watch")
    parser.add_argument("--reveal-developer-mode", action="store_true",
                        help="Show the Developer Mode switch; does not enable or confirm it")
    parser.add_argument("--install", type=Path, help="Install a signed Watch .app or .ipa")
    parser.add_argument("--receipt", type=Path,
                        help="Exclusively create verified installation JSON (requires --install)")
    parser.add_argument("--inspect-bundle", metavar="BUNDLE",
                        help="Read app identity using the Watch app registry Lookup command")
    parser.add_argument("--inspect-output", type=Path,
                        help="Exclusively create Lookup JSON (requires --inspect-bundle)")
    args = parser.parse_args()
    if args.receipt and not args.install:
        parser.error("--receipt requires --install")
    if bool(args.inspect_bundle) != bool(args.inspect_output):
        parser.error("--inspect-bundle and --inspect-output must be supplied together")
    if args.inspect_bundle and args.install:
        parser.error("--inspect-bundle and --install are mutually exclusive")
    args.state_directory.mkdir(parents=True, exist_ok=True)
    try:
        asyncio.run(asyncio.wait_for(main(args), 120))
    except Exception as error:
        # Avoid printing pairing records or device identifiers in tracebacks.
        if isinstance(error, (ValueError, RuntimeError)):
            print(str(error), flush=True)
        elif type(error).__name__ in {"AppInstallError", "StreamingZipConduitError"}:
            print(str(error), flush=True)
        print(f"Deployment stopped: {type(error).__name__}", flush=True)
        raise SystemExit(1) from None


if __name__ == "__main__":
    run()
