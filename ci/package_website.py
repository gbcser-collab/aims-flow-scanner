"""Create a webroot ZIP from the verified upload manifest, without wrapper folders.

Only manifest-listed files are shipped. This excludes transfer leftovers and
keeps documentation and server configuration outside the public upload archive.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import zipfile


def package(assembled_dir, output):
    root = (assembled_dir / 'FELTOLTENDO').resolve()
    records = json.loads((assembled_dir / 'FAJLLISTA.json').read_text())
    entries = {}
    for record in records:
        name = record['path']
        rel = PurePosixPath(name)
        if rel.is_absolute() or '..' in rel.parts or '\\' in name or str(rel) != name:
            raise ValueError('Invalid upload path: ' + name)
        if name in entries:
            raise ValueError('Duplicate upload path: ' + name)
        source = root.joinpath(*rel.parts)
        if source.is_symlink() or not source.resolve().is_relative_to(root):
            raise ValueError('Upload path escapes webroot: ' + name)
        data = source.read_bytes()
        if len(data) != record['bytes'] or hashlib.sha256(data).hexdigest() != record['sha256']:
            raise ValueError('Upload file differs from manifest: ' + name)
        entries[name] = source
    for required in ('index.html', 'flow/app/index.html', 'assets/mobile-v41.css'):
        if required not in entries:
            raise ValueError('Missing webroot entry: ' + required)
    if '.htaccess' in entries:
        raise ValueError('Do not replace existing root server configuration in an update.')
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation preserves previous deliverables if the path is reused.
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, source in sorted(entries.items()):
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, source.read_bytes())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(entries):
            raise ValueError('Archive integrity verification failed.')
    return {'output': str(output), 'files': len(entries), 'bytes': output.stat().st_size,
            'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembled-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    print(json.dumps(package(**vars(parser.parse_args())), indent=2))
