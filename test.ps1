
. "$PSScriptRoot/source/Private/Remove-GPOComputerAce.ps1"
. "$PSScriptRoot/source/Public/Sync-ZephyrToGPOFilteringSDDL.ps1"

# Exemple d'utilisation : vide le filtrage et ajoute au maximum 100 ordinateurs
Sync-ZephyrToGPOFilteringSDDL -MaxComputers 100 -Verbose
