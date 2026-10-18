#!/usr/bin/env python3
"""Package an unsigned Xcode device build for later local Apple ID re-signing.

No Apple identity, provisioning profile, password, or paid developer account is
used here. Ad-hoc signatures retain App Group entitlements for the sideloader to
read and remap. They do not make this IPA directly installable on an iPhone.
Only macOS supplies the Apple tools needed by this script.
"""

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*arguments):
    result = subprocess.run(arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout, result.stderr


def read_plist(path):
    with path.open("rb") as handle:
        value = plistlib.load(handle)
    require(isinstance(value, dict), f"Expected a plist dictionary: {path.name}")
    return value


def write_plist(path, value):
    with path.open("wb") as handle:
        plistlib.dump(value, handle, fmt=plistlib.FMT_XML, sort_keys=True)


def valid_identifier(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value) is not None


def bundle_info(bundle):
    info = read_plist(bundle / "Info.plist")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", executable),
            f"Invalid bundle executable in {bundle.name}")
    require(valid_identifier(info.get("CFBundleIdentifier")), f"Invalid bundle identifier in {bundle.name}")
    require((bundle / executable).is_file(), f"Missing executable in {bundle.name}")
    return info


def resolve_entitlements(template, variables):
    def resolve(value):
        if isinstance(value, str):
            def replace(match):
                key = match.group(1)
                require(key in variables, f"Unresolved entitlement build setting: {key}")
                return variables[key]
            return re.sub(r"\$\(([^)]+)\)", replace, value)
        if isinstance(value, list):
            return [resolve(item) for item in value]
        if isinstance(value, dict):
            return {key: resolve(item) for key, item in value.items()}
        return value
    return resolve(read_plist(template))


def validate_device_executable(bundle, info):
    executable = str(bundle / info["CFBundleExecutable"])
    architectures = run("xcrun", "lipo", "-archs", executable)[0].decode().split()
    require(architectures == ["arm64"], f"Expected a thin arm64 device executable in {bundle.name}, got {architectures}")
    commands = run("xcrun", "vtool", "-show-build", executable)[0].decode()
    require(re.search(r"^\s*platform\s+IOS\s*$", commands, re.MULTILINE),
            f"{bundle.name} is not an iOS device build (an arm64 Simulator build cannot be installed)")
    require(os.access(executable, os.X_OK), f"Executable permission is missing in {bundle.name}")


def sign(path, entitlements=None):
    arguments = ["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der"]
    if entitlements is not None:
        arguments.extend(["--entitlements", str(entitlements)])
    arguments.append(str(path))
    run(*arguments)


def validate_signature(bundle, expected_group):
    run("codesign", "--verify", "--strict", "--verbose=2", str(bundle))
    signature = run("codesign", "--display", "--verbose=4", str(bundle))
    require(b"Signature=adhoc" in signature[0] + signature[1], f"Expected an ad-hoc signature in {bundle.name}")
    entitlements, _ = run("codesign", "--display", "--entitlements", ":-", str(bundle))
    value = plistlib.loads(entitlements)
    require(value.get("com.apple.security.application-groups") == [expected_group],
            f"Signed App Group entitlement mismatch in {bundle.name}")


