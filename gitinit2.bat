@echo off
setlocal enabledelayedexpansion

:: -----------------------------------------------------------------------------
:: gitinit.bat -- One-time git initialization for a new project.
:: Run this ONCE, after all manual preparation steps are complete.
:: Usage: gitinit.bat [project-identifier]
::   If no argument is given, the current folder name is used instead.
:: -----------------------------------------------------------------------------

if /i "%~1"=="/?" goto :show_readme
if /i "%~1"=="-h" goto :show_readme
if /i "%~1"=="--help" goto :show_readme

:: --- Step 0: Abort early if any generated file already exists ----------------
set EXISTING=
if exist "hacs.json"                          set EXISTING=hacs.json
if exist "package.json"                       set EXISTING=package.json
if exist ".github\workflows\build.yml"        set EXISTING=.github\workflows\build.yml
if exist ".github\workflows\publish.yml"      set EXISTING=.github\workflows\publish.yml
if exist ".github\workflows\validate_hacs.yml" set EXISTING=.github\workflows\validate_hacs.yml

if not "%EXISTING%"=="" (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !! ERROR: %EXISTING% already exists.                            !!
    echo !! gitinit.bat generates this file and will not overwrite it.   !!
    echo !! Remove or rename it manually if you really want to proceed.  !!
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

:: --- Step 1: Determine the starting point (argument or folder name) ----------
if "%~1"=="" (
    for %%F in ("%CD%") do set STARTPOINT=%%~nxF
) else (
    set STARTPOINT=%~1
)

:: --- Step 2: Derive default identifier and default display name -------------
set DEFAULT_IDENTIFIER=%STARTPOINT%

set UPPER_MAP=a=A b=B c=C d=D e=E f=F g=G h=H i=I j=J k=K l=L m=M n=N o=O p=P q=Q r=R s=S t=T u=U v=V w=W x=X y=Y z=Z

set DEFAULT_NAME=
for %%W in ("%STARTPOINT:-= %") do (
    set WORD=%%~W
    set FIRST=!WORD:~0,1!
    set REST=!WORD:~1!
    for %%M in (%UPPER_MAP%) do (
        for /f "tokens=1,2 delims==" %%a in ("%%M") do (
            if "!FIRST!"=="%%a" set FIRST=%%b
        )
    )
    if "!DEFAULT_NAME!"=="" (
        set DEFAULT_NAME=!FIRST!!REST!
    ) else (
        set DEFAULT_NAME=!DEFAULT_NAME! !FIRST!!REST!
    )
)

:: --- Step 3: Ask for project name and identifier, defaults pre-filled --------
echo.
set /p PROJECT_NAME="Project name (%DEFAULT_NAME%): "
if "%PROJECT_NAME%"=="" set PROJECT_NAME=%DEFAULT_NAME%

set /p PROJECT_IDENTIFIER="Project identifier (%DEFAULT_IDENTIFIER%): "
if "%PROJECT_IDENTIFIER%"=="" set PROJECT_IDENTIFIER=%DEFAULT_IDENTIFIER%

set GITHUB_USER=rob-vandenberg
set REMOTE_URL=https://github.com/%GITHUB_USER%/%PROJECT_IDENTIFIER%.git

:: --- Step 4: Confirmation gate -------------------------------------------------
echo.
echo =====================================================================
echo  This will:
echo    - Initialize a git repository in this folder
echo    - Create branch 'main'
echo    - Add remote origin: %REMOTE_URL%
echo    - Generate hacs.json and package.json
echo    - Generate .github\workflows\build.yml, publish.yml, validate_hacs.yml
echo    - Commit and push the above to GitHub
echo =====================================================================
echo.
set /p CONFIRM="Continue? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo.
    echo gitinit aborted. No changes were made.
    exit /b 1
)

:: --- Step 5: Initialize local git repository ----------------------------------
echo.
echo [1/6] Initializing local git repository...
git init
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !! ERROR: git init failed              !!
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

:: --- Step 6: Create and switch to main branch ---------------------------------
echo.
echo [2/6] Creating main branch...
git checkout -b main
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !! ERROR: Could not create main branch !!
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

:: --- Step 7: Add remote origin -------------------------------------------------
echo.
echo [3/6] Adding remote origin...
git remote add origin %REMOTE_URL%
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !! ERROR: Could not add remote origin             !!
    echo !!                                                !!
    echo !! Make sure the GitHub repository exists at:    !!
    echo !!   %REMOTE_URL%
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

