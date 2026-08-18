@echo off
echo ================================================================
echo              BELEKA PRO POS - WINDOWS BUILD SCRIPT              
echo ================================================================
echo.

REM 1. Clean and fetch packages
echo [*] Fetching Flutter dependencies...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo [!] flutter pub get failed.
    pause
    exit /b %ERRORLEVEL%
)

REM 2. Update Launcher Icons
echo [*] Updating Windows app icons...
call dart run flutter_launcher_icons

REM 3. Build Windows 64-bit Release Binary
echo [*] Compiling Release Windows Application...
call flutter build windows --release
if %ERRORLEVEL% neq 0 (
    echo [!] Windows compilation failed. Make sure "Desktop development with C++" is installed in Visual Studio.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ================================================================
echo                   BUILD COMPLETED SUCCESSFULLY!                
echo ================================================================
echo Release Directory:
echo %CD%\build\windows\x64\runner\Release\
echo.
echo You can run BelekaPOS.exe directly from that folder.
echo ================================================================
pause
