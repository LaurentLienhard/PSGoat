BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsStaleEntry' {
    Context 'Constructor' {
        It 'Should create an instance with the default constructor' {
            InModuleScope $script:moduleName {
                [PSGDnsStaleEntry]::new() | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should set all properties via the parameterized constructor' {
            InModuleScope $script:moduleName {
                $ts  = [datetime]'2025-01-01 00:00:00'
                $obj = [PSGDnsStaleEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $ts, 45)
                $obj.HostName   | Should -Be 'server01'
                $obj.ZoneName   | Should -Be 'contoso.com'
                $obj.RecordType | Should -Be 'A'
                $obj.IPAddress  | Should -Be '192.168.1.10'
                $obj.TimeStamp  | Should -Be $ts
                $obj.AgeDays    | Should -Be 45
            }
        }
    }

    Context 'ToString method' {
        It 'Should return the expected formatted string' {
            InModuleScope $script:moduleName {
                $ts  = [datetime]'2025-01-15 00:00:00'
                $obj = [PSGDnsStaleEntry]::new('server01', 'contoso.com', 'A', '192.168.1.10', $ts, 45)
                $obj.ToString() | Should -Be '[Stale] server01.contoso.com (192.168.1.10) — last seen 2025-01-15 (45 day(s))'
            }
        }
    }

    Context 'FindStaleRecords static method' {
        It 'Should return records older than the threshold' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @([PSCustomObject]@{
                        HostName   = 'server01'
                        RecordType = 'A'
                        TimeStamp  = [datetime]::Now.AddDays(-60)
                        RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
                    })
                }

                $results = [PSGDnsStaleEntry]::FindStaleRecords('localhost', @('contoso.com'), @('A'), 30, $null)
                $results | Should -HaveCount 1
                $results[0].HostName | Should -Be 'server01'
                $results[0].AgeDays  | Should -BeGreaterThan 30
            }
        }

        It 'Should not return records within the threshold' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @([PSCustomObject]@{
                        HostName   = 'server01'
                        RecordType = 'A'
                        TimeStamp  = [datetime]::Now.AddDays(-10)
                        RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
                    })
                }

                $results = [PSGDnsStaleEntry]::FindStaleRecords('localhost', @('contoso.com'), @('A'), 30, $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should ignore static records (null TimeStamp)' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @([PSCustomObject]@{
                        HostName   = 'server01'
                        RecordType = 'A'
                        TimeStamp  = $null
                        RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
                    })
                }

                $results = [PSGDnsStaleEntry]::FindStaleRecords('localhost', @('contoso.com'), @('A'), 30, $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should ignore static records (MinValue TimeStamp)' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @([PSCustomObject]@{
                        HostName   = 'server01'
                        RecordType = 'A'
                        TimeStamp  = [datetime]::MinValue
                        RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
                    })
                }

                $results = [PSGDnsStaleEntry]::FindStaleRecords('localhost', @('contoso.com'), @('A'), 30, $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should use CimSession parameter when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsStaleEntry]::FindStaleRecords('dc01.contoso.com', @('contoso.com'), @('A'), 30, [PSCustomObject]@{ Id = 1 })

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should use ComputerName parameter when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsStaleEntry]::FindStaleRecords('dc01.contoso.com', @('contoso.com'), @('A'), 30, $null)

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should return an empty array when no records exist' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                $results = [PSGDnsStaleEntry]::FindStaleRecords('localhost', @('contoso.com'), @('A'), 30, $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should evaluate both A and AAAA record types when both are requested' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsStaleEntry]::FindStaleRecords('localhost', @('contoso.com'), @('A', 'AAAA'), 30, $null)

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $RRType -eq 'A' }    -Exactly -Times 1 -Scope It
                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $RRType -eq 'AAAA' } -Exactly -Times 1 -Scope It
            }
        }
    }
}
