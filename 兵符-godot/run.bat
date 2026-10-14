@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem ===== Bingfu - dev script =====
rem   run.bat           run the game (GUI)
rem   run.bat edit      open the Godot editor
rem   run.bat test      engine tests
rem   run.bat ui        UI smoke test
rem   run.bat guard     architecture guard (the three iron laws)
rem   run.bat selfplay  AI-vs-AI, checks games can actually finish
rem   run.bat shot      render one frame to _shot.png (opens a window)
rem   run.bat all       run every suite
rem
rem If Godot lives somewhere else, change the GODOT line below.
rem This file is ASCII-only and must keep CRLF line endings:
rem cmd.exe mis-parses LF-only .bat files.

set "GODOT=D:\Game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

rem %~dp0 always ends with a backslash. Leaving it on would turn the closing
rem quote of "%PROJ%" into an escaped \" and swallow the rest of the command
rem line -- so strip it.
set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"

if not exist "%GODOT%" (
	echo [ERROR] Godot not found: %GODOT%
	echo         Edit the GODOT path at the top of run.bat
	exit /b 1
)

rem Godot returns 0 even when it aborts on a bad --path, so guard against
rem "silent success" by checking the project file is really there.
if not exist "%PROJ%\project.godot" (
	echo [ERROR] project.godot not found in: %PROJ%
	exit /b 1
)

set "MODE=%~1"
if "%MODE%"=="" set "MODE=game"

if /i "%MODE%"=="game" (
	"%GODOT%" --path "%PROJ%"
	exit /b !errorlevel!
)

if /i "%MODE%"=="edit" (
	"%GODOT%" --path "%PROJ%" -e
	exit /b !errorlevel!
)

if /i "%MODE%"=="test" (
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/TestRunner.gd
	exit /b !errorlevel!
)

if /i "%MODE%"=="ui" (
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/UiSmoke.gd
	exit /b !errorlevel!
)

if /i "%MODE%"=="guard" (
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/ArchGuard.gd
	exit /b !errorlevel!
)

if /i "%MODE%"=="selfplay" (
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/SelfPlay.gd
	exit /b !errorlevel!
)

if /i "%MODE%"=="shot" (
	rem 开真窗口渲一帧存图。改过 BoardView / Main 的布局后跑一次。
	"%GODOT%" --path "%PROJ%" --script res://tests/Screenshot.gd
	exit /b !errorlevel!
)

if /i "%MODE%"=="all" (
	rem Run every suite even if an earlier one fails, so one run shows all
	rem breakage instead of only the first.
	set "RC=0"
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/TestRunner.gd
	if not "!errorlevel!"=="0" set "RC=1"
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/UiSmoke.gd
	if not "!errorlevel!"=="0" set "RC=1"
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/ArchGuard.gd
	if not "!errorlevel!"=="0" set "RC=1"
	"%GODOT%" --headless --path "%PROJ%" --script res://tests/SelfPlay.gd
	if not "!errorlevel!"=="0" set "RC=1"
	if not "!RC!"=="0" (
		echo [FAIL] some suite failed
		exit /b 1
	)
	echo [OK] all tests passed
	exit /b 0
)

echo usage: run.bat [game^|edit^|test^|ui^|guard^|selfplay^|shot^|all]
exit /b 1