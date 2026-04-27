BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsDuplicateIp' {
    Context 'Constructor' {
        It 'Should create an instance with the default constructor' {
            InModuleScope $script:moduleName {
                [PSGDnsDuplicateIp]::new() | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should set all properties via the parameterized constructor' {
            InModuleScope $script:moduleName {
                $obj = [PSGDnsDuplicateIp]::new('192.168.1.10', @('server01.contoso.com', 'server02.contoso.com'))
                $obj.IPAddress  | Should -Be '192.168.1.10'
                $obj.HostNames  | Should -HaveCount 2
                $obj.HostNames  | Should -Contain 'server01.contoso.com'
                $obj.HostNames  | Should -Contain 'server02.contoso.com'
                $obj.Count      | Should -Be 2
            }
        }
    }

    Context 'ToString method' {
        It 'Should return the expected formatted string' {
            InModuleScope $script:moduleName {
                $obj = [PSGDnsDuplicateIp]::new('192.168.1.10', @('server01.contoso.com', 'server02.contoso.com'))
                $obj.ToString() | Should -BeLike '[DuplicateIp] 192.168.1.10*'
                $obj.ToString() | Should -BeLike '*2 host(s)*'
            }
        }
    }

    Context 'FindDuplicateIps static method' {
        It 'Should return an entry when two hostnames share the same IP' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @(
                        [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                        [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } }
                    )
                }

                $results = [PSGDnsDuplicateIp]::FindDuplicateIps('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 1
                $results[0].IPAddress | Should -Be '192.168.1.10'
                $results[0].Count     | Should -Be 2
            }
        }

        It 'Should not return an entry when each IP is used by only one hostname' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @(
                        [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                        [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') } }
                    )
                }

                $results = [PSGDnsDuplicateIp]::FindDuplicateIps('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should detect duplicates across multiple zones' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($ZoneName)
                    if ($ZoneName -eq 'contoso.com')
                    {
                        @([PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } })
                    }
                    else
                    {
                        @([PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } })
                    }
                }

                $results = [PSGDnsDuplicateIp]::FindDuplicateIps('localhost', @('contoso.com', 'fabrikam.com'), $null)
                $results | Should -HaveCount 1
                $results[0].Count | Should -Be 2
            }
        }

        It 'Should use CimSession parameter when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsDuplicateIp]::FindDuplicateIps('dc01.contoso.com', @('contoso.com'), [PSCustomObject]@{ Id = 1 })

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should use ComputerName parameter when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsDuplicateIp]::FindDuplicateIps('dc01.contoso.com', @('contoso.com'), $null)

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should return an empty array when there are no A records' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                $results = [PSGDnsDuplicateIp]::FindDuplicateIps('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 0
            }
        }
    }
}
