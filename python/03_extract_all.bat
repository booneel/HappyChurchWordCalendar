@echo off
chcp 65001 > nul
cd /d "%~dp0"

if not exist "365일 매일묵상말씀.pdf" (
  echo 현재 폴더에 "365일 매일묵상말씀.pdf" 파일을 넣어주세요.
  pause
  exit /b 1
)

call .venv\Scripts\python.exe extract_titles_ai.py ^
  --pdf "365일 매일묵상말씀.pdf" ^
  --year 2026 ^
  --workers 3

pause