:: --- Step 8: Generate hacs.json, package.json, and workflow files -------------
echo.
echo [4/6] Generating hacs.json, package.json, and workflow files...

if not exist ".github\workflows" mkdir ".github\workflows"

> "hacs.json" (
    echo {
    echo   "name": "%PROJECT_NAME%",
    echo   "filename": "dist/%PROJECT_IDENTIFIER%.js"
    echo }
)

> "package.json" (
    echo {
    echo   "name": "%PROJECT_IDENTIFIER%",
    echo   "version": "1.0.0",
    echo   "scripts": {
    echo     "build": "terser src/%PROJECT_IDENTIFIER%.js -o dist/%PROJECT_IDENTIFIER%.js --compress --mangle"
    echo   },
    echo   "devDependencies": {
    echo     "terser": "^5.0.0"
    echo   }
    echo }
)

> ".github\workflows\build.yml" (
    echo name: Build
    echo.
    echo on:
    echo   push:
    echo     branches:
    echo       - main
    echo     paths:
    echo       - 'src/*.js'
    echo   workflow_dispatch:
    echo.
    echo env:
    echo   FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
    echo.
    echo permissions:
    echo   contents: write
    echo.
    echo jobs:
    echo   build:
    echo     runs-on: ubuntu-latest
    echo     steps:
    echo       - uses: actions/checkout@v6
    echo.
    echo       - name: Get version
    echo         id: version
    echo         run: echo "version=$(grep -o "CARD_VERSION = '[^']*'" src/%PROJECT_IDENTIFIER%.js ^| sed "s/CARD_VERSION = '//;s/'//")" ^>^> $GITHUB_OUTPUT
    echo.
    echo       - name: Install dependencies
    echo         run: yarn install
    echo.
    echo       - name: Build
    echo         run: yarn build
    echo.
    echo       - name: Commit built file
    echo         uses: EndBug/add-and-commit@v10
    echo         with:
    echo           add: '["dist/%PROJECT_IDENTIFIER%.js"]'
    echo           message: "Auto-build minified JS from source v${{ steps.version.outputs.version }}"
)

> ".github\workflows\publish.yml" (
    echo name: publish-new-version
    echo on:
    echo   workflow_dispatch:
    echo     inputs:
    echo       version:
    echo         description: "Version being published"
    echo         required: true
    echo.
    echo env:
    echo   FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
    echo.
    echo permissions:
    echo   contents: write
    echo.
    echo jobs:
    echo   publish:
    echo     runs-on: ubuntu-latest
    echo     steps:
    echo       - uses: actions/checkout@v6
    echo       - name: Validate version format
    echo         run: echo "${{ github.event.inputs.version }}" ^| grep -E "^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$"
    echo       - name: Install dependencies
    echo         run: yarn install
    echo       - name: Build
    echo         run: yarn build
    echo       - name: Commit and push
    echo         uses: EndBug/add-and-commit@v10
    echo         with:
    echo           add: '["dist/%PROJECT_IDENTIFIER%.js"]'
    echo           message: "Publishing version ${{ github.event.inputs.version }}"
    echo           tag: "v${{ github.event.inputs.version }}"
    echo           tag_push: '--force'
    echo       - name: Publish Github release
    echo         uses: ncipollo/release-action@v1
    echo         with:
    echo           tag: "v${{ github.event.inputs.version }}"
    echo           name: "v${{ github.event.inputs.version }}"
    echo           body: "Published by Rob Vandenberg"
    echo           makeLatest: true
    echo           allowUpdates: true
    echo           artifacts: "dist/*.js"
)

> ".github\workflows\validate_hacs.yml" (
    echo name: HACS Action
    echo.
    echo on:
    echo   workflow_run:
    echo     workflows: ["Build"]
    echo     types:
    echo       - completed
    echo   schedule:
    echo     - cron: "0 0 * * *"
    echo.
    echo jobs:
    echo   hacs:
    echo     name: HACS Action
    echo     runs-on: "ubuntu-latest"
    echo     steps:
    echo       - name: HACS Action
    echo         uses: "hacs/action@main"
    echo         with:
    echo           category: "plugin"
)

echo  Generated hacs.json, package.json, and 3 workflow files.

:: --- Step 9: Stage, commit, and push the generated files -----------------------
echo.
echo [5/6] Committing generated files...
git add ".github/workflows" "hacs.json" "package.json"
git commit -m "Add GitHub Actions workflow files and HACS/package metadata"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !! ERROR: git commit failed                       !!
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

