@echo off
setlocal enabledelayedexpansion

:: ANSI color codes (requires Windows 10 1511+)
for /f %%A in ('echo prompt $E ^| cmd') do set "ESC=%%A"
set "RESET=%ESC%[0m"
set "WHITE=%ESC%[97m"
set "BLUE=%ESC%[94m"
set "GREEN=%ESC%[92m"
set "RED=%ESC%[91m"

:: ============================================================
echo.
echo %BLUE%[STEP 1]%WHITE% Extracting version from manifest.json...%RESET%
:: ============================================================
for /f "tokens=2 delims=:, " %%A in ('findstr /C:"\"version\"" custom_components\chrono_folder\manifest.json') do (
    set RAW_VERSION=%%A
)
:: Strip surrounding quotes
set PROJECT_VERSION=%RAW_VERSION:"=%

if "%PROJECT_VERSION%"=="" (
    echo %RED%!! ERROR: Could not find version in custom_components\chrono_folder\manifest.json !!%RESET%
    pause & exit /b 1
)
echo  PROJECT_VERSION: %PROJECT_VERSION%

:: ============================================================
echo.
echo %BLUE%[STEP 2]%WHITE% Determining release mode...%RESET%
:: ============================================================
git rev-parse "%PROJECT_VERSION%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set MODE=UPDATE
) else (
    set MODE=RELEASE
)
echo  MODE: %MODE%

:: ============================================================
echo.
echo %BLUE%[STEP 3]%WHITE% Validating commit message...%RESET%
:: ============================================================
set MSG=%~1

if "%MODE%"=="RELEASE" (
    if "%MSG%"=="" (
        echo.
        echo %RED%!! ERROR: A comment is REQUIRED for a new release. !!%RESET%
        echo %RED%!! Usage: release.bat "Your commit message"         !!%RESET%
        pause & exit /b 1
    )
    echo  MESSAGE: %MSG%
) else (
    echo  MESSAGE: N/A - UPDATE mode
)

:: ============================================================
echo.
echo %BLUE%[STEP 4]%WHITE% Creating backup zip...%RESET%
:: ============================================================
set BACKUP_FILE=backup\chrono_folder_%PROJECT_VERSION%.zip

if exist "%BACKUP_FILE%" (
    attrib -r "%BACKUP_FILE%"
    del /f "%BACKUP_FILE%"
)

if not exist backup mkdir backup

"C:\Program Files\7-Zip\7z.exe" a "%BACKUP_FILE%" "custom_components\chrono_folder\*" -r >nul
if %ERRORLEVEL% NEQ 0 (
    echo %RED%!! ERROR: Backup zip failed. Check 7-Zip installation. !!%RESET%
    pause & exit /b 1
)
echo %GREEN%[BACKUP] %BACKUP_FILE%%RESET%
attrib +r "%BACKUP_FILE%"

:: ============================================================
echo.
echo %BLUE%[STEP 5]%WHITE% Staging and committing to git...%RESET%
:: ============================================================
git add . -v

if "%MODE%"=="UPDATE" (
    git commit --amend --no-edit
    git tag -f %PROJECT_VERSION%
) else (
    git commit -m "%MSG%"
    git tag -a %PROJECT_VERSION% -m "%MSG%"
)

:: ============================================================
echo.
echo %BLUE%[STEP 6]%WHITE% Pushing to GitHub...%RESET%
:: ============================================================
git push origin main --force && git push origin %PROJECT_VERSION% --force

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo %RED%!! ERROR: Git push failed !!%RESET%
    pause & exit /b 1
)

:: ============================================================
echo.
echo %BLUE%[STEP 7]%WHITE% Creating GitHub release...%RESET%
:: ============================================================
if "%MODE%"=="RELEASE" (
    gh release create %PROJECT_VERSION% --title "%PROJECT_VERSION%" --notes "%MSG%"
    if %ERRORLEVEL% NEQ 0 (
        echo.
        echo %RED%!! ERROR: GitHub release creation failed !!%RESET%
        pause & exit /b 1
    )
    echo %GREEN%[RELEASE] GitHub release %PROJECT_VERSION% created%RESET%
) else (
    echo  Skipping GitHub release creation - UPDATE mode
)

echo.
echo %GREEN%===========================================%RESET%
echo %GREEN% SUCCESS! %MODE% complete for v%PROJECT_VERSION%%RESET%
echo %GREEN%===========================================%RESET%
pause