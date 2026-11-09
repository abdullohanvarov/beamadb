#!/usr/bin/env python3
"""Map dynamically resolved system libraries to conservative host package versions."""
import os
import pathlib
import re
import subprocess
import sys
bundle = pathlib.Path(sys.argv[1]).resolve()
env = dict(os.environ, LD_LIBRARY_PATH=str(bundle / 'lib'))
paths = set()
for binary in [bundle / 'beamadb_desktop', *list((bundle / 'lib').glob('*.so*')), bundle / 'bin/scrcpy/linux/adb', bundle / 'bin/scrcpy/linux/scrcpy']:
    result = subprocess.run(['ldd', str(binary)], capture_output=True, text=True, env=env)
    if 'not found' in result.stdout:
        raise SystemExit(f'Missing runtime dependency for {binary}:\n{result.stdout}')
    for match in re.finditer(r'(?:=>\s+)?(/[^\s]+)', result.stdout):
        path = pathlib.Path(match.group(1)).resolve()
        if not path.is_relative_to(bundle):
            paths.add(str(path))
packages = {}
for path in sorted(paths):
    found = subprocess.run(['dpkg-query', '-S', path], capture_output=True, text=True)
    if found.returncode and path.startswith('/usr/lib/'):
        found = subprocess.run(['dpkg-query', '-S', path.removeprefix('/usr')], capture_output=True, text=True)
    if found.returncode:
        raise SystemExit(f'Cannot identify runtime package for {path}')
    package = found.stdout.split(': ')[0].split(':')[0]
    version = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', package], text=True).strip()
    packages[package] = version
print(', '.join(f'{name} (>= {version})' for name, version in sorted(packages.items())))
