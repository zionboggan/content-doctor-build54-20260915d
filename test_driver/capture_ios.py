"""Bounded simulator launch; connect directly to its real VM service console URL.

Avoids an unbounded wait in Flutter's simulator system-log discovery. Only
navigation screenshots from the signed-in integration test are uploaded.
"""
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    device = os.environ['CAPTURE_DEVICE']
    bundle = 'com.zionsworking.matchabloom'
    app = Path('build/ios/iphonesimulator/Runner.app')
    if not app.is_dir():
        raise RuntimeError('Built simulator application missing')
    print('Installing built application', flush=True)
    subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True, timeout=90)
    console = Path(os.environ['RUNNER_TEMP']) / 'capture-console.log'
    console.touch(mode=0o600)
    print('Launching application and waiting for its VM service', flush=True)
    with console.open('w') as output:
        process = subprocess.Popen([
            'xcrun', 'simctl', 'launch', '--terminate-running-process', '--console-pty',
            device, bundle, '--enable-dart-profiling', '--enable-checked-mode',
            '--verify-entry-points', '--disable-vm-service-publication',
            '--start-paused', '--vm-service-port=8711',
        ], stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 90
            uri = None
            next_system_log = time.monotonic() + 10
            while time.monotonic() < deadline:
                contents = console.read_text(errors='replace')
                if time.monotonic() >= next_system_log:
                    # Some simulator versions send engine output only to unified logs.
                    try:
                        logs = subprocess.run([
                            'xcrun', 'simctl', 'spawn', device, 'log', 'show',
                            '--last', '2m', '--style', 'compact',
                            '--predicate', 'process == "Runner"',
                        ], capture_output=True, text=True, timeout=15)
                        contents += logs.stdout
                    except subprocess.TimeoutExpired:
                        # Diagnostics must not abort the actual launch attempt.
                        print('Simulator log query slow; continuing console discovery', flush=True)
                    next_system_log = time.monotonic() + 10
                match = re.search(r'http://(?:127\.0\.0\.1|localhost):8711/[^\s]+', contents)
                if match:
                    uri = match.group(0)
                    break
                if process.poll() is not None:
                    raise RuntimeError('Simulator application exited before exposing its VM service')
                time.sleep(1)
            if uri is None:
                # No reviewer login occurred yet; emit only a bounded native error tail.
                print(contents[-5000:], flush=True)
                diagnostic = Path('startup-diagnostics')
                diagnostic.mkdir(exist_ok=True)
                subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot',
                                str(diagnostic / 'before-driver.png')],
                               check=True, timeout=20)
                raise RuntimeError('VM service startup exceeded90seconds')
            print('::add-mask::' + uri, flush=True)
            print('VM service available; running real login and screenshot capture', flush=True)
            result = subprocess.run([
                'flutter', 'drive', '--use-existing-app=' + uri,
                '--driver=test_driver/app_store_capture.dart',
                '--target=integration_test/app_store_capture_test.dart',
                '--no-dds', '--timeout=180', '-d', device,
            ], timeout=220)
            if result.returncode:
                raise RuntimeError('Screenshot driver failed; see its masked test output')
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            try:
                subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle],
                               capture_output=True, timeout=15)
            except subprocess.TimeoutExpired:
                print('Simulator termination timed out after capture', flush=True)
            console.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        # Do not dump command arguments containing the ephemeral VM service URL.
        raise SystemExit('Capture command stopped: ' + type(error).__name__) from None
