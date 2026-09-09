@echo off
rem ===== Potion Workshop - game launcher =====
rem The Godot engine is kept in ..\GodotEngine so that double-clicking the
rem engine .exe opens the Project Manager instead of running this game.
start "" "%~dp0..\GodotEngine\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
