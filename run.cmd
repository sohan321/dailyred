@echo off
rem Daily Red from cmd or PowerShell: runs scripts/run.sh in Git Bash (set up,
rem fetch, build, serve). Usage: run           (http://localhost:8080)
rem                              run 3000      (another port)
setlocal
set "BASH="
for %%G in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LocalAppData%\Programs\Git\bin\bash.exe") do (
  if not defined BASH if exist "%%~G" set "BASH=%%~G"
)
if not defined BASH (
  rem Fall back to git.exe on PATH: bash.exe lives in ..\bin next to its cmd\ folder.
  for /f "delims=" %%G in ('where git 2^>nul') do (
    if not defined BASH if exist "%%~dpG..\bin\bash.exe" set "BASH=%%~dpG..\bin\bash.exe"
  )
)
if not defined BASH (
  echo Git Bash not found. Install Git for Windows: https://git-scm.com/download/win
  exit /b 1
)
"%BASH%" "%~dp0scripts/run.sh" %*
