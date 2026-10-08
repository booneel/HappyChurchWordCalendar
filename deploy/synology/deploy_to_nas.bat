@echo off
setlocal
chcp 65001 > nul
cd /d "%~dp0..\.."

where ssh >nul 2>nul
if errorlevel 1 goto :missing_ssh
where scp >nul 2>nul
if errorlevel 1 goto :missing_ssh

if not exist "deploy\synology\compose.yaml" goto :missing_files
if not exist "python\Dockerfile.nas" goto :missing_files
if not exist "python\nas_api.py" goto :missing_files
if not exist "python\nas_requirements.txt" goto :missing_files

echo This copies the NAS API files and rebuilds/restarts the wordcalendar-api container.
echo It does not copy .env or Firebase export data.
set "NAS_TARGET="
set /p "NAS_TARGET=SSH target (example: admin@192.168.0.20): "
if "%NAS_TARGET%"=="" goto :invalid_target

echo.
echo Checking the NAS folders and private .env file...
ssh "%NAS_TARGET%" "test -f /volume1/docker/wordcalendar/.env && test -d /volume1/docker/wordcalendar/app && test -d /volume1/wordcalendar-data && echo NAS_READY"
if errorlevel 1 goto :nas_not_ready

echo.
echo Copying compose.yaml and NAS API files...
scp "deploy\synology\compose.yaml" "%NAS_TARGET%:/volume1/docker/wordcalendar/compose.yaml"
if errorlevel 1 goto :copy_failed
scp "python\Dockerfile.nas" "%NAS_TARGET%:/volume1/docker/wordcalendar/app/Dockerfile.nas"
if errorlevel 1 goto :copy_failed
scp "python\nas_api.py" "%NAS_TARGET%:/volume1/docker/wordcalendar/app/nas_api.py"
if errorlevel 1 goto :copy_failed
scp "python\nas_requirements.txt" "%NAS_TARGET%:/volume1/docker/wordcalendar/app/nas_requirements.txt"
if errorlevel 1 goto :copy_failed

echo.
echo Rebuilding and starting the NAS API. Enter the NAS password if requested.
ssh -t "%NAS_TARGET%" "cd /volume1/docker/wordcalendar && sudo docker compose up -d --build && sudo docker compose ps"
if errorlevel 1 goto :start_failed

echo.
echo Deployment command completed. Verify the API using the curl commands in README.md.
pause
exit /b 0

:missing_ssh
echo Windows OpenSSH Client is required. Install it from Settings ^> System ^> Optional features.
pause
exit /b 1

:missing_files
echo Required project files are missing. Run this BAT from the repository copy in its deploy\synology folder.
pause
exit /b 1

:invalid_target
echo Enter the NAS SSH account and host, for example admin@192.168.0.20.
pause
exit /b 1

:nas_not_ready
echo NAS precheck failed. Check SSH target/authentication, /volume1/docker/wordcalendar/app, its private .env, and the wordcalendar-data shared folder.
pause
exit /b 1

:copy_failed
echo File copy failed. Check the SSH target, account permissions, and destination folders.
pause
exit /b 1

:start_failed
echo Container startup failed. Check Container Manager is installed and read the compose logs on the NAS.
pause
exit /b 1
