<img width="2760" height="1504" alt="Gemini_Generated_Image_tw5sy8tw5sy8tw5s" src="https://github.com/user-attachments/assets/f75d4c2a-148a-453a-8568-4482fce24acd" />

# PSGoat

A PowerShell module providing Windows system administration utilities: DNS auditing, DHCP monitoring, and more.

## Requirements

- PowerShell 5.1 or higher
- DnsServer module (included in Windows Server RSAT tools) — for DNS functions
- DhcpServer module (included in Windows Server RSAT tools) — for DHCP functions

## Installation

```powershell
Install-Module -Name PSGoat
```

## DHCP Functions

| Function | Description |
|----------|-------------|
| [`Get-PSGDhcpScopeUtilization`](#get-psgdhcpscopeutilization) | Returns utilization statistics per DHCPv4 scope: addresses in use, reserved, free, and percentage consumed. |

---

### Get-PSGDhcpScopeUtilization

Returns per-scope utilization data from a Windows DHCP server. Both active leases and reservations are counted as consumed capacity. Use `-Threshold` to surface only scopes at risk of exhaustion.

```powershell
# All scopes on the local DHCP server
Get-PSGDhcpScopeUtilization

# Only scopes at 80% utilization or above
Get-PSGDhcpScopeUtilization -Threshold 80

# Specific scopes on a remote server
Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com' -Credential (Get-Credential) -Threshold 80

# Two servers, formatted as a table
'dhcp01.contoso.com', 'dhcp02.contoso.com' | Get-PSGDhcpScopeUtilization -Threshold 80 |
    Format-Table ScopeId, Name, TotalAddresses, InUse, Free, UtilizationPercent
```

---

## DNS Functions

| Function | Description |
|----------|-------------|
| [`Get-PSGDnsEntry`](#get-psgdnsentry) | Returns DNS resource records with optional static/dynamic and duplicate filtering. |
| [`Get-PSGDnsOrphanEntry`](#get-psgdnsorphanentry) | Detects A records without a matching PTR, and PTR records without a matching A. |
| [`Get-PSGDnsBrokenCname`](#get-psgdnsbrokencname) | Detects CNAME records whose target has no A, AAAA or CNAME in the managed zones. |
| [`Get-PSGDnsStaleEntry`](#get-psgdnsstaleentry) | Returns dynamic records not refreshed within a given number of days. |
| [`Get-PSGDnsDuplicateIp`](#get-psgdnsduplicateip) | Returns IP addresses shared by more than one hostname across the managed zones. |
| [`Get-PSGDnsCnameChain`](#get-psgdnscnamechain) | Detects long CNAME chains and circular CNAME references. |
| [`Get-PSGDnsZoneStat`](#get-psgdnszonestat) | Returns per-zone statistics: record counts by type, static/dynamic split, stale count. |
| [`Get-PSGDnsForwardReverseMismatch`](#get-psgdnsforwardreversemismatch) | Detects A records whose PTR record exists but points to a different FQDN. |

---

### Get-PSGDnsEntry

Returns DNS resource records from one or more zones. Supports filtering by record origin (`Static` / `Dynamic`) and duplicate detection.

```powershell
# All records from every primary zone
Get-PSGDnsEntry

# Only manually created (static) records in a specific zone
Get-PSGDnsEntry -ZoneName 'contoso.com' -Filter Static

# Hostnames with duplicate records of the same type
Get-PSGDnsEntry -Duplicate

# Remote execution with credentials
Get-PSGDnsEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### Get-PSGDnsOrphanEntry

Detects orphaned DNS records by cross-referencing forward and reverse zones. Reverse zones are always discovered automatically.

- **MissingPTR** — an A record exists but no corresponding PTR.
- **MissingA** — a PTR record exists but no corresponding A.

```powershell
# All orphaned records (MissingPTR + MissingA)
Get-PSGDnsOrphanEntry

# Only A records with no PTR, with verbose progress
Get-PSGDnsOrphanEntry -OrphanType MissingPTR -Verbose
```

---

### Get-PSGDnsBrokenCname

Detects CNAME records whose alias target cannot be resolved within the managed zones. CNAMEs pointing to external hostnames are silently skipped.

```powershell
# All broken CNAMEs across every primary zone
Get-PSGDnsBrokenCname

# Restricted to one zone, remote execution
Get-PSGDnsBrokenCname -ZoneName 'contoso.com' -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
```

---

### Get-PSGDnsStaleEntry

Returns dynamic (DDNS) records whose `TimeStamp` has not been refreshed within the specified number of days. Static records are always ignored.

```powershell
# Records not refreshed in the last 30 days (default)
Get-PSGDnsStaleEntry

# Custom threshold, restricted to one zone
Get-PSGDnsStaleEntry -ZoneName 'contoso.com' -ThresholdDays 60
```

---

### Get-PSGDnsDuplicateIp

Returns IP addresses assigned to more than one hostname across the managed zones. Useful for detecting incomplete migrations or IP conflicts.

```powershell
# Duplicate IPs across all zones
Get-PSGDnsDuplicateIp

# Across two specific zones
Get-PSGDnsDuplicateIp -ZoneName 'contoso.com', 'fabrikam.com'
```

---

### Get-PSGDnsCnameChain

Detects CNAME chains with two or more hops (configurable via `-MinDepth`) and all circular references, regardless of depth.

```powershell
# Chains with 2+ hops and all circular references (default)
Get-PSGDnsCnameChain

# Only circular references (set MinDepth higher than realistic chain length)
Get-PSGDnsCnameChain | Where-Object IsCircular
```

---

### Get-PSGDnsZoneStat

Returns a statistics summary per zone: total records, breakdown by type, static vs dynamic split, and stale record count.

```powershell
# Statistics for all zones as a table
Get-PSGDnsZoneStat | Format-Table ZoneName, TotalRecords, StaticCount, DynamicCount, StaleCount

# Breakdown by record type for a specific zone
(Get-PSGDnsZoneStat -ZoneName 'contoso.com').ByType
```

---

### Get-PSGDnsForwardReverseMismatch

Detects A records where a PTR record exists for the same IP but points to a different FQDN. Records without any PTR are intentionally skipped — use `Get-PSGDnsOrphanEntry` for those.

Typical causes: server renames, IP reassignments, or incomplete migrations where the reverse zone was not updated.

```powershell
# All forward/reverse mismatches across every primary zone
Get-PSGDnsForwardReverseMismatch

# Restricted to one forward zone
Get-PSGDnsForwardReverseMismatch -ZoneName 'contoso.com'

# Remote execution with credentials
Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)
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
