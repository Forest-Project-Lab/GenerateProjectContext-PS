# Makefile for setting up the GenerateProjectContext tool on Windows

# --- Configuration ---
INSTALL_DIR := $(USERPROFILE)\MyPowerShellScripts\GenerateProjectContext
PS_SCRIPT_NAME := GenerateProjectContext.ps1
BAT_SCRIPT_NAME := gpc.bat

# --- Targets ---

default: help

setup: create_install_dir copy_scripts add_to_path ## Install scripts and add the install directory to user Path environment variable

uninstall: remove_from_path ## Remove the install directory from user Path environment variable (doesn't delete files)

help:
	@echo Usage:
	@echo   make setup      - Installs the scripts and configures the Path environment variable.
	@echo   make uninstall  - Removes the script directory from the Path environment variable.
	@echo   make help       - Shows this help message.
	@echo.
	@echo Note: You need 'make' installed (e.g., via Chocolatey: choco install make).
	@echo       You might need to restart your terminal/system for Path changes to take effect.

create_install_dir:
	@echo Creating installation directory: $(INSTALL_DIR)
	@powershell -Command "if (-not (Test-Path -Path '$(INSTALL_DIR)' -PathType Container)) { New-Item -Path '$(INSTALL_DIR)' -ItemType Directory -Force | Out-Null }"
	@echo Directory created or already exists.

copy_scripts:
	@echo Copying scripts to $(INSTALL_DIR)...
	@powershell -Command "Copy-Item -Path '.\$(PS_SCRIPT_NAME)' -Destination '$(INSTALL_DIR)' -Force"
	@powershell -Command "Copy-Item -Path '.\$(BAT_SCRIPT_NAME)' -Destination '$(INSTALL_DIR)' -Force"
	@echo Scripts copied.

# [修正] PowerShell 変数参照 ($) を $$ にエスケープ
add_to_path:
	@echo Adding $(INSTALL_DIR) to user Path environment variable...
	@powershell -Command "& { \
		Write-Host 'Current user Path:'; \
		$$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User'); \
		Write-Host $$currentPath; \
		$$installDir = '$(INSTALL_DIR)'; \
		if (($$currentPath -split ';') -notcontains $$installDir) { \
			Write-Host ('Adding ' + $$installDir + ' to Path...'); \
			$$newPath = $$currentPath + ';' + $$installDir; \
			$$newPath = $$newPath -replace ';{2,}', ';' -replace '^;|;$$', ''; \
			[Environment]::SetEnvironmentVariable('Path', $$newPath, 'User'); \
			Write-Host 'Path updated successfully. Please restart your terminal for changes to take effect.'; \
		} else { \
			Write-Host ($$installDir + ' is already in the user Path.'); \
		} \
	}"

# [修正] PowerShell 変数参照 ($) を $$ にエスケープ
remove_from_path:
	@echo Removing $(INSTALL_DIR) from user Path environment variable...
	@powershell -Command "& { \
		Write-Host 'Current user Path:'; \
		$$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User'); \
		Write-Host $$currentPath; \
		$$installDir = '$(INSTALL_DIR)'; \
		if (($$currentPath -split ';') -contains $$installDir) { \
			Write-Host ('Removing ' + $$installDir + ' from Path...'); \
			$$pathArray = $$currentPath -split ';'; \
			$$newPathArray = $$pathArray | Where-Object { $$_ -ne $$installDir -and $$_ -ne '' }; \
			$$newPath = $$newPathArray -join ';'; \
			[Environment]::SetEnvironmentVariable('Path', $$newPath, 'User'); \
			Write-Host 'Path updated successfully. Please restart your terminal if needed.'; \
		} else { \
			Write-Host ($$installDir + ' was not found in the user Path.'); \
		} \
	}"

.PHONY: default setup uninstall help create_install_dir copy_scripts add_to_path remove_from_path