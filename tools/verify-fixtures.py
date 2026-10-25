#!/usr/bin/env python3
"""Verify the single authoritative fixture set, or a byte-identical mirror."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
fixtures = root / 'conformance'
if not (fixtures / 'manifest.json').exists():
    fixtures = root / 'Tests/MagritteTests/Fixtures'
manifest = json.loads((fixtures / 'manifest.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((fixtures / name).read_bytes()).hexdigest() == digest, name
if (root / 'conformance-source.json').exists():
    lock = json.loads((root / 'conformance-source.json').read_text())
    assert lock['manifestSHA256'] == hashlib.sha256((fixtures / 'manifest.json').read_bytes()).hexdigest()
    assert len(lock['revision']) == 40
print(f"Verified {len(manifest['files'])} shared fixtures")
