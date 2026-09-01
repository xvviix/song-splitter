#!/usr/bin/env python3
"""
Generates the self-contained installers in engine/.

The Python engine is embedded as base64 inside a single .bat (Windows) and a
single .sh (macOS/Linux), so the user downloads ONE file. This avoids Chrome's
"multiple automatic downloads" block and removes the "put both files in the
same folder" failure mode entirely.

Run this after editing xvviix_engine.py:
    python3 build-installers.py
"""

import base64
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "engine" / "xvviix_engine.py"
OUT_BAT = ROOT / "engine" / "install-xvviix.bat"
OUT_SH = ROOT / "engine" / "install-xvviix.sh"

payload = base64.b64encode(SRC.read_bytes()).decode("ascii")

# ----------------------------------------------------------------- Windows
# ASCII only. Persian text in a .bat breaks under the default OEM codepage
# (cmd mangles UTF-8 and can split commands mid-byte), which is why the old
# version failed to run.
bat_b64 = "\n".join(
    f"echo {line}>>\"%B64%\"" for line in textwrap.wrap(payload, 120)
)

BAT = f"""@echo off
setlocal enabledelayedexpansion
title XVVIIX - Local Engine Setup
cd /d "%~dp0"

echo.
echo  ============================================================
echo                XVVIIX - Local Engine Setup
echo  ============================================================
echo.
echo   This will set up the Demucs AI engine on this computer.
echo.
echo     [1] Check that Python is installed
echo     [2] Create an isolated environment in this folder
echo     [3] Download the AI engine
echo     [4] Start the engine
echo.
echo   Download size depends on your hardware:
echo     - No NVIDIA graphics card : about 250 MB
echo     - With NVIDIA graphics card : about 2.5 GB (CUDA libraries)
echo.
echo   Everything stays inside this folder.
echo   To uninstall, simply delete this folder.
echo.
echo  ------------------------------------------------------------
pause
echo.

echo  [1/4] Checking Python...
where python >nul 2>&1
if errorlevel 1 goto nopython
python -c "import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
if errorlevel 1 goto badversion
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set PYVER=%%v
echo        OK - Python !PYVER!
echo.

echo  [2/4] Creating environment...
set "REUSE=0"
python -c "import torch,sys; v=tuple(int(x) for x in torch.__version__.split('.')[:2]); sys.exit(0 if v>=(2,0) else 1)" >nul 2>&1
if not errorlevel 1 (
    set "REUSE=1"
    for /f "delims=" %%v in ('python -c "import torch;print(torch.__version__)" 2^>nul') do set TVER=%%v
    for /f "delims=" %%c in ('python -c "import torch;print(\'yes\' if torch.cuda.is_available() else \'no\')" 2^>nul') do set TCUDA=%%c
    echo        Found PyTorch !TVER! on your system ^(CUDA: !TCUDA!^)
    echo        Reusing it - only a few MB will be downloaded.
)
if exist ".venv\\Scripts\\python.exe" (
    echo        OK - environment already exists
) else (
    if "!REUSE!"=="1" (
        python -m venv --system-site-packages .venv
    ) else (
        python -m venv .venv
    )
    if errorlevel 1 (
        echo        FAILED - could not create the environment
        pause
        exit /b 1
    )
    echo        OK - created
)
set "PY=.venv\\Scripts\\python.exe"
echo.

echo  [3/4] Installing the AI engine...
if exist ".venv\\.installed" (
    echo        OK - already installed
    goto writeengine
)

if "!REUSE!"=="1" (
    echo        Using the PyTorch already on your system - skipping the big download.
    goto installdemucs
)

echo        Detecting graphics card...
set "HASNV=0"
where nvidia-smi >nul 2>&1 && set "HASNV=1"
if "!HASNV!"=="1" (
    echo        NVIDIA GPU detected - installing CUDA build (about 2.5 GB^)
    echo        This is the slow part. Please wait.
    "%PY%" -m pip install --quiet --upgrade pip
    "%PY%" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121
    if errorlevel 1 (
        echo        CUDA build failed - falling back to the smaller CPU build
        "%PY%" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
    )
) else (
    echo        No NVIDIA GPU - installing the small CPU build (about 250 MB^)
    "%PY%" -m pip install --quiet --upgrade pip
    "%PY%" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 (
    echo        FAILED - check your internet connection and run this file again
    pause
    exit /b 1
)

:installdemucs
"%PY%" -m pip install demucs soundfile
if errorlevel 1 (
    echo        FAILED - could not install Demucs
    pause
    exit /b 1
)
echo done>".venv\\.installed"
echo        OK - installed
echo.

:writeengine
set "B64=%TEMP%\\xvviix_b64_%RANDOM%.txt"
if exist "%B64%" del "%B64%"
{bat_b64}
certutil -decode "%B64%" "xvviix_engine.py" >nul 2>&1
if errorlevel 1 (
    echo        FAILED - could not write the engine file
    del "%B64%" >nul 2>&1
    pause
    exit /b 1
)
del "%B64%" >nul 2>&1

echo.
echo  [4/4] Starting the engine...
echo.
echo  ============================================================
echo     READY
echo.
echo     Go back to the website - it connects automatically.
echo     Keep this window open while you work.
echo     Press Ctrl+C to stop.
echo  ============================================================
echo.
"%PY%" xvviix_engine.py
pause
exit /b 0

:nopython
echo.
echo        Python is not installed (or not on your PATH^).
echo.
echo        1. Go to https://www.python.org/downloads/
echo        2. Download and run the installer
echo        3. IMPORTANT: tick "Add Python to PATH"
echo        4. Run this file again
echo.
start https://www.python.org/downloads/
pause
exit /b 1

:badversion
echo.
echo        Your Python is too old. Version 3.9 or newer is required.
echo        Get it from https://www.python.org/downloads/
echo.
start https://www.python.org/downloads/
pause
exit /b 1
"""

