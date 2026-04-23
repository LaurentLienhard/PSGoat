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
