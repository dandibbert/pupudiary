#!/usr/bin/env python3
"""Offline macOS inspection of a signed Pupudiary IPA. Does not sign, upload or install it."""
import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile


def command(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f'{Path(args[0]).name} failed for {args[-1]}: {result.stderr.decode(errors="replace").strip()}')
    return result.stdout


def permits(allowed, claimed):
    """Provisioning entitlements are an allowlist, not an exact copy of signed claims."""
    if isinstance(claimed, str):
        return isinstance(allowed, str) and fnmatch.fnmatchcase(claimed, allowed)
    if isinstance(claimed, list):
        return isinstance(allowed, list) and all(any(permits(a, c) for a in allowed) for c in claimed)
    if isinstance(claimed, dict):
        return isinstance(allowed, dict) and all(k in allowed and permits(allowed[k], v) for k, v in claimed.items())
    return type(allowed) is type(claimed) and allowed == claimed


def inspect_bundle(bundle, work, expected_group, udid):
    profile_path = bundle / 'embedded.mobileprovision'
    if not profile_path.is_file():
        raise ValueError(f'{bundle.name}: embedded.mobileprovision missing')
    command('codesign', '--verify', '--strict', '--verbose=2', str(bundle))
    raw_entitlements = command('codesign', '--display', '--entitlements', ':-', str(bundle))
    entitlements = plistlib.loads(raw_entitlements)
    profile = plistlib.loads(command('security', 'cms', '-D', '-i', str(profile_path)))
    permitted = profile['Entitlements']
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    bundle_id = info['CFBundleIdentifier']
    signed_app_id = entitlements.get('application-identifier', '')
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    if not any(signed_app_id == f'{prefix}.{bundle_id}' for prefix in prefixes):
        raise ValueError(f'{bundle.name}: application-identifier does not match profile prefix and bundle ID')
    team = entitlements.get('com.apple.developer.team-identifier')
    if not team or team not in profile.get('TeamIdentifier', []):
        raise ValueError(f'{bundle.name}: signing team does not match profile')
    for key, claimed in entitlements.items():
        if key not in permitted or not permits(permitted[key], claimed):
            raise ValueError(f'{bundle.name}: signed entitlement {key!r} is not allowed by its profile')
    expiry = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
    if expiry <= datetime.now(timezone.utc):
        raise ValueError(f'{bundle.name}: provisioning profile has expired')
    if udid and not profile.get('ProvisionsAllDevices', False) and udid not in profile.get('ProvisionedDevices', []):
        raise ValueError(f'{bundle.name}: the requested device UDID is not provisioned')
    # Compare the actual signing leaf certificate with the profile's authorized certificates.
    prefix = work / (bundle.name + '-signer-')
    command('codesign', '--display', '--extract-certificates', str(prefix), str(bundle))
    certificate = Path(str(prefix) + '0')
    leaf = certificate.read_bytes()
    authorized = profile.get('DeveloperCertificates', [])
    if leaf not in authorized:
        raise ValueError(f'{bundle.name}: signing certificate is not authorized by its provisioning profile')
    command('openssl', 'x509', '-inform', 'DER', '-in', str(certificate), '-checkend', '0', '-noout')
    has_group = expected_group in entitlements.get('com.apple.security.application-groups', [])
    return {
        'bundle': bundle.name, 'bundle_id': bundle_id, 'team': team,
        'profile_expires': expiry.isoformat(), 'app_group_present': has_group,
        'certificate_sha256': hashlib.sha256(leaf).hexdigest(),
        'device_scope': 'all devices' if profile.get('ProvisionsAllDevices') else (
            'registered devices' if profile.get('ProvisionedDevices') else 'App Store distribution'),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--app-id', default='com.dandibbert.pupudiary')
    parser.add_argument('--widget-id', default='com.dandibbert.pupudiary.widget')
    parser.add_argument('--group', default='group.com.dandibbert.pupudiary')
    parser.add_argument('--udid', help='Optionally check that both profiles permit this device. Kept local; not printed.')
    parser.add_argument('--allow-no-app-group', action='store_true', help='Explicitly permit app-only fallback; does not validate widget sharing.')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('Run this offline validator on a Mac with Xcode command-line tools.')
    for tool in ('codesign', 'security', 'openssl'):
        if not shutil.which(tool):
            parser.error(f'Required macOS tool missing: {tool}')
    module_path = Path(__file__).with_name('validate-ipa.py')
    spec = importlib.util.spec_from_file_location('ipa_validation', module_path)
    validation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validation)
    validation.validate(args.ipa, False, args.app_id, args.widget_id)
    with tempfile.TemporaryDirectory(prefix='pupudiary-signed-check-') as temp:
        temp = Path(temp)
        # Structural validation above rejects traversal paths and symbolic links first.
        with zipfile.ZipFile(args.ipa) as archive:
            archive.extractall(temp)
            # zipfile does not restore executable mode; codesign verification expects it.
            for item in archive.infolist():
                mode = (item.external_attr >> 16) & 0o777
                if mode:
                    (temp / item.filename).chmod(mode)
        app = temp / 'Payload/Pupudiary.app'
        widget = app / 'PlugIns/PupudiaryWidgetExtension.appex'
        reports = [inspect_bundle(bundle, temp, args.group, args.udid) for bundle in (app, widget)]
        command('codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app))
        if reports[0]['team'] != reports[1]['team']:
            raise ValueError('App and widget are signed by different teams')
        if reports[0]['certificate_sha256'] != reports[1]['certificate_sha256']:
            raise ValueError('App and widget are signed with different certificates')
        if reports[0]['app_group_present'] != reports[1]['app_group_present']:
            raise ValueError('Only one target has the required App Group entitlement; repair both profiles/signatures')
        if not all(r['app_group_present'] for r in reports):
            if not args.allow_no_app_group:
                raise ValueError('App Group is absent. Widget data sharing/one-tap logging cannot work. For app-only fallback, explicitly use --allow-no-app-group.')
            print('WARNING: app-only fallback. Widget shared records and interactive logging are NOT validated.')
        print(json.dumps({'checks_passed': reports, 'expected_app_group': args.group,
            'limits': 'Offline inspection cannot check revocation, online trust, installation eligibility or on-device widget execution.'}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, plistlib.InvalidFileException) as error:
        sys.exit(f'Signed IPA validation failed: {error}')