# ------------------------------------------------------------ macOS / Linux
SH = f"""#!/usr/bin/env bash
# XVVIIX - Local Engine Setup (macOS / Linux)
set -u
cd "$(dirname "$0")"

G='\\033[0;32m'; R='\\033[0;31m'; Y='\\033[1;33m'; N='\\033[0m'

echo
echo "  ============================================================"
echo "                XVVIIX - Local Engine Setup"
echo "  ============================================================"
echo
echo "   This will set up the Demucs AI engine on this computer."
echo
echo "     [1] Check Python"
echo "     [2] Create an isolated environment in this folder"
echo "     [3] Download the AI engine"
echo "     [4] Start the engine"
echo
echo "   Download size:"
echo "     - CPU only        : about 250 MB"
echo "     - NVIDIA GPU      : about 2.5 GB (CUDA libraries)"
echo
echo "   Everything stays in this folder. Delete it to uninstall."
echo
read -rp "   Press Enter to continue... " _
echo

echo "  [1/4] Checking Python..."
PY=""
for c in python3.12 python3.11 python3.10 python3; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  echo -e "       ${{R}}Python not found.${{N}}"
  echo "       Install it from https://www.python.org/downloads/"
  command -v brew >/dev/null 2>&1 && echo "       or run:  brew install python"
  exit 1
fi
echo -e "       ${{G}}OK - $($PY --version)${{N}}"
echo

echo "  [2/4] Creating environment..."
REUSE=0
if "$PY" -c "import torch,sys; v=tuple(int(x) for x in torch.__version__.split('.')[:2]); sys.exit(0 if v>=(2,0) else 1)" >/dev/null 2>&1; then
  REUSE=1
  TVER=$("$PY" -c "import torch;print(torch.__version__)" 2>/dev/null)
  TCUDA=$("$PY" -c "import torch;print('yes' if torch.cuda.is_available() else 'no')" 2>/dev/null)
  echo -e "       ${{G}}Found PyTorch $TVER on your system (CUDA: $TCUDA)${{N}}"
  echo "       Reusing it - only a few MB will be downloaded."
fi
if [ -x ".venv/bin/python" ]; then
  echo -e "       ${{G}}OK - environment already exists${{N}}"
else
  if [ "$REUSE" = "1" ]; then
    "$PY" -m venv --system-site-packages .venv || {{ echo -e "       ${{R}}FAILED${{N}}"; exit 1; }}
  else
    "$PY" -m venv .venv || {{ echo -e "       ${{R}}FAILED${{N}}"; exit 1; }}
  fi
  echo -e "       ${{G}}OK - created${{N}}"
fi
VPY=".venv/bin/python"
echo

echo "  [3/4] Installing the AI engine..."
if [ -f ".venv/.installed" ]; then
  echo -e "       ${{G}}OK - already installed${{N}}"
else
  "$VPY" -m pip install --quiet --upgrade pip
  if [ "$REUSE" = "1" ]; then
    echo "       Using the PyTorch already on your system - skipping the big download."
  elif command -v nvidia-smi >/dev/null 2>&1; then
    echo "       NVIDIA GPU detected - installing CUDA build (about 2.5 GB)"
    "$VPY" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121 \\
      || "$VPY" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
  elif [ "$(uname -s)" = "Darwin" ]; then
    echo "       macOS detected - installing the standard build (about 250 MB)"
    "$VPY" -m pip install torch torchaudio
  else
    echo "       No NVIDIA GPU - installing the small CPU build (about 250 MB)"
    "$VPY" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
  fi
  "$VPY" -m pip install demucs soundfile || {{ echo -e "       ${{R}}FAILED${{N}}"; exit 1; }}
  touch .venv/.installed
  echo -e "       ${{G}}OK - installed${{N}}"
fi
echo

# unpack the embedded engine (single heredoc, decoded portably)
if base64 --help 2>&1 | grep -q -- '-d,'; then DEC="base64 -d"; else DEC="base64 --decode"; fi
cat <<'XVVIIX_B64' > .xvviix_payload.b64
{payload}
XVVIIX_B64
$DEC < .xvviix_payload.b64 > xvviix_engine.py || {{
  echo -e "       ${{R}}FAILED to unpack the engine${{N}}"; rm -f .xvviix_payload.b64; exit 1;
}}
rm -f .xvviix_payload.b64

echo "  [4/4] Starting the engine..."
echo
echo "  ============================================================"
echo -e "     ${{G}}READY${{N}}"
echo "     Go back to the website - it connects automatically."
echo "     Keep this window open. Press Ctrl+C to stop."
echo "  ============================================================"
echo
"$VPY" xvviix_engine.py
"""

