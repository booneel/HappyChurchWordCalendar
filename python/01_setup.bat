@echo off
chcp 65001 > nul
cd /d "%~dp0"

echo [1/3] Python 가상환경 생성
python -m venv .venv
if errorlevel 1 goto :error

echo [2/3] pip 업데이트
call .venv\Scripts\python.exe -m pip install --upgrade pip
if errorlevel 1 goto :error

echo [3/3] 패키지 설치
call .venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 goto :error

if not exist .env (
  copy .env.example .env > nul
)

echo.
echo 완료.
echo 이제 .env 파일을 메모장으로 열어 OPENAI_API_KEY를 입력하세요.
pause
exit /b 0

:error
echo.
echo 설치 중 오류가 발생했습니다.
pause
exit /b 1
