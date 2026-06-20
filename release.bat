@echo off
setlocal enabledelayedexpansion

:: ANSI color codes (requires Windows 10 1511+)
for /f %%A in ('echo prompt $E ^| cmd') do set "ESC=%%A"
set "RESET=%ESC%[0m"
set "WHITE=%ESC%[97m"
set "BLUE=%ESC%[94m"
set "GREEN=%ESC%[92m"
set "RED=%ESC%[91m"

:: -----------------------------------------------------------------------------
:: release.bat -- UNIVERSAL release script for HA custom INTEGRATIONS.
:: Nothing in this file is project-specific - the domain is auto-detected
:: from custom_components\<domain>, so this file can be copied as-is into
:: any integration project without editing a single line.
:: -----------------------------------------------------------------------------

:: ============================================================
echo.
echo %BLUE%[STEP 1]%WHITE% Detecting integration domain...%RESET%
:: ============================================================
if not exist "custom_components" (
    echo %RED%!! ERROR: custom_components folder not found. Run this from the project root. !!%RESET%
    pause & exit /b 1
)

set "SUBDIR_COUNT=0"
set "DOMAIN="
for /d %%D in ("custom_components\*") do (
    set /a SUBDIR_COUNT+=1
    set "DOMAIN=%%~nxD"
)

if "%SUBDIR_COUNT%"=="0" (
    echo %RED%!! ERROR: custom_components contains no subfolder - nothing to release. !!%RESET%
    pause & exit /b 1
)
if not "%SUBDIR_COUNT%"=="1" (
    echo %RED%!! ERROR: custom_components contains more than one subfolder - ambiguous. !!%RESET%
    pause & exit /b 1
)
echo  DOMAIN: %DOMAIN%

:: ============================================================
echo.
echo %BLUE%[STEP 2]%WHITE% Validating manifest.json domain matches folder name...%RESET%
:: ============================================================
for /f "tokens=2 delims=:, " %%A in ('findstr /C:"\"domain\"" "custom_components\%DOMAIN%\manifest.json"') do set "RAW_DOMAIN=%%A"
set "MANIFEST_DOMAIN=%RAW_DOMAIN:"=%"

if "%MANIFEST_DOMAIN%"=="" (
    echo %RED%!! ERROR: could not read "domain" from custom_components\%DOMAIN%\manifest.json !!%RESET%
    pause & exit /b 1
)
if not "%MANIFEST_DOMAIN%"=="%DOMAIN%" (
    echo.
    echo %RED%!! ERROR: manifest.json domain "%MANIFEST_DOMAIN%" does not match its     !!%RESET%
    echo %RED%!! containing folder name "%DOMAIN%". Home Assistant requires these to   !!%RESET%
    echo %RED%!! be identical - the integration will not load correctly. Aborting.     !!%RESET%
    pause & exit /b 1
)
echo  OK - manifest.json domain matches folder name

:: ============================================================
echo.
echo %BLUE%[STEP 3]%WHITE% Extracting version from manifest.json...%RESET%
:: ============================================================
for /f "tokens=2 delims=:, " %%A in ('findstr /C:"\"version\"" "custom_components\%DOMAIN%\manifest.json"') do set "RAW_VERSION=%%A"
set "INTEGRATION_VERSION=%RAW_VERSION:"=%"

if "%INTEGRATION_VERSION%"=="" (
    echo %RED%!! ERROR: Could not find version in custom_components\%DOMAIN%\manifest.json !!%RESET%
    pause & exit /b 1
)
echo  INTEGRATION_VERSION: %INTEGRATION_VERSION%

:: Git tags and GitHub releases use a "v" prefix, matching the plugin
:: workflow's convention. manifest.json itself stays unprefixed - HA
:: doesn't want a "v" in there.
set "TAG_VERSION=v%INTEGRATION_VERSION%"

:: ============================================================
echo.
echo %BLUE%[STEP 4]%WHITE% Determining release mode...%RESET%
:: ============================================================
git rev-parse "%TAG_VERSION%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set MODE=UPDATE
) else (
    set MODE=RELEASE
)
echo  MODE: %MODE%

:: ============================================================
echo.
echo %BLUE%[STEP 5]%WHITE% Validating commit message...%RESET%
:: ============================================================
set MSG=%~1

if "%MODE%"=="RELEASE" (
    if "%MSG%"=="" (
        echo.
        echo %RED%!! ERROR: A comment is REQUIRED for a new release. !!%RESET%
        echo %RED%!! Usage: release.bat "Your commit message"        !!%RESET%
        pause & exit /b 1
    )
    echo  MESSAGE: %MSG%
) else (
    echo  MESSAGE: N/A - UPDATE mode
)

:: ============================================================
echo.
echo %BLUE%[STEP 6]%WHITE% Creating backup zip...%RESET%
:: ============================================================
set BACKUP_FILE=backup\%DOMAIN%_%INTEGRATION_VERSION%.zip

if exist "%BACKUP_FILE%" (
    attrib -r "%BACKUP_FILE%"
    del /f "%BACKUP_FILE%"
)

if not exist backup mkdir backup

"C:\Program Files\7-Zip\7z.exe" a "%BACKUP_FILE%" "custom_components\%DOMAIN%\*" -r >nul
if %ERRORLEVEL% NEQ 0 (
    echo %RED%!! ERROR: Backup zip failed. Check 7-Zip installation. !!%RESET%
    pause & exit /b 1
)
echo %GREEN%[BACKUP] %BACKUP_FILE%%RESET%
attrib +r "%BACKUP_FILE%"

:: ============================================================
echo.
echo %BLUE%[STEP 7]%WHITE% Staging and committing to git...%RESET%
:: ============================================================
git add . -v

if "%MODE%"=="UPDATE" (
    git commit --amend --no-edit
    git tag -f %TAG_VERSION%
) else (
    git commit -m "%MSG%"
    git tag -a %TAG_VERSION% -m "%MSG%"
)

:: ============================================================
echo.
echo %BLUE%[STEP 8]%WHITE% Pushing to GitHub...%RESET%
:: ============================================================
git push origin main --force && git push origin %TAG_VERSION% --force

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo %RED%!! ERROR: Git push failed !!%RESET%
    pause & exit /b 1
)

:: ============================================================
echo.
echo %BLUE%[STEP 9]%WHITE% Creating GitHub release...%RESET%
:: ============================================================
if "%MODE%"=="RELEASE" (
    gh release create %TAG_VERSION% --title "%TAG_VERSION%" --notes "%MSG%"
    if %ERRORLEVEL% NEQ 0 (
        echo.
        echo %RED%!! ERROR: GitHub release creation failed !!%RESET%
        pause & exit /b 1
    )
    echo %GREEN%[RELEASE] GitHub release %TAG_VERSION% created%RESET%
) else (
    echo  Skipping GitHub release creation - UPDATE mode
)

echo.
echo %GREEN%===========================================%RESET%
echo %GREEN% SUCCESS! %MODE% complete for %TAG_VERSION%%RESET%
echo %GREEN%===========================================%RESET%
pause
