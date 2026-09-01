@echo off
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
    for /f "delims=" %%c in ('python -c "import torch;print('yes' if torch.cuda.is_available() else 'no')" 2^>nul') do set TCUDA=%%c
    echo        Found PyTorch !TVER! on your system ^(CUDA: !TCUDA!^)
    echo        Reusing it - only a few MB will be downloaded.
)
if exist ".venv\Scripts\python.exe" (
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
set "PY=.venv\Scripts\python.exe"
echo.

echo  [3/4] Installing the AI engine...
if exist ".venv\.installed" (
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
echo done>".venv\.installed"
echo        OK - installed
echo.

:writeengine
set "B64=%TEMP%\xvviix_b64_%RANDOM%.txt"
if exist "%B64%" del "%B64%"
echo IiIiClhWVklJWCAtIGxvY2FsIEdQVS9DUFUgZW5naW5lLgoKUnVucyBEZW11Y3Mgb24gdGhlIHVzZXIncyBvd24gbWFjaGluZSBhbmQgZXhwb3NlcyBhIHRp>>"%B64%"
echo bnkgSFRUUCBBUEkgdGhhdCB0aGUKd2Vic2l0ZSAoaG9zdGVkIG9uIEdpdEh1YiBQYWdlcykgY2FuIGNhbGwuIEF1ZGlvIG5ldmVyIGxlYXZlcyB0aGUgbWFj>>"%B64%"
echo aGluZS4KClN0YXJ0ZWQgYXV0b21hdGljYWxseSBieSBpbnN0YWxsLXh2dmlpeC5iYXQgLyBpbnN0YWxsLXh2dmlpeC5zaC4KIiIiCgppbXBvcnQganNvbgpp>>"%B64%"
echo bXBvcnQgb3MKaW1wb3J0IHJlCmltcG9ydCBzaHV0aWwKaW1wb3J0IHN1YnByb2Nlc3MKaW1wb3J0IHN5cwppbXBvcnQgdGhyZWFkaW5nCmltcG9ydCB1dWlk>>"%B64%"
echo CmZyb20gZW1haWwucGFyc2VyIGltcG9ydCBCeXRlc1BhcnNlcgpmcm9tIGVtYWlsLnBvbGljeSBpbXBvcnQgZGVmYXVsdApmcm9tIGh0dHAuc2VydmVyIGlt>>"%B64%"
echo cG9ydCBUaHJlYWRpbmdIVFRQU2VydmVyLCBCYXNlSFRUUFJlcXVlc3RIYW5kbGVyCmZyb20gcGF0aGxpYiBpbXBvcnQgUGF0aApmcm9tIHVybGxpYi5wYXJz>>"%B64%"
echo ZSBpbXBvcnQgdW5xdW90ZQoKUk9PVCA9IFBhdGgoX19maWxlX18pLnJlc29sdmUoKS5wYXJlbnQKVVBMT0FEUyA9IFJPT1QgLyAidXBsb2FkcyIKT1VUUFVU>>"%B64%"
echo UyA9IFJPT1QgLyAib3V0cHV0cyIKVVBMT0FEUy5ta2RpcihleGlzdF9vaz1UcnVlKQpPVVRQVVRTLm1rZGlyKGV4aXN0X29rPVRydWUpCgpIT1NUID0gb3Mu>>"%B64%"
echo ZW52aXJvbi5nZXQoIlhWVklJWF9IT1NUIiwgIjEyNy4wLjAuMSIpClBPUlQgPSBpbnQob3MuZW52aXJvbi5nZXQoIlhWVklJWF9QT1JUIiwgIjg3NjUiKSkK>>"%B64%"
echo TUFYX1VQTE9BRCA9IDUwMCAqIDEwMjQgKiAxMDI0CkFMTE9XRURfRVhUID0geyIud2F2IiwgIi5tcDMiLCAiLmZsYWMiLCAiLm00YSIsICIuYWFjIiwgIi5v>>"%B64%"
echo Z2ciLCAiLmFpZmYiLCAiLmFpZiJ9ClNURU1fTkFNRVMgPSB7InZvY2FscyIsICJkcnVtcyIsICJiYXNzIiwgIm90aGVyIn0KU0FGRSA9IHJlLmNvbXBpbGUo>>"%B64%"
echo ciJeW1x3LlwtXSskIikKUFJPR1JFU1NfUkUgPSByZS5jb21waWxlKHIiKFxkezEsM30pJSIpCgpqb2JzID0ge30KCgpkZWYgZ3B1X2luZm8oKToKICAgIHRy>>"%B64%"
echo eToKICAgICAgICBpbXBvcnQgdG9yY2gKCiAgICAgICAgaWYgdG9yY2guY3VkYS5pc19hdmFpbGFibGUoKToKICAgICAgICAgICAgcmV0dXJuIHsiZGV2aWNl>>"%B64%"
echo IjogImN1ZGEiLCAibmFtZSI6IHRvcmNoLmN1ZGEuZ2V0X2RldmljZV9uYW1lKDApfQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBwYXNzCiAgICBy>>"%B64%"
echo ZXR1cm4geyJkZXZpY2UiOiAiY3B1IiwgIm5hbWUiOiAiQ1BVIn0KCgpERVZJQ0UgPSBncHVfaW5mbygpCgoKY2xhc3MgSGFuZGxlcihCYXNlSFRUUFJlcXVl>>"%B64%"
echo c3RIYW5kbGVyKToKICAgIHNlcnZlcl92ZXJzaW9uID0gIlhWVklJWC8yLjAiCgogICAgZGVmIGxvZ19tZXNzYWdlKHNlbGYsIGZtdCwgKmFyZ3MpOgogICAg>>"%B64%"
echo ICAgICMga2VlcCB0aGUgY29uc29sZSByZWFkYWJsZSBmb3Igbm9uLXRlY2huaWNhbCB1c2VycwogICAgICAgIGlmICIvYXBpL2hlYWx0aCIgbm90IGluIChh>>"%B64%"
echo cmdzWzBdIGlmIGFyZ3MgZWxzZSAiIik6CiAgICAgICAgICAgIHN5cy5zdGRvdXQud3JpdGUoIiAgLSAlc1xuIiAlIChmbXQgJSBhcmdzKSkKCiAgICBkZWYg>>"%B64%"
echo X2NvcnMoc2VsZik6CiAgICAgICAgb3JpZ2luID0gc2VsZi5oZWFkZXJzLmdldCgiT3JpZ2luIikKICAgICAgICBpZiBvcmlnaW46CiAgICAgICAgICAgIHNl>>"%B64%"
echo bGYuc2VuZF9oZWFkZXIoIkFjY2Vzcy1Db250cm9sLUFsbG93LU9yaWdpbiIsIG9yaWdpbikKICAgICAgICAgICAgc2VsZi5zZW5kX2hlYWRlcigiVmFyeSIs>>"%B64%"
echo ICJPcmlnaW4iKQogICAgICAgIGVsc2U6CiAgICAgICAgICAgIHNlbGYuc2VuZF9oZWFkZXIoIkFjY2Vzcy1Db250cm9sLUFsbG93LU9yaWdpbiIsICIqIikK>>"%B64%"
echo ICAgICAgICBzZWxmLnNlbmRfaGVhZGVyKCJBY2Nlc3MtQ29udHJvbC1BbGxvdy1IZWFkZXJzIiwgIkNvbnRlbnQtVHlwZSwgUmFuZ2UiKQogICAgICAgIHNl>>"%B64%"
echo bGYuc2VuZF9oZWFkZXIoIkFjY2Vzcy1Db250cm9sLUFsbG93LU1ldGhvZHMiLCAiR0VULCBQT1NULCBIRUFELCBPUFRJT05TIikKICAgICAgICBzZWxmLnNl>>"%B64%"
echo bmRfaGVhZGVyKCJBY2Nlc3MtQ29udHJvbC1FeHBvc2UtSGVhZGVycyIsICJDb250ZW50LUxlbmd0aCwgQ29udGVudC1SYW5nZSwgQWNjZXB0LVJhbmdlcyIp>>"%B64%"
echo CiAgICAgICAgc2VsZi5zZW5kX2hlYWRlcigiQWNjZXNzLUNvbnRyb2wtTWF4LUFnZSIsICI4NjQwMCIpCgogICAgZGVmIGVuZF9oZWFkZXJzKHNlbGYpOgog>>"%B64%"
echo ICAgICAgIHNlbGYuc2VuZF9oZWFkZXIoIkNhY2hlLUNvbnRyb2wiLCAibm8tc3RvcmUiKQogICAgICAgIHNlbGYuX2NvcnMoKQogICAgICAgIHN1cGVyKCku>>"%B64%"
echo ZW5kX2hlYWRlcnMoKQoKICAgIGRlZiBkb19PUFRJT05TKHNlbGYpOgogICAgICAgIHNlbGYuc2VuZF9yZXNwb25zZSgyMDQpCiAgICAgICAgc2VsZi5zZW5k>>"%B64%"
echo X2hlYWRlcigiQ29udGVudC1MZW5ndGgiLCAiMCIpCiAgICAgICAgc2VsZi5lbmRfaGVhZGVycygpCgogICAgZGVmIHNlbmRfanNvbihzZWxmLCBkYXRhLCBj>>"%B64%"
echo b2RlPTIwMCk6CiAgICAgICAgcmF3ID0ganNvbi5kdW1wcyhkYXRhKS5lbmNvZGUoKQogICAgICAgIHNlbGYuc2VuZF9yZXNwb25zZShjb2RlKQogICAgICAg>>"%B64%"
echo IHNlbGYuc2VuZF9oZWFkZXIoIkNvbnRlbnQtVHlwZSIsICJhcHBsaWNhdGlvbi9qc29uIikKICAgICAgICBzZWxmLnNlbmRfaGVhZGVyKCJDb250ZW50LUxl>>"%B64%"
echo bmd0aCIsIHN0cihsZW4ocmF3KSkpCiAgICAgICAgc2VsZi5lbmRfaGVhZGVycygpCiAgICAgICAgc2VsZi53ZmlsZS53cml0ZShyYXcpCgogICAgIyAtLS0t>>"%B64%"
echo LS0tLS0tLS0tLS0tIFBPU1QgLS0tLS0tLS0tLS0tLS0tLQogICAgZGVmIGRvX1BPU1Qoc2VsZik6CiAgICAgICAgaWYgc2VsZi5wYXRoICE9ICIvYXBpL3Nw>>"%B64%"
echo bGl0IjoKICAgICAgICAgICAgc2VsZi5zZW5kX2pzb24oeyJlcnJvciI6ICJOb3QgZm91bmQifSwgNDA0KQogICAgICAgICAgICByZXR1cm4KICAgICAgICB0>>"%B64%"
echo cnk6CiAgICAgICAgICAgIGxlbmd0aCA9IGludChzZWxmLmhlYWRlcnMuZ2V0KCJDb250ZW50LUxlbmd0aCIsICIwIikpCiAgICAgICAgICAgIGlmIGxlbmd0>>"%B64%"
echo aCA8PSAwOgogICAgICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiRW1wdHkgcmVxdWVzdCIpCiAgICAgICAgICAgIGlmIGxlbmd0aCA+IE1BWF9VUExP>>"%B64%"
echo QUQ6CiAgICAgICAgICAgICAgICBzZWxmLnNlbmRfanNvbih7ImVycm9yIjogIkZpbGUgbGFyZ2VyIHRoYW4gNTAwIE1CIn0sIDQxMykKICAgICAgICAgICAg>>"%B64%"
echo ICAgIHJldHVybgogICAgICAgICAgICBjdHlwZSA9IHNlbGYuaGVhZGVycy5nZXQoIkNvbnRlbnQtVHlwZSIsICIiKQogICAgICAgICAgICBpZiAibXVsdGlw>>"%B64%"
echo YXJ0L2Zvcm0tZGF0YSIgbm90IGluIGN0eXBlOgogICAgICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiRXhwZWN0ZWQgbXVsdGlwYXJ0L2Zvcm0tZGF0>>"%B64%"
echo YSIpCgogICAgICAgICAgICBib2R5ID0gc2VsZi5yZmlsZS5yZWFkKGxlbmd0aCkKICAgICAgICAgICAgbXNnID0gQnl0ZXNQYXJzZXIocG9saWN5PWRlZmF1>>"%B64%"
echo bHQpLnBhcnNlYnl0ZXMoCiAgICAgICAgICAgICAgICBmIkNvbnRlbnQtVHlwZToge2N0eXBlfVxyXG5NSU1FLVZlcnNpb246IDEuMFxyXG5cclxuIi5lbmNv>>"%B64%"
echo ZGUoKSArIGJvZHkKICAgICAgICAgICAgKQoKICAgICAgICAgICAgZmlsZW5hbWUgPSBmaWxlZGF0YSA9IE5vbmUKICAgICAgICAgICAgZmllbGRzID0ge30K>>"%B64%"
echo ICAgICAgICAgICAgZm9yIHBhcnQgaW4gbXNnLml0ZXJfcGFydHMoKToKICAgICAgICAgICAgICAgIG5hbWUgPSBwYXJ0LmdldF9wYXJhbSgibmFtZSIsIGhl>>"%B64%"
echo YWRlcj0iY29udGVudC1kaXNwb3NpdGlvbiIpCiAgICAgICAgICAgICAgICBpZiBuYW1lID09ICJmaWxlIjoKICAgICAgICAgICAgICAgICAgICBmaWxlbmFt>>"%B64%"
echo ZSA9IHBhcnQuZ2V0X2ZpbGVuYW1lKCkKICAgICAgICAgICAgICAgICAgICBmaWxlZGF0YSA9IHBhcnQuZ2V0X3BheWxvYWQoZGVjb2RlPVRydWUpCiAgICAg>>"%B64%"
echo ICAgICAgICAgICBlbGlmIG5hbWU6CiAgICAgICAgICAgICAgICAgICAgZmllbGRzW25hbWVdID0gcGFydC5nZXRfY29udGVudCgpCgogICAgICAgICAgICBp>>"%B64%"
echo ZiBub3QgZmlsZW5hbWUgb3Igbm90IGZpbGVkYXRhOgogICAgICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiTm8gYXVkaW8gZmlsZSByZWNlaXZlZCIp>>"%B64%"
echo CiAgICAgICAgICAgIGV4dCA9IFBhdGgoZmlsZW5hbWUpLnN1ZmZpeC5sb3dlcigpIG9yICIud2F2IgogICAgICAgICAgICBpZiBleHQgbm90IGluIEFMTE9X>>"%B64%"
echo RURfRVhUOgogICAgICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcihmJ1Vuc3VwcG9ydGVkIGZpbGUgdHlwZSAie2V4dH0iJykKCiAgICAgICAgICAgIHRy>>"%B64%"
echo eToKICAgICAgICAgICAgICAgIHN0ZW1zID0ganNvbi5sb2FkcyhmaWVsZHMuZ2V0KCJzdGVtcyIsICJbXSIpKQogICAgICAgICAgICBleGNlcHQganNvbi5K>>"%B64%"
echo U09ORGVjb2RlRXJyb3I6CiAgICAgICAgICAgICAgICBzdGVtcyA9IFtdCiAgICAgICAgICAgIHN0ZW1zID0gW3MgZm9yIHMgaW4gc3RlbXMgaWYgcyBpbiBT>>"%B64%"
echo VEVNX05BTUVTXSBvciBsaXN0KFNURU1fTkFNRVMpCgogICAgICAgICAgICBqb2IgPSBzdHIodXVpZC51dWlkNCgpKQogICAgICAgICAgICBzcmMgPSBVUExP>>"%B64%"
echo QURTIC8gKGpvYiArIGV4dCkKICAgICAgICAgICAgc3JjLndyaXRlX2J5dGVzKGZpbGVkYXRhKQogICAgICAgICAgICBqb2JzW2pvYl0gPSB7InN0YXR1cyI6>>"%B64%"
echo ICJxdWV1ZWQiLCAicHJvZ3Jlc3MiOiAwLCAibmFtZSI6IGZpbGVuYW1lfQogICAgICAgICAgICB0aHJlYWRpbmcuVGhyZWFkKHRhcmdldD1ydW5fc3BsaXQs>>"%B64%"
echo IGFyZ3M9KGpvYiwgc3JjLCBzdGVtcyksIGRhZW1vbj1UcnVlKS5zdGFydCgpCiAgICAgICAgICAgIHNlbGYuc2VuZF9qc29uKHsiam9iX2lkIjogam9ifSkK>>"%B64%"
echo ICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgc2VsZi5zZW5kX2pzb24oeyJlcnJvciI6IHN0cihleGMpfSwgNDAwKQoKICAg>>"%B64%"
echo ICMgLS0tLS0tLS0tLS0tLS0tLSBHRVQgLS0tLS0tLS0tLS0tLS0tLQogICAgZGVmIGRvX0hFQUQoc2VsZik6CiAgICAgICAgc2VsZi5kb19HRVQoKQoKICAg>>"%B64%"
echo IGRlZiBkb19HRVQoc2VsZik6CiAgICAgICAgaWYgc2VsZi5wYXRoID09ICIvYXBpL2hlYWx0aCI6CiAgICAgICAgICAgIHNlbGYuc2VuZF9qc29uKHsKICAg>>"%B64%"
echo ICAgICAgICAgICAgICJhcHAiOiAiWFZWSUlYIiwKICAgICAgICAgICAgICAgICJ2ZXJzaW9uIjogIjIuMCIsCiAgICAgICAgICAgICAgICAiZW5naW5lIjog>>"%B64%"
echo ImRlbXVjcyIsCiAgICAgICAgICAgICAgICAiZGV2aWNlIjogREVWSUNFWyJkZXZpY2UiXSwKICAgICAgICAgICAgICAgICJkZXZpY2VfbmFtZSI6IERFVklD>>"%B64%"
echo RVsibmFtZSJdLAogICAgICAgICAgICAgICAgIm9rIjogVHJ1ZSwKICAgICAgICAgICAgfSkKICAgICAgICAgICAgcmV0dXJuCgogICAgICAgIGlmIHNlbGYu>>"%B64%"
echo cGF0aC5zdGFydHN3aXRoKCIvYXBpL3N0YXR1cy8iKToKICAgICAgICAgICAgam9iID0gc2VsZi5wYXRoLnJzcGxpdCgiLyIsIDEpWy0xXQogICAgICAgICAg>>"%B64%"
echo ICBzZWxmLnNlbmRfanNvbihqb2JzLmdldChqb2IsIHsiZXJyb3IiOiAiVW5rbm93biBqb2IifSkpCiAgICAgICAgICAgIHJldHVybgoKICAgICAgICBpZiBz>>"%B64%"
echo ZWxmLnBhdGguc3RhcnRzd2l0aCgiL2FwaS9kb3dubG9hZC8iKToKICAgICAgICAgICAgc2VsZi5fZG93bmxvYWQoKQogICAgICAgICAgICByZXR1cm4KCiAg>>"%B64%"
echo ICAgICAgc2VsZi5zZW5kX2pzb24oeyJlcnJvciI6ICJOb3QgZm91bmQifSwgNDA0KQoKICAgIGRlZiBfZG93bmxvYWQoc2VsZik6CiAgICAgICAgcGF0aCwg>>"%B64%"
echo XywgcXVlcnkgPSBzZWxmLnBhdGgucGFydGl0aW9uKCI/IikKICAgICAgICBpbmxpbmUgPSAiaW5saW5lPTEiIGluIHF1ZXJ5CiAgICAgICAgcGFydHMgPSBw>>"%B64%"
echo YXRoLnNwbGl0KCIvIikKICAgICAgICBpZiBsZW4ocGFydHMpICE9IDc6CiAgICAgICAgICAgIHNlbGYuc2VuZF9qc29uKHsiZXJyb3IiOiAiSW52YWxpZCBw>>"%B64%"
echo YXRoIn0sIDQwMCkKICAgICAgICAgICAgcmV0dXJuCiAgICAgICAgXywgXywgXywgam9iLCBtb2RlbCwgc29uZywgZmlsZW5hbWUgPSBbdW5xdW90ZShwKSBm>>"%B64%"
echo b3IgcCBpbiBwYXJ0c10KICAgICAgICBmb3IgYyBpbiAoam9iLCBtb2RlbCwgc29uZywgZmlsZW5hbWUpOgogICAgICAgICAgICBpZiBub3QgU0FGRS5tYXRj>>"%B64%"
echo aChjKSBvciAiLi4iIGluIGM6CiAgICAgICAgICAgICAgICBzZWxmLnNlbmRfanNvbih7ImVycm9yIjogIkludmFsaWQgcGF0aCJ9LCA0MDApCiAgICAgICAg>>"%B64%"
echo ICAgICAgICByZXR1cm4KCiAgICAgICAgcm9vdCA9IE9VVFBVVFMucmVzb2x2ZSgpCiAgICAgICAgdGFyZ2V0ID0gKE9VVFBVVFMgLyBqb2IgLyBtb2RlbCAv>>"%B64%"
echo IHNvbmcgLyBmaWxlbmFtZSkucmVzb2x2ZSgpCiAgICAgICAgdHJ5OgogICAgICAgICAgICB0YXJnZXQucmVsYXRpdmVfdG8ocm9vdCkKICAgICAgICBleGNl>>"%B64%"
echo cHQgVmFsdWVFcnJvcjoKICAgICAgICAgICAgc2VsZi5zZW5kX2pzb24oeyJlcnJvciI6ICJJbnZhbGlkIHBhdGgifSwgNDAwKQogICAgICAgICAgICByZXR1>>"%B64%"
echo cm4KICAgICAgICBpZiBub3QgdGFyZ2V0LmlzX2ZpbGUoKToKICAgICAgICAgICAgc2VsZi5zZW5kX2pzb24oeyJlcnJvciI6ICJOb3QgZm91bmQifSwgNDA0>>"%B64%"
echo KQogICAgICAgICAgICByZXR1cm4KCiAgICAgICAgc2l6ZSA9IHRhcmdldC5zdGF0KCkuc3Rfc2l6ZQogICAgICAgIHN0YXJ0LCBlbmQsIHN0YXR1cyA9IDAs>>"%B64%"
echo IHNpemUgLSAxLCAyMDAKICAgICAgICBybmcgPSBzZWxmLmhlYWRlcnMuZ2V0KCJSYW5nZSIsICIiKQogICAgICAgIG0gPSByZS5tYXRjaChyImJ5dGVzPShc>>"%B64%"
echo ZCopLShcZCopJCIsIHJuZy5zdHJpcCgpKSBpZiBybmcgZWxzZSBOb25lCiAgICAgICAgaWYgbSBhbmQgc2l6ZToKICAgICAgICAgICAgcywgZSA9IG0uZ3Jv>>"%B64%"
echo dXAoMSksIG0uZ3JvdXAoMikKICAgICAgICAgICAgaWYgczoKICAgICAgICAgICAgICAgIHN0YXJ0ID0gaW50KHMpCiAgICAgICAgICAgICAgICBpZiBlOgog>>"%B64%"
echo ICAgICAgICAgICAgICAgICAgIGVuZCA9IG1pbihpbnQoZSksIHNpemUgLSAxKQogICAgICAgICAgICBlbGlmIGU6CiAgICAgICAgICAgICAgICBzdGFydCA9>>"%B64%"
echo IG1heCgwLCBzaXplIC0gaW50KGUpKQogICAgICAgICAgICBpZiBzdGFydCA+IGVuZCBvciBzdGFydCA+PSBzaXplOgogICAgICAgICAgICAgICAgc2VsZi5z>>"%B64%"
echo ZW5kX3Jlc3BvbnNlKDQxNikKICAgICAgICAgICAgICAgIHNlbGYuc2VuZF9oZWFkZXIoIkNvbnRlbnQtUmFuZ2UiLCBmImJ5dGVzICove3NpemV9IikKICAg>>"%B64%"
echo ICAgICAgICAgICAgIHNlbGYuZW5kX2hlYWRlcnMoKQogICAgICAgICAgICAgICAgcmV0dXJuCiAgICAgICAgICAgIHN0YXR1cyA9IDIwNgoKICAgICAgICBs>>"%B64%"
echo ZW5ndGggPSBlbmQgLSBzdGFydCArIDEKICAgICAgICBzZWxmLnNlbmRfcmVzcG9uc2Uoc3RhdHVzKQogICAgICAgIHNlbGYuc2VuZF9oZWFkZXIoIkNvbnRl>>"%B64%"
echo bnQtVHlwZSIsICJhdWRpby93YXYiKQogICAgICAgIHNlbGYuc2VuZF9oZWFkZXIoIkFjY2VwdC1SYW5nZXMiLCAiYnl0ZXMiKQogICAgICAgIHNlbGYuc2Vu>>"%B64%"
echo ZF9oZWFkZXIoIkNvbnRlbnQtRGlzcG9zaXRpb24iLAogICAgICAgICAgICAgICAgICAgICAgICAgZid7ImlubGluZSIgaWYgaW5saW5lIGVsc2UgImF0dGFj>>"%B64%"
echo aG1lbnQifTsgZmlsZW5hbWU9IntmaWxlbmFtZX0iJykKICAgICAgICBzZWxmLnNlbmRfaGVhZGVyKCJDb250ZW50LUxlbmd0aCIsIHN0cihsZW5ndGgpKQog>>"%B64%"
echo ICAgICAgIGlmIHN0YXR1cyA9PSAyMDY6CiAgICAgICAgICAgIHNlbGYuc2VuZF9oZWFkZXIoIkNvbnRlbnQtUmFuZ2UiLCBmImJ5dGVzIHtzdGFydH0te2Vu>>"%B64%"
echo ZH0ve3NpemV9IikKICAgICAgICBzZWxmLmVuZF9oZWFkZXJzKCkKICAgICAgICBpZiBzZWxmLmNvbW1hbmQgPT0gIkhFQUQiOgogICAgICAgICAgICByZXR1>>"%B64%"
echo cm4KICAgICAgICB3aXRoIHRhcmdldC5vcGVuKCJyYiIpIGFzIGY6CiAgICAgICAgICAgIGYuc2VlayhzdGFydCkKICAgICAgICAgICAgbGVmdCA9IGxlbmd0>>"%B64%"
echo aAogICAgICAgICAgICB3aGlsZSBsZWZ0ID4gMDoKICAgICAgICAgICAgICAgIGNodW5rID0gZi5yZWFkKG1pbig2NTUzNiwgbGVmdCkpCiAgICAgICAgICAg>>"%B64%"
echo ICAgICBpZiBub3QgY2h1bms6CiAgICAgICAgICAgICAgICAgICAgYnJlYWsKICAgICAgICAgICAgICAgIHNlbGYud2ZpbGUud3JpdGUoY2h1bmspCiAgICAg>>"%B64%"
echo ICAgICAgICAgICBsZWZ0IC09IGxlbihjaHVuaykKCgpkZWYgcnVuX3NwbGl0KGpvYiwgc3JjLCBzdGVtcyk6CiAgICBvdXQgPSBPVVRQVVRTIC8gam9iCiAg>>"%B64%"
echo ICBvdXQubWtkaXIoZXhpc3Rfb2s9VHJ1ZSkKICAgIGpvYnNbam9iXS51cGRhdGUoc3RhdHVzPSJwcm9jZXNzaW5nIiwgcHJvZ3Jlc3M9NSkKICAgIG1vZGVs>>"%B64%"
echo ID0gImh0ZGVtdWNzIgogICAgdHJ5OgogICAgICAgIGNtZCA9IFtzeXMuZXhlY3V0YWJsZSwgIi1tIiwgImRlbXVjcyIsICItbiIsIG1vZGVsLCAiLS1vdXQi>>"%B64%"
echo LCBzdHIob3V0KSwgc3RyKHNyYyldCiAgICAgICAgaWYgREVWSUNFWyJkZXZpY2UiXSA9PSAiY3VkYSI6CiAgICAgICAgICAgIGNtZCArPSBbIi1kIiwgImN1>>"%B64%"
echo ZGEiXQogICAgICAgIHByb2MgPSBzdWJwcm9jZXNzLlBvcGVuKGNtZCwgc3Rkb3V0PXN1YnByb2Nlc3MuUElQRSwgc3RkZXJyPXN1YnByb2Nlc3MuU1RET1VU>>"%B64%"
echo LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRleHQ9VHJ1ZSwgYnVmc2l6ZT0xKQogICAgICAgIGZvciBsaW5lIGluIHByb2Muc3Rkb3V0Ogog>>"%B64%"
echo ICAgICAgICAgICBoaXQgPSBQUk9HUkVTU19SRS5zZWFyY2gobGluZSkKICAgICAgICAgICAgaWYgaGl0OgogICAgICAgICAgICAgICAgam9ic1tqb2JdWyJw>>"%B64%"
echo cm9ncmVzcyJdID0gbWF4KDUsIG1pbig5NSwgaW50KGhpdC5ncm91cCgxKSkpKQogICAgICAgIHByb2Mud2FpdCgpCiAgICAgICAgaWYgcHJvYy5yZXR1cm5j>>"%B64%"
echo b2RlICE9IDA6CiAgICAgICAgICAgIHJhaXNlIFJ1bnRpbWVFcnJvcigiRGVtdWNzIGNvdWxkIG5vdCBwcm9jZXNzIHRoaXMgZmlsZS4iKQoKICAgICAgICBm>>"%B64%"
echo b2xkZXIgPSBvdXQgLyBtb2RlbCAvIHNyYy5zdGVtCiAgICAgICAgZm91bmQgPSB7cC5zdGVtOiBwIGZvciBwIGluIGZvbGRlci5nbG9iKCIqLndhdiIpIGlm>>"%B64%"
echo IHAuaXNfZmlsZSgpfQogICAgICAgIGNob3NlbiA9IHtrOiB2IGZvciBrLCB2IGluIGZvdW5kLml0ZW1zKCkgaWYgayBpbiBzdGVtc30gb3IgZm91bmQKICAg>>"%B64%"
echo ICAgICBmaWxlcyA9IHtrOiBmIi9hcGkvZG93bmxvYWQve2pvYn0ve21vZGVsfS97c3JjLnN0ZW19L3t2Lm5hbWV9IiBmb3IgaywgdiBpbiBjaG9zZW4uaXRl>>"%B64%"
echo bXMoKX0KICAgICAgICBqb2JzW2pvYl0udXBkYXRlKHN0YXR1cz0iY29tcGxldGUiLCBwcm9ncmVzcz0xMDAsIGZpbGVzPWZpbGVzKQogICAgZXhjZXB0IEV4>>"%B64%"
echo Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgam9ic1tqb2JdLnVwZGF0ZShzdGF0dXM9ImVycm9yIiwgZXJyb3I9c3RyKGV4YykpCiAgICBmaW5hbGx5OgogICAg>>"%B64%"
echo ICAgIHRyeToKICAgICAgICAgICAgc3JjLnVubGluayhtaXNzaW5nX29rPVRydWUpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAgICAgcGFz>>"%B64%"
echo cwoKCmRlZiBtYWluKCk6CiAgICBsaW5lID0gIj0iICogNTgKICAgIHByaW50KGxpbmUpCiAgICBwcmludCgiICAgWFZWSUlYIC0gTG9jYWwgRW5naW5lIikK>>"%B64%"
echo ICAgIHByaW50KGxpbmUpCiAgICBwcmludChmIiAgIERldmljZSAgOiB7REVWSUNFWyduYW1lJ119IikKICAgIHByaW50KGYiICAgQWRkcmVzcyA6IGh0dHA6>>"%B64%"
echo Ly97SE9TVH06e1BPUlR9IikKICAgIHByaW50KGxpbmUpCiAgICBwcmludCgpCiAgICBwcmludCgiICAgUkVBRFkgLSBnbyBiYWNrIHRvIHRoZSB3ZWJzaXRl>>"%B64%"
echo LCBpdCBjb25uZWN0cyBhdXRvbWF0aWNhbGx5LiIpCiAgICBwcmludCgiICAgS2VlcCB0aGlzIHdpbmRvdyBvcGVuLiBQcmVzcyBDdHJsK0MgdG8gc3RvcC4i>>"%B64%"
echo KQogICAgcHJpbnQoKQogICAgdHJ5OgogICAgICAgIFRocmVhZGluZ0hUVFBTZXJ2ZXIoKEhPU1QsIFBPUlQpLCBIYW5kbGVyKS5zZXJ2ZV9mb3JldmVyKCkK>>"%B64%"
echo ICAgIGV4Y2VwdCBLZXlib2FyZEludGVycnVwdDoKICAgICAgICBwcmludCgiXG4gICBFbmdpbmUgc3RvcHBlZC4iKQoKCmlmIF9fbmFtZV9fID09ICJfX21h>>"%B64%"
echo aW5fXyI6CiAgICBtYWluKCkK>>"%B64%"
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
