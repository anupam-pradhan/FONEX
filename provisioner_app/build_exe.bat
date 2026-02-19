@echo off
REM ============================================================
REM  FONEX Provisioner — Build Windows EXE
REM  Run this ONCE on your Windows machine to create the .exe
REM ============================================================

title Building FONEX Provisioner...
echo.
echo  [1/3] Installing Python dependencies...
pip install -r requirements.txt
pip install pyinstaller

echo.
echo  [2/3] Building FONEX_Provisioner.exe...
pyinstaller ^
  --onefile ^
  --windowed ^
  --name FONEX_Provisioner ^
  --icon=fonex_icon.ico ^
  fonex_provisioner.py

REM Note: Remove --icon flag if you don't have fonex_icon.ico yet

echo.
echo  [3/3] Done!
echo.
echo  Your EXE is at:  dist\FONEX_Provisioner.exe
echo.
echo  ============================================================
echo  IMPORTANT: Copy adb.exe (from Android Platform Tools) into
echo  the same folder as FONEX_Provisioner.exe
echo  ============================================================
echo.
pause
