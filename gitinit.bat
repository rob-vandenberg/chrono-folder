@echo off
setlocal enabledelayedexpansion

:: -----------------------------------------------------------------------------
:: gitinit.bat -- One-time git + scaffold initialization for a new HA
::                custom INTEGRATION project (HACS category: integration).
:: Run this ONCE, from inside the project root folder.
::
:: Two supported starting states:
::   A) Empty folder            -> gitinit asks for everything, scaffolds all.
::   B) custom_components\<domain> already populated (manifest.json, .py
::      files already written by hand) -> gitinit detects the domain and
::      reads name/version from the existing manifest.json, and only fills
::      in whatever else is still missing. It never overwrites a file that
::      already exists.
::
:: Usage: gitinit.bat [project-identifier]
::   If no argument is given, the current folder name is used instead.
:: -----------------------------------------------------------------------------

if /i "%~1"=="/?" goto :show_readme
if /i "%~1"=="-h" goto :show_readme
if /i "%~1"=="--help" goto :show_readme

set "UPPER_MAP=a=A b=B c=C d=D e=E f=F g=G h=H i=I j=J k=K l=L m=M n=N o=O p=P q=Q r=R s=S t=T u=U v=V w=W x=X y=Y z=Z"

:: --- Step 0: Abort guard - ONLY on signs that gitinit already fully ran ------
set "EXISTING="
if exist "hacs.json"                     set "EXISTING=hacs.json"
if exist ".github\workflows\validate_hassfest_hacs.yml" set "EXISTING=.github\workflows\validate_hassfest_hacs.yml"

