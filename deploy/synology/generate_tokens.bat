@echo off
setlocal

where py >nul 2>nul
if %errorlevel%==0 goto use_py

where python >nul 2>nul
if %errorlevel%==0 goto use_python

echo Python 3 was not found. Install Python for Windows, then run this file again.
pause
exit /b 1

:use_py
py -3 -c "import secrets; print('WORDCALENDAR_NAS_TOKEN='+secrets.token_urlsafe(48)); print('WORDCALENDAR_NAS_ADMIN_TOKEN='+secrets.token_urlsafe(48)); print('WORDCALENDAR_NAS_PUSH_SECRET='+secrets.token_urlsafe(48))"
goto done

:use_python
python -c "import secrets; print('WORDCALENDAR_NAS_TOKEN='+secrets.token_urlsafe(48)); print('WORDCALENDAR_NAS_ADMIN_TOKEN='+secrets.token_urlsafe(48)); print('WORDCALENDAR_NAS_PUSH_SECRET='+secrets.token_urlsafe(48))"

:done
echo.
echo Copy each value into the matching private .env file. Do not commit or share them.
pause
