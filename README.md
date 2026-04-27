<img width="2760" height="1504" alt="Gemini_Generated_Image_tw5sy8tw5sy8tw5s" src="https://github.com/user-attachments/assets/f75d4c2a-148a-453a-8568-4482fce24acd" />

# PSGoat

A PowerShell module providing DNS auditing utilities for Windows DNS Server environments.

## Requirements

- PowerShell 5.1 or higher
- DnsServer module (included in Windows Server RSAT tools)

## Installation

```powershell
Install-Module -Name PSGoat
```

## DNS Functions

### `Get-PSGDnsEntry`

Returns DNS resource records from one or more zones.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all primary zones | Zones to query. Auto-discovered when omitted. |
| `RecordType` | `string[]` | all types | Record types to retrieve: `A`, `AAAA`, `CNAME`, `MX`, `PTR`, `SRV`, `TXT`. |
| `Filter` | `string` | `All` | Restrict to `Static` (manual), `Dynamic` (DDNS), or `All`. |
| `Duplicate` | `switch` | — | Return only hostnames with more than one record of the same type. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# All records from every primary zone
Get-PSGDnsEntry

# Only manually created records
Get-PSGDnsEntry -Filter Static

# Duplicate A/AAAA records in a specific zone
Get-PSGDnsEntry -ZoneName 'contoso.com' -Duplicate

# Remote execution
Get-PSGDnsEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### `Get-PSGDnsOrphanEntry`

Detects orphaned DNS records by cross-referencing forward and reverse zones.

- **MissingPTR** — an A record exists in a forward zone but no matching PTR exists in the corresponding reverse zone.
- **MissingA** — a PTR record exists in a reverse zone but no matching A record exists in the target forward zone.

Reverse zones are always discovered automatically.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all forward zones | Forward zones to inspect. Reverse zones are always auto-discovered. |
| `OrphanType` | `string` | `All` | Filter results: `MissingPTR`, `MissingA`, or `All`. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# All orphaned records
Get-PSGDnsOrphanEntry

# A records with no PTR
Get-PSGDnsOrphanEntry -OrphanType MissingPTR

# PTR records with no A, limited to one forward zone
Get-PSGDnsOrphanEntry -OrphanType MissingA -ZoneName 'contoso.com'

# Remote execution
Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### `Get-PSGDnsBrokenCname`

Detects CNAME records whose alias target cannot be resolved within the managed zones. Only CNAMEs pointing to a hostname inside a managed zone are checked — CNAMEs pointing to external hostnames are silently skipped.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all primary zones | Zones to inspect. Auto-discovered when omitted. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# All broken CNAME records
Get-PSGDnsBrokenCname

# Restricted to one zone
Get-PSGDnsBrokenCname -ZoneName 'contoso.com'

# Remote execution
Get-PSGDnsBrokenCname -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

# Query multiple servers via pipeline
'dc01.contoso.com', 'dc02.contoso.com' | Get-PSGDnsBrokenCname -Credential (Get-Credential)
```

---

## Build

Resolve dependencies (first time only, or after updating `RequiredModules.psd1`):

```powershell
./build.ps1 -ResolveDependency -Tasks noop
```

Build the module:

```powershell
./build.ps1 -Tasks build
```

Run all tests:

```powershell
./build.ps1 -AutoRestore -Tasks test
```

Run the full pipeline (build + test):

```powershell
./build.ps1
```

Run a single test file (requires a prior build):

```powershell
Invoke-Pester -Path ./tests/Unit/Public/Get-PSGDnsEntry.Tests.ps1
```

Run the linter:

```powershell
Invoke-ScriptAnalyzer -Path ./source -Settings ./.vscode/analyzersettings.psd1 -Recurse
```