def write_archive(payload, output):
    # Preserve executable permissions and in-bundle symlinks. All archive paths
    # are relative and start with Payload/, as required by iOS sideloaders.
    output.parent.mkdir(parents=True, exist_ok=True)
    expanded_bytes = 0
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(payload.rglob("*")):
            metadata = path.lstat()
            relative = path.relative_to(payload.parent).as_posix()
            is_directory = stat.S_ISDIR(metadata.st_mode)
            entry = zipfile.ZipInfo(relative + ("/" if is_directory else ""))
            entry.create_system = 3
            entry.external_attr = metadata.st_mode << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            if path.is_symlink():
                require(path.resolve().is_relative_to(payload), f"Symlink leaves Payload: {relative}")
                data = os.readlink(path).encode("utf-8")
            else:
                data = b"" if is_directory else path.read_bytes()
            expanded_bytes += len(data)
            require(expanded_bytes <= 128 * 1024 * 1024, "The expanded payload exceeds the 128 MiB artifact limit")
            archive.writestr(entry, data)
    require(output.stat().st_size <= 64 * 1024 * 1024, "The compressed IPA exceeds the 64 MiB artifact limit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Release-iphoneos/Datenblick.app from xcodebuild")
    parser.add_argument("--output", required=True, type=Path, help="Destination .ipa file")
    parser.add_argument("--config-dir", type=Path, default=Path(__file__).resolve().parent.parent / "Config")
    args = parser.parse_args()
    require(sys.platform == "darwin", "Packaging requires macOS with Xcode; use the free public-repository workflow on Windows.")
    source = args.app.resolve(strict=True)
    require(source.is_dir() and source.name == "Datenblick.app", "Expected a Datenblick.app bundle")
    require(args.output.suffix.lower() == ".ipa", "The output must use the .ipa extension")

    with tempfile.TemporaryDirectory(prefix="datenblick-ipa-") as temporary:
        staging = Path(temporary)
        payload = staging / "Payload"
        app = payload / "Datenblick.app"
        shutil.copytree(source, app, symlinks=True)
        widget = app / "PlugIns" / "DatenblickWidget.appex"
        extensions = sorted((app / "PlugIns").glob("*.appex"))
        require(extensions == [widget], "Expected exactly one embedded DatenblickWidget.appex")
        app_info, widget_info = bundle_info(app), bundle_info(widget)
        app_id = app_info["CFBundleIdentifier"]
        require(widget_info["CFBundleIdentifier"] == app_id + ".widget", "Widget identifier must be the app identifier plus .widget")
        group = app_info.get("AppGroupIdentifier")
        require(valid_identifier(group) and group.startswith("group."), "The built AppGroupIdentifier is missing or unresolved")
        require(widget_info.get("AppGroupIdentifier") == group, "App and widget must use the same built AppGroupIdentifier")
        require(app_info.get("CFBundlePackageType") == "APPL", "Unexpected app package type")
        require(widget_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension",
                "The embedded extension is not a WidgetKit widget")
        variables = {"BASE_BUNDLE_IDENTIFIER": app_id, "APP_GROUP_IDENTIFIER": group}

        for bundle, info, template in [(widget, widget_info, "Widget.entitlements"), (app, app_info, "App.entitlements")]:
            validate_device_executable(bundle, info)
            # XML makes the artifact inspectable with the cross-platform verifier.
            # Modify plists before signing so the final signature covers them.
            write_plist(bundle / "Info.plist", info)
            (bundle / "embedded.mobileprovision").unlink(missing_ok=True)
            entitlements = resolve_entitlements(args.config_dir / template, variables)
            require(entitlements.get("com.apple.security.application-groups") == [group],
                    f"Resolved entitlements do not match the built group in {template}")
            entitlement_path = staging / template
            write_plist(entitlement_path, entitlements)
            # Sign nested frameworks/libraries first, without app entitlements.
            nested = [path for path in bundle.rglob("*") if path.suffix == ".framework" and path.is_dir()
                      or path.suffix == ".dylib" and path.is_file()]
            for path in sorted(nested, key=lambda item: len(item.parts), reverse=True):
                # The widget has already been signed when processing the app.
                if bundle == app and widget in path.parents:
                    continue
                sign(path)
            sign(bundle, entitlement_path)
            validate_signature(bundle, group)

        run("codesign", "--verify", "--strict", "--deep", "--verbose=2", str(app))
        write_archive(payload, args.output.resolve())

    print(f"Packaged {args.output}: arm64 iOS app + widget, matching App Group entitlements, ad-hoc signatures.")
    print("This IPA still requires local re-signing with your free Apple ID before installation.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f"IPA packaging failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode(errors="replace"), file=sys.stderr)
        sys.exit(1)
