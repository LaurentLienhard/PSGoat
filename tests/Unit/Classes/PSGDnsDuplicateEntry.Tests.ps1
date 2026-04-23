BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsDuplicateEntry' {
    Context 'Default constructor' {
        It 'Should create an empty instance without throwing' {
            InModuleScope $script:moduleName {
                { [PSGDnsDuplicateEntry]::new() } | Should -Not -Throw
            }
        }
    }

    Context 'Parameterized constructor' {
        It 'Should set HostName correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsDuplicateEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'))
                $entry.HostName | Should -Be 'server01'
            }
        }

        It 'Should set ZoneName correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsDuplicateEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'))
                $entry.ZoneName | Should -Be 'contoso.com'
            }
        }

        It 'Should set RecordType correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsDuplicateEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'))
                $entry.RecordType | Should -Be 'A'
            }
        }

        It 'Should set RecordData correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsDuplicateEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'))
                $entry.RecordData | Should -HaveCount 2
                $entry.RecordData[0] | Should -Be '192.168.1.10'
                $entry.RecordData[1] | Should -Be '192.168.1.11'
            }
        }

        It 'Should compute DuplicateCount from RecordData length' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsDuplicateEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'))
                $entry.DuplicateCount | Should -Be 2
            }
        }
    }

    Context 'NewSession static method' {
        It 'Should return null when Credential is null' {
            InModuleScope $script:moduleName {
                $result = [PSGDnsDuplicateEntry]::NewSession('dc01.contoso.com', $null)
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Should call New-CimSession when Credential is provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } }
                $cred = [PSCredential]::new('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
                [PSGDnsDuplicateEntry]::NewSession('dc01.contoso.com', $cred) | Should -Not -BeNullOrEmpty
                Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'RemoveSession static method' {
        It 'Should not throw when CimSession is null' {
            InModuleScope $script:moduleName {
                { [PSGDnsDuplicateEntry]::RemoveSession($null) } | Should -Not -Throw
            }
        }

        It 'Should call Remove-CimSession when a session is provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Remove-CimSession -MockWith {}
                $fakeSession = [PSCustomObject]@{ Id = 1 }
                [PSGDnsDuplicateEntry]::RemoveSession($fakeSession)
                Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'ExtractRecordData static method' {
        It 'Should return IPv4 address for A records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'A'
                    RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
                }
                [PSGDnsDuplicateEntry]::ExtractRecordData($record) | Should -Be '192.168.1.10'
            }
        }

        It 'Should return IPv6 address for AAAA records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'AAAA'
                    RecordData = [PSCustomObject]@{ IPv6Address = [System.Net.IPAddress]::Parse('::1') }
                }
                [PSGDnsDuplicateEntry]::ExtractRecordData($record) | Should -Be '::1'
            }
        }

        It 'Should return alias for CNAME records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'CNAME'
                    RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com' }
                }
                [PSGDnsDuplicateEntry]::ExtractRecordData($record) | Should -Be 'server01.contoso.com'
            }
        }

        It 'Should return PTR domain name for PTR records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'PTR'
                    RecordData = [PSCustomObject]@{ PtrDomainName = 'server01.contoso.com' }
                }
                [PSGDnsDuplicateEntry]::ExtractRecordData($record) | Should -Be 'server01.contoso.com'
            }
        }

        It 'Should return descriptive text for TXT records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'TXT'
                    RecordData = [PSCustomObject]@{ DescriptiveText = 'v=spf1 include:contoso.com ~all' }
                }
                [PSGDnsDuplicateEntry]::ExtractRecordData($record) | Should -Be 'v=spf1 include:contoso.com ~all'
            }
        }
    }

    Context 'GetZones static method' {
        It 'Should return only primary non-auto-created zones when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @(
                        [PSCustomObject]@{ ZoneName = 'contoso.com';   IsAutoCreated = $false; ZoneType = 'Primary'   },
                        [PSCustomObject]@{ ZoneName = 'auto.local';    IsAutoCreated = $true;  ZoneType = 'Primary'   },
                        [PSCustomObject]@{ ZoneName = 'secondary.com'; IsAutoCreated = $false; ZoneType = 'Secondary' }
                    )
                }
                $zones = [PSGDnsDuplicateEntry]::GetZones('localhost', $null)
                $zones | Should -HaveCount 1
                $zones[0] | Should -Be 'contoso.com'
            }
        }

        It 'Should use CimSession when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @([PSCustomObject]@{ ZoneName = 'contoso.com'; IsAutoCreated = $false; ZoneType = 'Primary' })
                }
                $fakeSession = [PSCustomObject]@{ Id = 1 }
                [PSGDnsDuplicateEntry]::GetZones('dc01.contoso.com', $fakeSession)
                Should -Invoke -CommandName Get-DnsServerZone -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'FindInZone static method' {
        It 'Should return duplicate entries only' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @(
                        [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                        [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') } },
                        [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') } }
                    )
                }
                $result = [PSGDnsDuplicateEntry]::FindInZone('localhost', 'contoso.com', @('A'), $null)
                $result | Should -HaveCount 1
                $result[0].HostName | Should -Be 'server01'
                $result[0].DuplicateCount | Should -Be 2
            }
        }

        It 'Should return an empty array when there are no duplicates' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @(
                        [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                        [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') } }
                    )
                }
                $result = [PSGDnsDuplicateEntry]::FindInZone('localhost', 'contoso.com', @('A'), $null)
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Should use CimSession when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }
                $fakeSession = [PSCustomObject]@{ Id = 1 }
                [PSGDnsDuplicateEntry]::FindInZone('dc01.contoso.com', 'contoso.com', @('A'), $fakeSession)
                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'ToString method' {
        It 'Should include hostname, zone and record type' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsDuplicateEntry]::new('server01', 'contoso.com', 'A', @('192.168.1.10', '192.168.1.11'))
                $entry.ToString() | Should -Match 'server01'
                $entry.ToString() | Should -Match 'contoso\.com'
                $entry.ToString() | Should -Match '\[A\]'
            }
        }
    }
}