if not "%EXISTING%"=="" (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !! ERROR: %EXISTING% already exists.                            !!
    echo !! That means gitinit already ran for this project. Aborting.   !!
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

:: --- Step 1: PROJECT_IDENTIFIER default - always from the root folder name --
if "%~1"=="" (
    for %%F in ("%CD%") do set "STARTPOINT=%%~nxF"
) else (
    set "STARTPOINT=%~1"
)
set "DEFAULT_IDENTIFIER=%STARTPOINT%"
call :TitleCase STARTPOINT DEFAULT_NAME_FROM_FOLDER

:: --- Step 2: Detect whether custom_components\<domain> already exists ------
set "MODE=GREENFIELD"
set "DOMAIN="

if exist "custom_components" (
    set "SUBDIR_COUNT=0"
    set "FOUND_DOMAIN="
    for /d %%D in ("custom_components\*") do (
        set /a SUBDIR_COUNT+=1
        set "FOUND_DOMAIN=%%~nxD"
    )
    if "!SUBDIR_COUNT!"=="0" (
        echo.
        echo !! ERROR: custom_components exists but is empty. gitinit expects   !!
        echo !! exactly one subfolder ^(your integration's domain^) if you've    !!
        echo !! already started writing code. Aborting - nothing was changed.  !!
        pause & exit /b 1
    )
    if not "!SUBDIR_COUNT!"=="1" (
        echo.
        echo !! ERROR: custom_components contains more than one subfolder.     !!
        echo !! gitinit can't guess which one is the integration domain.       !!
        echo !! Aborting - nothing was changed.                                !!
        pause & exit /b 1
    )
    set "DOMAIN=!FOUND_DOMAIN!"
    set "MODE=EXISTING_CODE"
)

:: --- Step 3: If code already exists, validate + read its manifest.json -----
set "MANIFEST_EXISTS=0"
set "PROJECT_NAME_FROM_MANIFEST="

if "%MODE%"=="EXISTING_CODE" (
    if exist "custom_components\%DOMAIN%\manifest.json" (
        set "MANIFEST_EXISTS=1"

        for /f "tokens=2 delims=:," %%A in ('findstr /C:"\"domain\"" "custom_components\%DOMAIN%\manifest.json"') do set "RAW=%%A"
        set "RAW=!RAW:"=!"
        for /f "tokens=* delims= " %%B in ("!RAW!") do set "MANIFEST_DOMAIN=%%B"

        if "!MANIFEST_DOMAIN!"=="" (
            echo.
            echo !! ERROR: could not read "domain" from                            !!
            echo !! custom_components\%DOMAIN%\manifest.json. Aborting.            !!
            pause & exit /b 1
        )

        if not "!MANIFEST_DOMAIN!"=="%DOMAIN%" (
            echo.
            echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            echo !! ERROR: manifest.json domain "!MANIFEST_DOMAIN!" does not match  !!
            echo !! its containing folder name "%DOMAIN%".                         !!
            echo !! Home Assistant REQUIRES these to be identical - the integration !!
            echo !! will not load correctly until this is fixed. Aborting, nothing  !!
            echo !! was changed.                                                    !!
            echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            pause & exit /b 1
        )

        for /f "tokens=2 delims=:," %%A in ('findstr /C:"\"name\"" "custom_components\%DOMAIN%\manifest.json"') do set "RAW=%%A"
        set "RAW=!RAW:"=!"
        for /f "tokens=* delims= " %%B in ("!RAW!") do set "PROJECT_NAME_FROM_MANIFEST=%%B"
    )
)

:: --- Step 4: Prompts - only ask for what isn't already known ---------------
echo.
set /p PROJECT_IDENTIFIER="Project identifier (%DEFAULT_IDENTIFIER%): "
if "%PROJECT_IDENTIFIER%"=="" set "PROJECT_IDENTIFIER=%DEFAULT_IDENTIFIER%"

if "%MODE%"=="GREENFIELD" (
    set "DEFAULT_DOMAIN=%PROJECT_IDENTIFIER:-=_%"
    set /p DOMAIN="Integration domain (%DEFAULT_DOMAIN%): "
    if "%DOMAIN%"=="" set "DOMAIN=%DEFAULT_DOMAIN%"
) else (
    echo  Integration domain: %DOMAIN%   ^(detected from custom_components\%DOMAIN%^)
)

if not "%PROJECT_NAME_FROM_MANIFEST%"=="" (
    set "PROJECT_NAME=%PROJECT_NAME_FROM_MANIFEST%"
    echo  Project name: %PROJECT_NAME%   ^(read from manifest.json^)
) else (
    if "%MODE%"=="EXISTING_CODE" (
        call :TitleCase DOMAIN DEFAULT_NAME
    ) else (
        set "DEFAULT_NAME=%DEFAULT_NAME_FROM_FOLDER%"
    )
    set /p PROJECT_NAME="Project name (%DEFAULT_NAME%): "
    if "%PROJECT_NAME%"=="" set "PROJECT_NAME=%DEFAULT_NAME%"
)

if "%MANIFEST_EXISTS%"=="0" (
    echo.
    echo  Valid iot_class values:
    echo    assumed_state   calculated      cloud_polling
    echo    cloud_push      local_polling   local_push
    set /p IOT_CLASS="IoT class (required, no default): "
    if "%IOT_CLASS%"=="" (
        echo.
        echo !! ERROR: iot_class is required by hassfest. Re-run and provide one. !!
        pause & exit /b 1
    )
)

set "GITHUB_USER=rob-vandenberg"
set "REMOTE_URL=https://github.com/%GITHUB_USER%/%PROJECT_IDENTIFIER%.git"

:: --- Step 5: Confirmation gate - show exactly what will happen -------------
echo.
echo =====================================================================
echo  MODE: %MODE%
if "%MODE%"=="EXISTING_CODE" echo  Existing integration detected at custom_components\%DOMAIN%
echo.
echo  Files:
if "%MANIFEST_EXISTS%"=="1" (echo    manifest.json        - already exists, will skip) else (echo    manifest.json        - will create)
if exist "hacs.json"                          (echo    hacs.json            - already exists, will skip) else (echo    hacs.json            - will create)
if exist "README.md"                          (echo    README.md            - already exists, will skip) else (echo    README.md            - will create)
if exist ".gitignore"                         (echo    .gitignore           - already exists, will skip) else (echo    .gitignore           - will create)
if exist ".gitattributes"                     (echo    .gitattributes       - already exists, will skip) else (echo    .gitattributes       - will create)
if exist ".github\workflows\validate_hassfest_hacs.yml"     (echo    validate_hassfest_hacs.yml         - already exists, will skip) else (echo    validate_hassfest_hacs.yml         - will create)
echo.
echo  Folders ^(created only if missing^):
echo    .github\workflows   art   backup   docs
echo    custom_components\%DOMAIN%\brand
echo.
echo  git init, branch 'main', remote origin: %REMOTE_URL%
echo  Commit and push everything above to GitHub.
echo =====================================================================
echo.
set /p CONFIRM="Continue? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo.
    echo gitinit aborted. No changes were made.
    exit /b 1
)

:: --- Step 6: git init / branch / remote -------------------------------------
echo.
echo [1/5] Initializing local git repository...
git init
if %ERRORLEVEL% NEQ 0 (echo. & echo !! ERROR: git init failed !! & pause & exit /b 1)

echo.
echo [2/5] Creating main branch...
git checkout -b main
if %ERRORLEVEL% NEQ 0 (echo. & echo !! ERROR: Could not create main branch !! & pause & exit /b 1)

echo.
echo [3/5] Adding remote origin...
git remote add origin %REMOTE_URL%
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !! ERROR: Could not add remote origin. Make sure the GitHub repo   !!
    echo !! exists at: %REMOTE_URL%
    pause & exit /b 1
)

