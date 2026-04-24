BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsEntry' {
    Context 'Default constructor' {
        It 'Should create an empty instance without throwing' {
            InModuleScope $script:moduleName {
                { [PSGDnsEntry]::new() } | Should -Not -Throw
            }
        }
    }

    Context 'Parameterized constructor' {
        It 'Should set HostName correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10'), $true, [datetime]::MinValue)
                $entry.HostName | Should -Be 'server01'
            }
        }

        It 'Should set ZoneName correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10'), $true, [datetime]::MinValue)
                $entry.ZoneName | Should -Be 'contoso.com'
            }
        }

        It 'Should set RecordType correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10'), $true, [datetime]::MinValue)
                $entry.RecordType | Should -Be 'A'
            }
        }

        It 'Should set RecordData correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'), $true, [datetime]::MinValue)
                $entry.RecordData | Should -HaveCount 2
                $entry.RecordData[0] | Should -Be '192.168.1.10'
                $entry.RecordData[1] | Should -Be '192.168.1.11'
            }
        }

        It 'Should compute Count from RecordData length' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'), $true, [datetime]::MinValue)
                $entry.Count | Should -Be 2
            }
        }

        It 'Should set IsStatic correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10'), $true, [datetime]::MinValue)
                $entry.IsStatic | Should -BeTrue
            }
        }

        It 'Should set TimeStamp correctly' {
            InModuleScope $script:moduleName {
                $ts = [datetime]'2025-01-15 10:00:00'
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10'), $false, $ts)
                $entry.TimeStamp | Should -Be $ts
            }
        }
    }

    Context 'IsStaticRecord static method' {
        It 'Should return true when TimeStamp is MinValue' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{ TimeStamp = [datetime]::MinValue }
                [PSGDnsEntry]::IsStaticRecord($record) | Should -BeTrue
            }
        }

        It 'Should return true when TimeStamp is null' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{ TimeStamp = $null }
                [PSGDnsEntry]::IsStaticRecord($record) | Should -BeTrue
            }
        }

        It 'Should return false when TimeStamp has an actual value' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{ TimeStamp = [datetime]'2025-01-15 10:00:00' }
                [PSGDnsEntry]::IsStaticRecord($record) | Should -BeFalse
            }
        }
    }

    Context 'GetEntries static method - Filter' {
        BeforeAll {
            $script:staticRecord = [PSCustomObject]@{
                HostName   = 'server01'
                RecordType = 'A'
                TimeStamp  = [datetime]::MinValue
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
            }

            $script:dynamicRecord = [PSCustomObject]@{
                HostName   = 'workstation01'
                RecordType = 'A'
                TimeStamp  = [datetime]'2025-01-15 10:00:00'
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.50') }
            }
        }

        It 'Should return both records when Filter is All' {
            InModuleScope $script:moduleName -Parameters @{ SR = $script:staticRecord; DR = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($SR, $DR) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $false, $null)
                $result | Should -HaveCount 2
            }
        }

        It 'Should return only static records when Filter is Static' {
            InModuleScope $script:moduleName -Parameters @{ SR = $script:staticRecord; DR = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($SR, $DR) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Static', $false, $null)
                $result | Should -HaveCount 1
                $result[0].HostName | Should -Be 'server01'
                $result[0].IsStatic | Should -BeTrue
            }
        }

        It 'Should return only dynamic records when Filter is Dynamic' {
            InModuleScope $script:moduleName -Parameters @{ SR = $script:staticRecord; DR = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($SR, $DR) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Dynamic', $false, $null)
                $result | Should -HaveCount 1
                $result[0].HostName | Should -Be 'workstation01'
                $result[0].IsStatic | Should -BeFalse
            }
        }

        It 'Should set Count to 1 for each individual record' {
            InModuleScope $script:moduleName -Parameters @{ SR = $script:staticRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($SR) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $false, $null)
                $result[0].Count | Should -Be 1
            }
        }

        It 'Should use CimSession when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }
                $fakeSession = [PSCustomObject]@{ Id = 1 }
                [PSGDnsEntry]::GetEntries('dc01.contoso.com', 'contoso.com', @('A'), 'All', $false, $fakeSession)
                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'GetEntries static method - DuplicatesOnly' {
        BeforeAll {
            $script:dupRecord1 = [PSCustomObject]@{
                HostName   = 'server01'
                RecordType = 'A'
                TimeStamp  = [datetime]::MinValue
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
            }

            $script:dupRecord2 = [PSCustomObject]@{
                HostName   = 'server01'
                RecordType = 'A'
                TimeStamp  = [datetime]::MinValue
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') }
            }

            $script:uniqueRecord = [PSCustomObject]@{
                HostName   = 'server02'
                RecordType = 'A'
                TimeStamp  = [datetime]::MinValue
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') }
            }

            $script:dynamicDup = [PSCustomObject]@{
                HostName   = 'workstation01'
                RecordType = 'A'
                TimeStamp  = [datetime]'2025-01-15 10:00:00'
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.50') }
            }
        }

        It 'Should return only groups with more than one record' {
            InModuleScope $script:moduleName -Parameters @{ R1 = $script:dupRecord1; R2 = $script:dupRecord2; R3 = $script:uniqueRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R1, $R2, $R3) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $true, $null)
                $result | Should -HaveCount 1
                $result[0].HostName | Should -Be 'server01'
            }
        }

        It 'Should set Count to the number of duplicate records' {
            InModuleScope $script:moduleName -Parameters @{ R1 = $script:dupRecord1; R2 = $script:dupRecord2; R3 = $script:uniqueRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R1, $R2, $R3) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $true, $null)
                $result[0].Count | Should -Be 2
            }
        }

        It 'Should include all data values in RecordData' {
            InModuleScope $script:moduleName -Parameters @{ R1 = $script:dupRecord1; R2 = $script:dupRecord2; R3 = $script:uniqueRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R1, $R2, $R3) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $true, $null)
                $result[0].RecordData | Should -HaveCount 2
                $result[0].RecordData | Should -Contain '192.168.1.10'
                $result[0].RecordData | Should -Contain '192.168.1.11'
            }
        }

        It 'Should return empty when there are no duplicates' {
            InModuleScope $script:moduleName -Parameters @{ R3 = $script:uniqueRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R3) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $true, $null)
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Should set IsStatic to true when all duplicate records are static' {
            InModuleScope $script:moduleName -Parameters @{ R1 = $script:dupRecord1; R2 = $script:dupRecord2 } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R1, $R2) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $true, $null)
                $result[0].IsStatic | Should -BeTrue
            }
        }

        It 'Should combine Filter and DuplicatesOnly: only static duplicates when Filter is Static' {
            InModuleScope $script:moduleName -Parameters @{ R1 = $script:dupRecord1; R2 = $script:dupRecord2; DD = $script:dynamicDup } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R1, $R2, $DD) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Static', $true, $null)
                $result | Should -HaveCount 1
                $result[0].HostName | Should -Be 'server01'
                $result[0].IsStatic | Should -BeTrue
            }
        }

        It 'Should return nothing when Filter excludes all duplicate candidates' {
            InModuleScope $script:moduleName -Parameters @{ R1 = $script:dupRecord1; R2 = $script:dupRecord2 } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($R1, $R2) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Dynamic', $true, $null)
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'ToString method' {
        It 'Should format a single static entry correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10'), $true, [datetime]::MinValue)
                $entry.ToString() | Should -Match '\[A\]'
                $entry.ToString() | Should -Match '\[Static\]'
                $entry.ToString() | Should -Match 'server01'
                $entry.ToString() | Should -Match 'contoso\.com'
                $entry.ToString() | Should -Match '192\.168\.1\.10'
            }
        }

        It 'Should format a single dynamic entry correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('workstation01', 'contoso.com', 'A', @('192.168.1.50'), $false, [datetime]'2025-01-15 10:00:00')
                $entry.ToString() | Should -Match '\[Dynamic\]'
            }
        }

        It 'Should format a duplicate group with record count and all data values' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'), $true, [datetime]::MinValue)
                $entry.ToString() | Should -Match '2 records'
                $entry.ToString() | Should -Match '192\.168\.1\.10'
                $entry.ToString() | Should -Match '192\.168\.1\.11'
            }
        }
    }
}
