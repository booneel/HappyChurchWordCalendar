@echo off
chcp 65001 > nul
cd /d "%~dp0"

call .venv\Scripts\python.exe build_review.py ^
  --input "output\titles.json" ^
  --output "output\review.html"

if exist "output\review.html" start "" "output\review.html"

pause
