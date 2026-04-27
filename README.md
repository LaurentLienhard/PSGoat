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

### `Get-PSGDnsStaleEntry`

Returns dynamic DNS records that have not been refreshed within a given number of days. Static records (no TimeStamp) are always ignored.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all primary zones | Zones to inspect. Auto-discovered when omitted. |
| `RecordType` | `string[]` | `A`, `AAAA` | Record types to evaluate. Accepted values: `A`, `AAAA`. |
| `ThresholdDays` | `int` | `30` | Number of days without refresh after which a record is considered stale. Must be ≥ 1. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# Stale records older than 30 days (default)
Get-PSGDnsStaleEntry

# Custom threshold
Get-PSGDnsStaleEntry -ThresholdDays 60

# Restricted to one zone with a 14-day threshold
Get-PSGDnsStaleEntry -ZoneName 'contoso.com' -ThresholdDays 14

# Remote execution
Get-PSGDnsStaleEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### `Get-PSGDnsDuplicateIp`

Returns IP addresses shared by more than one hostname across the managed DNS zones. Useful for detecting incomplete migrations or IP address conflicts.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all primary zones | Zones to inspect. Auto-discovered when omitted. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# Duplicate IPs across all zones
Get-PSGDnsDuplicateIp

# Restricted to specific zones
Get-PSGDnsDuplicateIp -ZoneName 'contoso.com', 'fabrikam.com'

# Remote execution
Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### `Get-PSGDnsCnameChain`

Returns CNAME chains with a depth equal to or greater than `MinDepth`, and all circular CNAME references regardless of depth. Depth is the number of CNAME hops: a single alias pointing directly to a final record has a depth of 1 (normal); two or more hops before reaching a final record may indicate a misconfiguration.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all primary zones | Zones to inspect. Auto-discovered when omitted. |
| `MinDepth` | `int` | `2` | Minimum number of CNAME hops to report. Must be ≥ 1. Circular chains are always reported. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# CNAME chains with 2 or more hops, and all circular references
Get-PSGDnsCnameChain

# Only chains with 3 or more hops
Get-PSGDnsCnameChain -MinDepth 3

# Restricted to one zone
Get-PSGDnsCnameChain -ZoneName 'contoso.com'

# Remote execution
Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### `Get-PSGDnsZoneStat`

Returns statistics per DNS zone: total records, breakdown by type (A, AAAA, CNAME, MX, PTR, SRV, TXT), static vs dynamic split, and stale record count.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | `string` | local machine | DNS server to query. Accepts pipeline input. |
| `Credential` | `PSCredential` | — | Credentials for remote connection. Creates a CimSession automatically. |
| `ZoneName` | `string[]` | all primary zones | Zones to inspect. Auto-discovered when omitted. |
| `ThresholdDays` | `int` | `30` | Days without refresh after which a dynamic record is counted as stale. Must be ≥ 1. |
| `LogFilePath` | `string` | — | Write OTel-compatible JSON Lines logs to this file (rotated at 10 MB). |

```powershell
# Statistics for all zones
Get-PSGDnsZoneStat

# Quick summary table
Get-PSGDnsZoneStat | Format-Table ZoneName, TotalRecords, StaticCount, DynamicCount, StaleCount

# Custom stale threshold
Get-PSGDnsZoneStat -ThresholdDays 60

# Restricted to one zone
Get-PSGDnsZoneStat -ZoneName 'contoso.com'

# Remote execution
Get-PSGDnsZoneStat -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
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
