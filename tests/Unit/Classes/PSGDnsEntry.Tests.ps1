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
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.HostName | Should -Be 'server01'
            }
        }

        It 'Should set ZoneName correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.ZoneName | Should -Be 'contoso.com'
            }
        }

        It 'Should set RecordType correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.RecordType | Should -Be 'A'
            }
        }

        It 'Should set RecordData correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.RecordData | Should -Be '192.168.1.10'
            }
        }

        It 'Should set IsStatic correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.IsStatic | Should -BeTrue
            }
        }

        It 'Should set TimeStamp correctly' {
            InModuleScope $script:moduleName {
                $ts = [datetime]'2025-01-15 10:00:00'
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $false, $ts)
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

    Context 'GetEntries static method' {
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

        It 'Should return both static and dynamic records when Filter is All' {
            InModuleScope $script:moduleName -Parameters @{ StaticRec = $script:staticRecord; DynamicRec = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($StaticRec, $DynamicRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $null)
                $result | Should -HaveCount 2
            }
        }

        It 'Should return only static records when Filter is Static' {
            InModuleScope $script:moduleName -Parameters @{ StaticRec = $script:staticRecord; DynamicRec = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($StaticRec, $DynamicRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Static', $null)
                $result | Should -HaveCount 1
                $result[0].HostName  | Should -Be 'server01'
                $result[0].IsStatic  | Should -BeTrue
            }
        }

        It 'Should return only dynamic records when Filter is Dynamic' {
            InModuleScope $script:moduleName -Parameters @{ StaticRec = $script:staticRecord; DynamicRec = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($StaticRec, $DynamicRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Dynamic', $null)
                $result | Should -HaveCount 1
                $result[0].HostName  | Should -Be 'workstation01'
                $result[0].IsStatic  | Should -BeFalse
            }
        }

        It 'Should return an empty array when no records match the filter' {
            InModuleScope $script:moduleName -Parameters @{ StaticRec = $script:staticRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($StaticRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'Dynamic', $null)
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Should use CimSession when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }
                $fakeSession = [PSCustomObject]@{ Id = 1 }
                [PSGDnsEntry]::GetEntries('dc01.contoso.com', 'contoso.com', @('A'), 'All', $fakeSession)
                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should set IsStatic to true for records with MinValue timestamp' {
            InModuleScope $script:moduleName -Parameters @{ StaticRec = $script:staticRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($StaticRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $null)
                $result[0].IsStatic | Should -BeTrue
            }
        }

        It 'Should set IsStatic to false for records with a real timestamp' {
            InModuleScope $script:moduleName -Parameters @{ DynamicRec = $script:dynamicRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($DynamicRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $null)
                $result[0].IsStatic | Should -BeFalse
            }
        }

        It 'Should populate RecordData from the record' {
            InModuleScope $script:moduleName -Parameters @{ StaticRec = $script:staticRecord } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($StaticRec) }
                $result = [PSGDnsEntry]::GetEntries('localhost', 'contoso.com', @('A'), 'All', $null)
                $result[0].RecordData | Should -Be '192.168.1.10'
            }
        }
    }

    Context 'ToString method' {
        It 'Should include Static label for static entries' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.ToString() | Should -Match 'Static'
            }
        }

        It 'Should include Dynamic label for dynamic entries' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('workstation01', 'contoso.com', 'A', '192.168.1.50', $false, [datetime]'2025-01-15 10:00:00')
                $entry.ToString() | Should -Match 'Dynamic'
            }
        }

        It 'Should include hostname, zone, record type and data' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $true, [datetime]::MinValue)
                $entry.ToString() | Should -Match 'server01'
                $entry.ToString() | Should -Match 'contoso\.com'
                $entry.ToString() | Should -Match '\[A\]'
                $entry.ToString() | Should -Match '192\.168\.1\.10'
            }
        }
    }
}