:: --- Step 7: Create folder structure (idempotent) ---------------------------
echo.
echo [4/5] Creating folder structure and files...
if not exist ".github\workflows"                mkdir ".github\workflows"
if not exist "art"                              mkdir "art"
if not exist "backup"                           mkdir "backup"
if not exist "custom_components\%DOMAIN%\brand" mkdir "custom_components\%DOMAIN%\brand"
if not exist "docs"                             mkdir "docs"

:: manifest.json
if "%MANIFEST_EXISTS%"=="1" (
    echo  manifest.json already exists - skipping
) else (
    > "custom_components\%DOMAIN%\manifest.json" (
        echo {
        echo   "domain": "%DOMAIN%",
        echo   "name": "%PROJECT_NAME%",
        echo   "codeowners": ["@%GITHUB_USER%"],
        echo   "config_flow": true,
        echo   "documentation": "https://github.com/%GITHUB_USER%/%PROJECT_IDENTIFIER%",
        echo   "iot_class": "%IOT_CLASS%",
        echo   "issue_tracker": "https://github.com/%GITHUB_USER%/%PROJECT_IDENTIFIER%/issues",
        echo   "requirements": [],
        echo   "version": "0.0.0"
        echo }
    )
    echo  Created custom_components\%DOMAIN%\manifest.json
)

:: hacs.json
if exist "hacs.json" (
    echo  hacs.json already exists - skipping
) else (
    > "hacs.json" (
        echo {
        echo   "name": "%PROJECT_NAME%",
        echo   "render_readme": true
        echo }
    )
    echo  Created hacs.json
)

:: README.md
if exist "README.md" (
    echo  README.md already exists - skipping
) else (
    > "README.md" (
        echo # %PROJECT_NAME%
        echo.
        echo ![%PROJECT_NAME%]^(art/header.svg^)
        echo.
        echo TODO: one-line description of what this integration does.
        echo.
        echo ---
        echo.
        echo ## Installation
        echo.
        echo ### HACS ^(recommended^)
        echo.
        echo Add this repository as a custom repository in HACS, then install **%PROJECT_NAME%** from the integrations section.
        echo.
        echo ### Manual
        echo.
        echo Copy `custom_components/%DOMAIN%/` into your Home Assistant `config/custom_components/` folder and restart Home Assistant.
        echo.
        echo ---
        echo.
        echo ## Configuration
        echo.
        echo After installation, go to **Settings -^> Devices ^& Services -^> Add Integration** and search for **%PROJECT_NAME%**.
        echo.
        echo ---
        echo.
        echo ## License
        echo.
        echo MIT
    )
    echo  Created README.md
)

:: .gitignore
if exist ".gitignore" (
    echo  .gitignore already exists - skipping
) else (
    > ".gitignore" (
        echo __pycache__/
        echo *.py[cod]
        echo *.egg-info/
        echo .vscode/
        echo .idea/
        echo .DS_Store
        echo backup/
    )
    echo  Created .gitignore
)

:: .gitattributes
if exist ".gitattributes" (
    echo  .gitattributes already exists - skipping
) else (
    > ".gitattributes" (
        echo * text=auto eol=lf
    )
    echo  Created .gitattributes
)

:: validate_hassfest_hacs.yml - single workflow, sequential steps (hassfest must pass before
:: HACS Action runs - one push triggers exactly one workflow run, not two)
if exist ".github\workflows\validate_hassfest_hacs.yml" (
    echo  validate_hassfest_hacs.yml already exists - skipping
) else (
    > ".github\workflows\validate_hassfest_hacs.yml" (
        echo name: "Validate: hassfest + HACS"
        echo.
        echo on:
        echo   push:
        echo     branches:
        echo       - main
        echo     paths:
        echo       - 'custom_components/**'
        echo       - 'hacs.json'
        echo   workflow_dispatch:
        echo   schedule:
        echo     - cron: "0 0 * * *"
        echo.
        echo jobs:
        echo   validate:
        echo     runs-on: "ubuntu-latest"
        echo     steps:
        echo       - uses: actions/checkout@v6
        echo.
        echo       - name: Validate with hassfest
        echo         uses: home-assistant/actions/hassfest@master
        echo.
        echo       - name: HACS Action
        echo         uses: "hacs/action@main"
        echo         with:
        echo           category: "integration"
    )
    echo  Created .github\workflows\validate_hassfest_hacs.yml
)

