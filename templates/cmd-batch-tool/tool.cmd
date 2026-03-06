@echo off
setlocal enabledelayedexpansion

if /I "%~1"=="--check" (
  echo {{project_name}} check ok
  exit /b 0
)

echo Running {{project_name}}
if exist config\settings.ini (
  for /f "tokens=1,* delims==" %%A in (config\settings.ini) do (
    if /I "%%A"=="name" set TOOL_NAME=%%B
  )
)
if defined TOOL_NAME (
  echo Name: !TOOL_NAME!
)
call lib\helpers.cmd :status
exit /b 0
