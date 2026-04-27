BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsZoneStat' {
    Context 'Constructor' {
        It 'Should create an instance with the default constructor' {
            InModuleScope $script:moduleName {
                [PSGDnsZoneStat]::new() | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should set all properties via the parameterized constructor' {
            InModuleScope $script:moduleName {
                $byType = @{ A = 5; AAAA = 2; CNAME = 3; MX = 1; PTR = 0; SRV = 0; TXT = 1 }
                $obj    = [PSGDnsZoneStat]::new('contoso.com', 'Primary', 12, 8, 4, 1, $byType)
                $obj.ZoneName     | Should -Be 'contoso.com'
                $obj.ZoneType     | Should -Be 'Primary'
                $obj.TotalRecords | Should -Be 12
                $obj.StaticCount  | Should -Be 8
                $obj.DynamicCount | Should -Be 4
                $obj.StaleCount   | Should -Be 1
                $obj.ByType['A']  | Should -Be 5
                $obj.ByType['MX'] | Should -Be 1
            }
        }
    }

    Context 'ToString method' {
        It 'Should return the expected formatted string' {
            InModuleScope $script:moduleName {
                $obj = [PSGDnsZoneStat]::new('contoso.com', 'Primary', 12, 8, 4, 1, @{})
                $obj.ToString() | Should -Be '[ZoneStat] contoso.com (Primary) — Total: 12 | Static: 8 | Dynamic: 4 | Stale: 1'
            }
        }
    }

    Context 'GetZoneStats static method' {
        It 'Should count static and dynamic records correctly' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @([PSCustomObject]@{ ZoneName = 'contoso.com'; ZoneType = 'Primary' })
                }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($RRType)
                    if ($RRType -eq 'A')
                    {
                        @(
                            [PSCustomObject]@{ RecordType = 'A'; TimeStamp = $null;                              RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                            [PSCustomObject]@{ RecordType = 'A'; TimeStamp = [datetime]::Now.AddDays(-10);       RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') } }
                        )
                    }
                    else { @() }
                }

                $results = [PSGDnsZoneStat]::GetZoneStats('localhost', @('contoso.com'), 30, $null)
                $results | Should -HaveCount 1
                $results[0].TotalRecords | Should -Be 2
                $results[0].StaticCount  | Should -Be 1
                $results[0].DynamicCount | Should -Be 1
                $results[0].StaleCount   | Should -Be 0
            }
        }

        It 'Should count stale records correctly' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @([PSCustomObject]@{ ZoneName = 'contoso.com'; ZoneType = 'Primary' })
                }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($RRType)
                    if ($RRType -eq 'A')
                    {
                        @(
                            [PSCustomObject]@{ RecordType = 'A'; TimeStamp = [datetime]::Now.AddDays(-60); RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                            [PSCustomObject]@{ RecordType = 'A'; TimeStamp = [datetime]::Now.AddDays(-10); RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') } }
                        )
                    }
                    else { @() }
                }

                $results = [PSGDnsZoneStat]::GetZoneStats('localhost', @('contoso.com'), 30, $null)
                $results[0].StaleCount   | Should -Be 1
                $results[0].DynamicCount | Should -Be 2
            }
        }

        It 'Should populate ByType hashtable for each record type' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @([PSCustomObject]@{ ZoneName = 'contoso.com'; ZoneType = 'Primary' })
                }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($RRType)
                    if ($RRType -eq 'A')
                    {
                        @([PSCustomObject]@{ RecordType = 'A'; TimeStamp = $null; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } })
                    }
                    elseif ($RRType -eq 'CNAME')
                    {
                        @([PSCustomObject]@{ RecordType = 'CNAME'; TimeStamp = $null; RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com.' } })
                    }
                    else { @() }
                }

                $results = [PSGDnsZoneStat]::GetZoneStats('localhost', @('contoso.com'), 30, $null)
                $results[0].ByType['A']     | Should -Be 1
                $results[0].ByType['CNAME'] | Should -Be 1
                $results[0].ByType['MX']    | Should -Be 0
            }
        }

        It 'Should return one entry per zone' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @(
                        [PSCustomObject]@{ ZoneName = 'contoso.com';  ZoneType = 'Primary' },
                        [PSCustomObject]@{ ZoneName = 'fabrikam.com'; ZoneType = 'Primary' }
                    )
                }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                $results = [PSGDnsZoneStat]::GetZoneStats('localhost', @('contoso.com', 'fabrikam.com'), 30, $null)
                $results | Should -HaveCount 2
            }
        }

        It 'Should use CimSession parameter when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone              -MockWith { @() }
                Mock -CommandName Get-DnsServerResourceRecord    -MockWith { @() }

                [PSGDnsZoneStat]::GetZoneStats('dc01.contoso.com', @('contoso.com'), 30, [PSCustomObject]@{ Id = 1 })

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Scope It
            }
        }

        It 'Should use ComputerName parameter when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone              -MockWith { @() }
                Mock -CommandName Get-DnsServerResourceRecord    -MockWith { @() }

                [PSGDnsZoneStat]::GetZoneStats('dc01.contoso.com', @('contoso.com'), 30, $null)

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Scope It
            }
        }
    }
}
