@echo off
setlocal
chcp 65001 > nul
cd /d "%~dp0..\.."

where flutter >nul 2>nul
if errorlevel 1 goto :missing_flutter

echo Build a NAS-connected Android release APK.
echo The user token will be embedded in the APK. Only share it with trusted users.
set "NAS_BASE_URL="
set "NAS_TOKEN="
set /p "NAS_BASE_URL=Tailscale HTTPS base URL (example: https://nas-name.example.ts.net): "
if "%NAS_BASE_URL%"=="" goto :missing_url

echo.
echo Enter the NAS user token. It will not be echoed in this window.
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "$secure = Read-Host 'NAS user token' -AsSecureString; [System.Net.NetworkCredential]::new('', $secure).Password"`) do set "NAS_TOKEN=%%T"
if not defined NAS_TOKEN goto :missing_token

call flutter pub get
if errorlevel 1 goto :build_failed

flutter build apk --release --dart-define=WORDCALENDAR_BACKEND=nas --dart-define=WORDCALENDAR_NAS_BASE_URL=%NAS_BASE_URL% --dart-define=WORDCALENDAR_NAS_TOKEN=%NAS_TOKEN%
if errorlevel 1 goto :build_failed

copy /y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\wordcalendar-nas.apk" >nul
if errorlevel 1 goto :copy_failed

set "NAS_TOKEN="
echo.
echo NAS APK created: build\app\outputs\flutter-apk\wordcalendar-nas.apk
echo Install it on a phone with Tailscale connected to the same tailnet.
pause
exit /b 0

:missing_flutter
echo Flutter is not installed or flutter is not on PATH.
pause
exit /b 1

:missing_url
echo Enter the NAS Tailscale HTTPS base URL.
pause
exit /b 1

:missing_token
echo No token was entered.
pause
exit /b 1

:build_failed
set "NAS_TOKEN="
echo Build failed. Review the Flutter output above.
pause
exit /b 1

:copy_failed
set "NAS_TOKEN="
echo APK build completed but copying the named APK failed.
pause
exit /b 1
