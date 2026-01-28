@echo off
REM Find Boomi Custom Scripts (Windows Batch Launcher)
REM This batch file launches the PowerShell script
REM
REM Detects: Groovy 1.5, Groovy 2.4, JavaScript
REM
REM Usage:
REM   find-boomi-custom-scripts.bat <processes_folder>
REM
REM Example:
REM   find-boomi-custom-scripts.bat C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes

PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0find-boomi-custom-scripts.ps1" %*
