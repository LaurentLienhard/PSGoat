BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsBase' {
    Context 'NewSession static method' {
        It 'Should return null when Credential is null' {
            InModuleScope $script:moduleName {
                [PSGDnsBase]::NewSession('dc01.contoso.com', $null) | Should -BeNullOrEmpty
            }
        }

        It 'Should call New-CimSession with ErrorAction Stop when Credential is provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } }
                $cred = [PSCredential]::new('contoso\admin', (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force))
                [PSGDnsBase]::NewSession('dc01.contoso.com', $cred) | Should -Not -BeNullOrEmpty
                Should -Invoke -CommandName New-CimSession -ParameterFilter { $ErrorAction -eq 'Stop' } -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'RemoveSession static method' {
        It 'Should not throw when CimSession is null' {
            InModuleScope $script:moduleName {
                { [PSGDnsBase]::RemoveSession($null) } | Should -Not -Throw
            }
        }

        It 'Should call Remove-CimSession when a session is provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Remove-CimSession -MockWith {}
                [PSGDnsBase]::RemoveSession([PSCustomObject]@{ Id = 1 })
                Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'GetZones static method' {
        It 'Should return only primary non-auto-created zones' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @(
                        [PSCustomObject]@{ ZoneName = 'contoso.com';   IsAutoCreated = $false; ZoneType = 'Primary'   },
                        [PSCustomObject]@{ ZoneName = 'auto.local';    IsAutoCreated = $true;  ZoneType = 'Primary'   },
                        [PSCustomObject]@{ ZoneName = 'secondary.com'; IsAutoCreated = $false; ZoneType = 'Secondary' }
                    )
                }
                $zones = [PSGDnsBase]::GetZones('localhost', $null)
                $zones | Should -HaveCount 1
                $zones[0] | Should -Be 'contoso.com'
            }
        }

        It 'Should use CimSession parameter when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @([PSCustomObject]@{ ZoneName = 'contoso.com'; IsAutoCreated = $false; ZoneType = 'Primary' })
                }
                [PSGDnsBase]::GetZones('dc01.contoso.com', [PSCustomObject]@{ Id = 1 })
                Should -Invoke -CommandName Get-DnsServerZone -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should use ComputerName parameter when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerZone -MockWith {
                    @([PSCustomObject]@{ ZoneName = 'contoso.com'; IsAutoCreated = $false; ZoneType = 'Primary' })
                }
                [PSGDnsBase]::GetZones('dc01.contoso.com', $null)
                Should -Invoke -CommandName Get-DnsServerZone -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It
            }
        }
    }

    Context 'IsStaticRecord static method' {
        It 'Should return true when TimeStamp is null' {
            InModuleScope $script:moduleName {
                [PSGDnsBase]::IsStaticRecord([PSCustomObject]@{ TimeStamp = $null }) | Should -BeTrue
            }
        }

        It 'Should return true when TimeStamp is MinValue' {
            InModuleScope $script:moduleName {
                [PSGDnsBase]::IsStaticRecord([PSCustomObject]@{ TimeStamp = [datetime]::MinValue }) | Should -BeTrue
            }
        }

        It 'Should return false when TimeStamp has an actual value' {
            InModuleScope $script:moduleName {
                [PSGDnsBase]::IsStaticRecord([PSCustomObject]@{ TimeStamp = [datetime]'2025-01-15 10:00:00' }) | Should -BeFalse
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
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be '192.168.1.10'
            }
        }

        It 'Should return IPv6 address for AAAA records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'AAAA'
                    RecordData = [PSCustomObject]@{ IPv6Address = [System.Net.IPAddress]::Parse('::1') }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be '::1'
            }
        }

        It 'Should return alias for CNAME records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'CNAME'
                    RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com' }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be 'server01.contoso.com'
            }
        }

        It 'Should return mail exchange for MX records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'MX'
                    RecordData = [PSCustomObject]@{ MailExchange = 'mail.contoso.com' }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be 'mail.contoso.com'
            }
        }

        It 'Should return PTR domain name for PTR records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'PTR'
                    RecordData = [PSCustomObject]@{ PtrDomainName = 'server01.contoso.com' }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be 'server01.contoso.com'
            }
        }

        It 'Should return priority weight port domainname for SRV records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'SRV'
                    RecordData = [PSCustomObject]@{ Priority = 10; Weight = 20; Port = 443; DomainName = 'svc.contoso.com' }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be '10 20 443 svc.contoso.com'
            }
        }

        It 'Should return descriptive text for TXT records' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'TXT'
                    RecordData = [PSCustomObject]@{ DescriptiveText = 'v=spf1 include:contoso.com ~all' }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Be 'v=spf1 include:contoso.com ~all'
            }
        }

        It 'Should call ToString on RecordData for unknown record types' {
            InModuleScope $script:moduleName {
                $record = [PSCustomObject]@{
                    RecordType = 'UNKNOWN'
                    RecordData = [PSCustomObject]@{ ToString = { 'raw-data' } }
                }
                [PSGDnsBase]::ExtractRecordData($record) | Should -Not -BeNullOrEmpty
            }
        }
    }
}