:: --- Step 8: Commit and push -------------------------------------------------
echo.
echo [5/5] Committing and pushing...
git add .
git commit -m "Initial project scaffold"
if %ERRORLEVEL% NEQ 0 (echo. & echo !! ERROR: git commit failed !! & pause & exit /b 1)

git push -u origin main
if %ERRORLEVEL% NEQ 0 (echo. & echo !! ERROR: Git push failed !! & pause & exit /b 1)

:: --- Done --------------------------------------------------------------------
echo.
echo =====================================================================
echo  SUCCESS! %PROJECT_NAME% scaffold is ready and pushed to GitHub.
echo =====================================================================
echo.
echo  STILL TO DO BY HAND:
echo    - Copy release.bat in from another integration project
if "%MODE%"=="GREENFIELD" (
    echo    - Write __init__.py, config_flow.py, const.py, and the platform
    echo      file^(s^) inside custom_components\%DOMAIN%\
)
echo    - Add strings.json / translations\en.json for the config flow UI
echo    - Drop a header image into art\ ^(referenced by README.md^)
echo    - Drop icon.png ^(and ideally logo.png^) into
echo      custom_components\%DOMAIN%\brand\
echo    - Add a LICENSE via the GitHub web UI
echo    - Set repository topics on GitHub for HACS searchability:
echo        home-assistant   hacs   integration
echo.
echo  !! WARNING: gitinit.bat is one-time. Do not run it again for this  !!
echo  !!          project once the scaffold exists.                     !!
echo.
pause
exit /b 0


:: -----------------------------------------------------------------------------
:TitleCase
:: %1 = name of input variable (separators - or _), %2 = name of output variable
:: -----------------------------------------------------------------------------
setlocal enabledelayedexpansion
set "INPUT=!%~1!"
set "INPUT=%INPUT:_= %"
set "INPUT=%INPUT:-= %"
set "RESULT="
for %%W in ("%INPUT%") do (
    set "WORD=%%~W"
    set "FIRST=!WORD:~0,1!"
    set "REST=!WORD:~1!"
    for %%M in (%UPPER_MAP%) do (
        for /f "tokens=1,2 delims==" %%a in ("%%M") do (
            if "!FIRST!"=="%%a" set "FIRST=%%b"
        )
    )
    if "!RESULT!"=="" (set "RESULT=!FIRST!!REST!") else (set "RESULT=!RESULT! !FIRST!!REST!")
)
endlocal & set "%~2=%RESULT%"
goto :eof


:: -----------------------------------------------------------------------------
:show_readme
:: -----------------------------------------------------------------------------
echo.
echo =====================================================================
echo   GITINIT -- One-time scaffold + git init for a new HA INTEGRATION
echo =====================================================================
echo.
echo   USAGE:   gitinit [project-identifier]
echo   EXAMPLE: gitinit chrono-folder
echo.
echo   If no argument is given, the current folder name is used as the
echo   default project identifier instead.
echo.
echo -- TWO WAYS TO START -------------------------------------------------
echo.
echo   A) Empty project folder
echo      gitinit asks for project name, identifier, domain, and iot_class,
echo      then scaffolds everything including manifest.json.
echo.
echo   B) You've already created custom_components\^<domain^> and written
echo      manifest.json plus your Python files
echo      gitinit detects the domain from that folder name, verifies the
echo      manifest's "domain" field matches it ^(Home Assistant requires
echo      this - hassfest will fail otherwise^), reads "name" from the
echo      manifest, and only creates whatever else is still missing.
echo.
echo   In both cases, gitinit NEVER overwrites a file that already exists.
echo   It only generates what's missing.
echo.
echo -- BEFORE RUNNING ----------------------------------------------------
echo.
echo   Create the GitHub repository first:
echo     - Go to https://github.com/rob-vandenberg
echo     - Click "New repository", name it EXACTLY like the local folder
echo     - Public, leave ALL checkboxes UNCHECKED on creation
echo.
echo -- WHAT GITINIT DOES NOT DO -------------------------------------------
echo.
echo   - It does not write release.bat - copy that in from another project
echo   - It does not create a LICENSE - add that on GitHub afterward
echo   - It does not create a brand icon - you supply icon.png yourself
echo.
echo -- WARNING ------------------------------------------------------------
echo.
echo   gitinit.bat must only ever be run ONCE per project.
echo.
echo =====================================================================
echo.
pause
exit /b 1
