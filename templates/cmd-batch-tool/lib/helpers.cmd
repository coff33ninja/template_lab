@echo off
if /I "%~1"==":status" (
  echo Status: ok
  exit /b 0
)
exit /b 0