echo.
echo [6/6] Pushing to GitHub...
git push -u origin main
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo !!      ERROR: Git Push failed        !!
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    exit /b 1
)

:: --- Done ------------------------------------------------------------------------
echo.
echo =====================================================================
echo  SUCCESS! Local git repository initialized and connected to GitHub.
echo  Workflow files and metadata have already been pushed, so the Build
echo  workflow will trigger correctly on your very first release.bat run.
echo =====================================================================
echo.
echo  !! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo  !!                                                                !!
echo  !!   DO NOT RUN GITINIT AGAIN FOR THIS PROJECT.                  !!
echo  !!   It is a one-time initialization script. Running it again    !!
echo  !!   will cause errors.                                           !!
echo  !!                                                                !!
echo  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo.
echo  You can now run release.bat for the first time to add, commit
echo  and push the first release.
echo.
echo  release.bat "Your first commit message"
echo.
echo  !! REMINDER !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo  !!                                                                !!
echo  !!   Set GitHub repository topics, or HACS validation will fail. !!
echo  !!                                                                !!
echo  !!   Go to: https://github.com/rob-vandenberg/%PROJECT_IDENTIFIER%
echo  !!   Click the gear icon next to "About" and add these topics:   !!
echo  !!     home-assistant                                             !!
echo  !!     lovelace                                                   !!
echo  !!     hacs                                                       !!
echo  !!                                                                !!
echo  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo.
pause
exit /b 0


:: -----------------------------------------------------------------------------
:show_readme
:: -----------------------------------------------------------------------------
echo.
echo =====================================================================
echo   GITINIT -- One-time git repository initialization for new projects
echo =====================================================================
echo.
echo   USAGE:   gitinit [project-identifier]
echo   EXAMPLE: gitinit chrono-grid-card
echo.
echo   If no argument is given, the current folder name is used as the
echo   default project identifier instead.
echo.
echo   Run this script ONCE per project. All of the following steps
echo   must be completed BEFORE running gitinit.
echo.
echo -- PREPARATION STEPS (do these manually first) ----------------------
echo.
echo   STEP 1 - Create the project folder on your local PC
echo.
echo     Example: C:\Home Assistant\chrono-grid-card
echo.
echo   STEP 2 - Create the required subfolders inside the project folder
echo.
echo     src                 -- contains the main source file
echo     dist                -- empty locally, holds minified JS on GitHub
echo     art                 -- screenshots, SVGs and other artwork
echo     backup              -- local backups of earlier versions
echo.
echo   STEP 3 - Populate the project folder with all required files
echo.
echo     .gitignore
echo     .gitattributes
echo     README.md            -- must contain at least one image,
echo                            otherwise GitHub will complain on
echo                            the first build
echo     release.bat
echo     src\^<your-source-file^>.js
echo.
echo   gitinit.bat itself will generate hacs.json, package.json, and
echo   .github\workflows\build.yml / publish.yml / validate_hacs.yml --
echo   do NOT create these manually.
echo.
echo   STEP 4 - Create the GitHub repository
echo.
echo     - Go to https://github.com/rob-vandenberg
echo     - Click "New repository"
echo     - Name it EXACTLY the same as your local project folder
echo     - Set visibility to Public (required for HACS distribution)
echo     - Leave ALL checkboxes UNCHECKED -- do NOT initialize with
echo       a README, .gitignore or license. Your local folder already
echo       has all of these. Initializing on GitHub would cause a
echo       conflict on the first push.
echo     - Click "Create repository"
echo.
echo == AFTER ALL STEPS ABOVE ARE DONE ==================================
echo.
echo   Run gitinit from INSIDE your project folder:
echo.
echo     cd "C:\Home Assistant\your-project-name"
echo     gitinit your-project-name
echo.
echo   gitinit will then ask you to confirm a project name and
echo   identifier (with sensible defaults pre-filled), show a summary
echo   of what it is about to do, and -- after your confirmation --:
echo     1. Run git init
echo     2. Create the main branch
echo     3. Connect your local repo to GitHub
echo     4. Generate hacs.json, package.json, and the workflow files
echo     5. Commit and push all of the above
echo.
echo -- WARNING ----------------------------------------------------------
echo.
echo   gitinit.bat must only ever be run ONCE per project.
echo   Do not run it again after the first time.
echo.
echo -- FINALLY ----------------------------------------------------------
echo.
echo   After gitinit completes, run release.bat to make your first
echo   commit and push it to GitHub.
echo.
echo =====================================================================
echo.
pause
exit /b 1
