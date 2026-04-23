<img width="2760" height="1504" alt="Gemini_Generated_Image_tw5sy8tw5sy8tw5s" src="https://github.com/user-attachments/assets/f75d4c2a-148a-453a-8568-4482fce24acd" />

# PSGoat

A PowerShell module with a collection of utility functions.

## Requirements

- PowerShell 5.0 or higher

## Installation

```powershell
Install-Module -Name PSGoat
```

## Public Functions

| Function | Synopsis |
|----------|----------|
| `Get-Something` | Returns the input string passed via the `-Data` parameter. |

## Build

Resolve dependencies (first time only):

```powershell
./build.ps1 -ResolveDependency -Tasks noop
```

Build the module:

```powershell
./build.ps1 -Tasks build
```

Run tests:

```powershell
./build.ps1 -AutoRestore -Tasks test
```
