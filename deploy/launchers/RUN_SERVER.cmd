@echo off
rem Rope Racers dedicated server (Windows). Usage: RUN_SERVER.cmd [port]
set PORT=%1
if "%PORT%"=="" set PORT=7777
"%~dp0RopeRacers.exe" --headless -- --server --port %PORT%
