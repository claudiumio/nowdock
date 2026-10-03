#!/usr/bin/env python3
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(['swift', 'build'], cwd=root, check=True)
bin_path = pathlib.Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
objects = sorted((bin_path / 'NowDockCore.build').glob('*.swift.o'))
objects += [p for p in sorted((bin_path / 'NowDock.build').glob('*.swift.o')) if p.name != 'main.swift.o']
with tempfile.TemporaryDirectory(prefix='nowdock-native-') as directory:
    executable = pathlib.Path(directory) / 'check-native'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-I', str(bin_path / 'Modules'), *map(str, objects), str(root / 'Scripts/NativeCheck/main.swift'), '-o', str(executable)], cwd=root, check=True)
    subprocess.run([str(executable), 'baseline'], cwd=root, check=True)
    subprocess.run([str(executable), 'safety'], cwd=root, check=True)
    if '--login' in sys.argv:
        contents = pathlib.Path(directory) / 'NowDockLoginCheck.app' / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        bundled = contents / 'MacOS' / 'check-native'
        shutil.copy2(executable, bundled)
        with (contents / 'Info.plist').open('wb') as manifest:
            plistlib.dump({'CFBundleIdentifier': 'dev.nowdock.LoginCheck', 'CFBundleExecutable': 'check-native', 'CFBundleName': 'NowDockLoginCheck', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSUIElement': True}, manifest)
        subprocess.run(['codesign', '--force', '--sign', '-', str(contents.parent)], check=True)
        subprocess.run([str(bundled), 'login'], cwd=root, check=True)
    fixture = subprocess.Popen([str(executable), 'fixture'], cwd=root, stdout=subprocess.PIPE, text=True)
    try:
        assert fixture.stdout is not None
        assert fixture.stdout.readline().startswith('READY '), 'Fixture did not initialize'
        present = False
        for attempt in range(10):
            result = subprocess.check_output([str(executable), 'inventory', str(fixture.pid)], cwd=root, text=True)
            if result.strip() == 'PRESENT':
                present = True
                break
            time.sleep(0.2)
        assert present, 'Fixture was not registered with WindowServer'
        subprocess.run([str(executable), 'fullscreen'], cwd=root, check=True)
    finally:
        fixture.terminate()
        fixture.wait(timeout=5)
