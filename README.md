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
| `Get-PSGDnsEntry` | Returns DNS resource records from one or more zones. Accepts a `-Filter` parameter (`All`, `Static`, `Dynamic`) to restrict results to manually created or DDNS-registered entries, and a `-Duplicate` switch to return only entries where the same hostname has more than one record of the same type. Supports local and remote execution via `ComputerName`. |

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
