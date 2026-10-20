@echo off
cd /d "C:\Dossiers personels\AfidiPro"
call npm run build
if %ERRORLEVEL% NEQ 0 (
    echo Build web failed
    pause
    exit /b %ERRORLEVEL%
)
echo.
echo Build web completed. Now building Android...
echo.
call npx cap build android
pause
