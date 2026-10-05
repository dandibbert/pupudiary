#!/usr/bin/env python3
"""Validate IPA structure, native arm64 device executables, widget metadata and compiled icons."""
import argparse
import json
from pathlib import Path, PurePosixPath
import plistlib
import stat
import struct
import sys
import zipfile


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def validate_macho(data, label):
    # The release build is deliberately thin arm64. iOS Simulator can also be arm64,
    # so architecture alone is insufficient: inspect LC_BUILD_VERSION's platform.
    require(len(data) >= 32 and data[:4] == b'\xcf\xfa\xed\xfe', f'{label}: expected a thin 64-bit Mach-O')
    _, cpu, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from('<8I', data)
    require(cpu == 0x0100000C, f'{label}: expected arm64, found CPU type {cpu:#x}')
    require(filetype == 2, f'{label}: expected an executable')
    require(32 + sizeofcmds <= len(data), f'{label}: truncated Mach-O load commands')
    cursor, platform = 32, None
    for _ in range(ncmds):
        require(cursor + 8 <= 32 + sizeofcmds, f'{label}: invalid Mach-O command')
        cmd, length = struct.unpack_from('<II', data, cursor)
        require(length >= 8 and cursor + length <= 32 + sizeofcmds, f'{label}: invalid Mach-O command size')
        if cmd == 0x32:  # LC_BUILD_VERSION
            require(length >= 24, f'{label}: invalid LC_BUILD_VERSION')
            platform = struct.unpack_from('<I', data, cursor + 8)[0]
        elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS
            platform = 2
        cursor += length
    require(platform == 2, f'{label}: expected iOS device platform 2, found {platform} (7 is Simulator)')


def validate(ipa, unsigned=False, app_id='com.dandibbert.pupudiary', widget_id='com.dandibbert.pupudiary.widget'):
    with zipfile.ZipFile(ipa) as archive:
        require(archive.testzip() is None, 'IPA ZIP CRC validation failed')
        names = set(archive.namelist())
        for info in archive.infolist():
            path = PurePosixPath(info.filename)
            require(not path.is_absolute() and '..' not in path.parts, 'Unsafe path inside IPA')
            require(not stat.S_ISLNK(info.external_attr >> 16), 'Unexpected symbolic link inside IPA')
            require(path.parts and path.parts[0] == 'Payload', 'Unexpected top-level IPA content')
        apps = {PurePosixPath(name).parts[1] for name in names if len(PurePosixPath(name).parts) >= 2}
        require(apps == {'Pupudiary.app'}, f'Expected only Payload/Pupudiary.app, found {apps}')
        root = 'Payload/Pupudiary.app'
        extension = root + '/PlugIns/PupudiaryWidgetExtension.appex'
        require(extension + '/Info.plist' in names, 'Widget .appex missing; do not strip app extensions')
        infos = []
        for path, expected_id in ((root, app_id), (extension, widget_id)):
            info = plistlib.loads(archive.read(path + '/Info.plist'))
            require(info.get('CFBundleIdentifier') == expected_id, f'{path}: unexpected bundle ID')
            require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], f'{path}: not built for iPhoneOS')
            executable = path + '/' + info['CFBundleExecutable']
            require(executable in names, f'{path}: executable missing')
            validate_macho(archive.read(executable), path)
            if unsigned:
                require(path + '/embedded.mobileprovision' not in names, f'{path}: unexpected provisioning profile in unsigned artifact')
                require(not any(n.startswith(path + '/_CodeSignature/') for n in names), f'{path}: unsigned artifact contains a code signature')
            infos.append(info)
        app_info, widget_info = infos
        require(widget_info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension', 'Incorrect WidgetKit extension point')
        for key in ('CFBundleVersion', 'CFBundleShortVersionString', 'MinimumOSVersion'):
            require(app_info.get(key) == widget_info.get(key), f'App/widget {key} mismatch')
        require(str(app_info.get('MinimumOSVersion', '')).startswith('17.'), 'Expected iOS 17 deployment target')
        require(root + '/Assets.car' in names, 'Compiled app asset catalog missing')
        icon_info = app_info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
        icon_names = icon_info.get('CFBundleIconFiles', [])
        require(bool(icon_names), 'Info.plist does not declare a primary app icon')
        compiled_icons = []
        for declared in icon_names:
            basename = Path(declared).stem
            matches = [n for n in names if n.startswith(root + '/' + basename) and n.endswith('.png') and '/PlugIns/' not in n]
            require(matches, f'Compiled app icon missing for {declared}')
            compiled_icons.extend(matches)
        sizes = []
        for icon in set(compiled_icons):
            content = archive.read(icon)
            require(content[:8] == b'\x89PNG\r\n\x1a\n', f'Invalid icon PNG: {icon}')
            # Xcode may write a CgBI chunk before IHDR. Parse chunks, not fixed offsets.
            cursor = 8
            while cursor + 8 <= len(content):
                length = struct.unpack_from('>I', content, cursor)[0]
                kind = content[cursor + 4:cursor + 8]
                if kind == b'IHDR':
                    sizes.append(struct.unpack_from('>II', content, cursor + 8))
                    break
                cursor += 12 + length
        require((120, 120) in sizes or (180, 180) in sizes, f'No iPhone home-screen icon size found: {sizes}')
        summary = {'ipa': str(ipa), 'bytes': ipa.stat().st_size, 'app': app_id, 'widget': widget_id,
                   'architecture': 'arm64', 'platform': 'iPhoneOS', 'minimum_iOS': app_info['MinimumOSVersion'],
                   'version': app_info['CFBundleShortVersionString'], 'build': app_info['CFBundleVersion'],
                   'icon_sizes': sorted(set(sizes)), 'unsigned': unsigned}
        return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--unsigned', action='store_true')
    parser.add_argument('--app-id', default='com.dandibbert.pupudiary')
    parser.add_argument('--widget-id', default='com.dandibbert.pupudiary.widget')
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.ipa, args.unsigned, args.app_id, args.widget_id), indent=2))
    except (ValidationError, OSError, KeyError, ValueError, zipfile.BadZipFile) as error:
        sys.exit(f'IPA validation failed: {error}')


if __name__ == '__main__':
    main()