OUT_BAT.write_bytes(BAT.replace("\n", "\r\n").encode("ascii", "strict"))
OUT_SH.write_text(SH, encoding="utf-8")
OUT_SH.chmod(0o755)

print(f"engine source : {SRC.stat().st_size:,} bytes")
print(f"install-xvviix.bat : {OUT_BAT.stat().st_size:,} bytes (ASCII, CRLF)")
print(f"install-xvviix.sh  : {OUT_SH.stat().st_size:,} bytes")


# ---------------------------------------------------------------------------
# Embed both installers into index.html as base64 so the download button
# never needs a network request (immune to CORS, opaque origins, offline).
# ---------------------------------------------------------------------------
def embed_in_page():
    page = ROOT / "index.html"
    if not page.exists():
        print("index.html not found - skipping embed")
        return
    html = page.read_text(encoding="utf-8")

    bat_b64 = base64.b64encode(OUT_BAT.read_bytes()).decode()
    sh_b64  = base64.b64encode(OUT_SH.read_bytes()).decode()

    block = (
        "<script>window.XVVIIX_INSTALLERS={"
        + '"bat":"' + bat_b64 + '",'
        + '"sh":"'  + sh_b64  + '"'
        + "};</script>"
    )

    start = "<!--INSTALLER-PAYLOAD-->"
    end = "<!--/INSTALLER-PAYLOAD-->"
    new = start + block + end

    if start in html and end in html:
        i = html.index(start)
        j = html.index(end) + len(end)
        html = html[:i] + new + html[j:]
    elif start in html:
        html = html.replace(start, new, 1)
    else:
        print("payload marker missing in index.html - skipping embed")
        return

    page.write_text(html, encoding="utf-8")
    kb = (len(bat_b64) + len(sh_b64)) / 1024
    print(f"embedded installers into index.html  (+{kb:.1f} KB base64)")


embed_in_page()
