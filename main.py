"""PC preview launcher for Escáner Local.

The app itself is the Flutter project in this folder (Android, iOS and
Windows). This opens its Windows build, building it first when the code is
newer than the program, and passes every argument through (for example
``--screenshot shot.png``).
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
EXE = ROOT / "build" / "windows" / "x64" / "runner" / "Release" / "escaner_local.exe"
SOURCES = ["lib", "pubspec.yaml", "pubspec.lock", "windows/runner", "windows/CMakeLists.txt"]


def newest_source_time() -> float:
    newest = 0.0
    for name in SOURCES:
        path = ROOT / name
        if path.is_file():
            newest = max(newest, path.stat().st_mtime)
        elif path.is_dir():
            for file in path.rglob("*"):
                if file.is_file():
                    newest = max(newest, file.stat().st_mtime)
    return newest


def build_if_needed() -> None:
    if EXE.exists() and EXE.stat().st_mtime >= newest_source_time():
        return
    subprocess.run("flutter build windows --release", shell=True, cwd=ROOT, check=True)


def main() -> int:
    if sys.platform != "win32":
        print("This launcher opens the Windows build; on a phone use `flutter run`.")
        return 2
    build_if_needed()
    args = sys.argv[1:]
    if "--screenshot" in args:
        i = args.index("--screenshot")
        if i + 1 < len(args):
            args[i + 1] = str(pathlib.Path(args[i + 1]).resolve())
    return subprocess.call([str(EXE), *args])


if __name__ == "__main__":
    sys.exit(main())
