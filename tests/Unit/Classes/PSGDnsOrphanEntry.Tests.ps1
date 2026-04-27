BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsOrphanEntry' {
    Context 'Default constructor' {
        It 'Should create an empty instance without throwing' {
            InModuleScope $script:moduleName {
                { [PSGDnsOrphanEntry]::new() } | Should -Not -Throw
            }
        }
    }

    Context 'Parameterized constructor' {
        It 'Should set all properties correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsOrphanEntry]::new('server01', 'contoso.com', '192.168.1.10', 'MissingPTR')
                $entry.HostName   | Should -Be 'server01'
                $entry.ZoneName   | Should -Be 'contoso.com'
                $entry.IPAddress  | Should -Be '192.168.1.10'
                $entry.OrphanType | Should -Be 'MissingPTR'
            }
        }
    }

    Context 'FindOrphans - MissingPTR' {
        BeforeAll {
            $script:aWithPtr = [PSCustomObject]@{
                HostName   = 'server01'
                RecordType = 'A'
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
            }
            $script:aWithoutPtr = [PSCustomObject]@{
                HostName   = 'server02'
                RecordType = 'A'
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') }
            }
            $script:existingPtr = [PSCustomObject]@{
                HostName   = '10'
                RecordType = 'PTR'
                RecordData = [PSCustomObject]@{ PtrDomainName = 'server01.contoso.com.' }
            }
        }

        It 'Should return only A records that have no PTR' {
            InModuleScope $script:moduleName -Parameters @{ AR1 = $script:aWithPtr; AR2 = $script:aWithoutPtr; PTR1 = $script:existingPtr } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($AR1, $AR2) } `
                    -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' -and [string]::IsNullOrEmpty($Name) }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($PTR1) } `
                    -ParameterFilter { $ZoneName -eq '1.168.192.in-addr.arpa' -and $RRType -eq 'PTR' -and $Name -eq '10' }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } `
                    -ParameterFilter { $ZoneName -eq '1.168.192.in-addr.arpa' -and $RRType -eq 'PTR' -and $Name -eq '20' }

                $result = [PSGDnsOrphanEntry]::FindOrphans('localhost', @('contoso.com'), @('1.168.192.in-addr.arpa'), 'MissingPTR', $null)
                $result | Should -HaveCount 1
                $result[0].HostName   | Should -Be 'server02'
                $result[0].IPAddress  | Should -Be '192.168.1.20'
                $result[0].OrphanType | Should -Be 'MissingPTR'
            }
        }

        It 'Should return empty when all A records have a PTR' {
            InModuleScope $script:moduleName -Parameters @{ AR1 = $script:aWithPtr; PTR1 = $script:existingPtr } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($AR1) } `
                    -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' -and [string]::IsNullOrEmpty($Name) }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($PTR1) } `
                    -ParameterFilter { $ZoneName -eq '1.168.192.in-addr.arpa' -and $RRType -eq 'PTR' -and $Name -eq '10' }

                $result = [PSGDnsOrphanEntry]::FindOrphans('localhost', @('contoso.com'), @('1.168.192.in-addr.arpa'), 'MissingPTR', $null)
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Should skip A records when no reverse zone covers the IP' {
            InModuleScope $script:moduleName -Parameters @{ AR1 = $script:aWithPtr } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($AR1) } `
                    -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' }

                $result = [PSGDnsOrphanEntry]::FindOrphans('localhost', @('contoso.com'), @(), 'MissingPTR', $null)
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'FindOrphans - MissingA' {
        BeforeAll {
            $script:ptrWithA = [PSCustomObject]@{
                HostName   = '10'
                RecordType = 'PTR'
                RecordData = [PSCustomObject]@{ PtrDomainName = 'server01.contoso.com.' }
            }
            $script:ptrWithoutA = [PSCustomObject]@{
                HostName   = '30'
                RecordType = 'PTR'
                RecordData = [PSCustomObject]@{ PtrDomainName = 'orphan.contoso.com.' }
            }
            $script:existingA = [PSCustomObject]@{
                HostName   = 'server01'
                RecordType = 'A'
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
            }
        }

        It 'Should return only PTR records that have no A record' {
            InModuleScope $script:moduleName -Parameters @{ PTR1 = $script:ptrWithA; PTR2 = $script:ptrWithoutA; AR1 = $script:existingA } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($PTR1, $PTR2) } `
                    -ParameterFilter { $ZoneName -eq '1.168.192.in-addr.arpa' -and $RRType -eq 'PTR' -and [string]::IsNullOrEmpty($Name) }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($AR1) } `
                    -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' -and $Name -eq 'server01' }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } `
                    -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' -and $Name -eq 'orphan' }

                $result = [PSGDnsOrphanEntry]::FindOrphans('localhost', @('contoso.com'), @('1.168.192.in-addr.arpa'), 'MissingA', $null)
                $result | Should -HaveCount 1
                $result[0].HostName   | Should -Be 'orphan.contoso.com'
                $result[0].IPAddress  | Should -Be '192.168.1.30'
                $result[0].OrphanType | Should -Be 'MissingA'
            }
        }

        It 'Should skip PTR records whose target hostname is in an unmanaged zone' {
            InModuleScope $script:moduleName {
                $externalPtr = [PSCustomObject]@{
                    HostName   = '10'
                    RecordType = 'PTR'
                    RecordData = [PSCustomObject]@{ PtrDomainName = 'server01.external.com.' }
                }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($externalPtr) } `
                    -ParameterFilter { $ZoneName -eq '1.168.192.in-addr.arpa' -and $RRType -eq 'PTR' }

                $result = [PSGDnsOrphanEntry]::FindOrphans('localhost', @('contoso.com'), @('1.168.192.in-addr.arpa'), 'MissingA', $null)
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Should return empty when all PTR records have a matching A record' {
            InModuleScope $script:moduleName -Parameters @{ PTR1 = $script:ptrWithA; AR1 = $script:existingA } {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($PTR1) } `
                    -ParameterFilter { $ZoneName -eq '1.168.192.in-addr.arpa' -and $RRType -eq 'PTR' -and [string]::IsNullOrEmpty($Name) }
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @($AR1) } `
                    -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' -and $Name -eq 'server01' }

                $result = [PSGDnsOrphanEntry]::FindOrphans('localhost', @('contoso.com'), @('1.168.192.in-addr.arpa'), 'MissingA', $null)
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'FindOrphans - CimSession' {
        It 'Should pass CimSession to Get-DnsServerResourceRecord' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }
                [PSGDnsOrphanEntry]::FindOrphans('dc01.contoso.com', @('contoso.com'), @('1.168.192.in-addr.arpa'), 'MissingPTR', [PSCustomObject]@{ Id = 1 })
                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Scope It
            }
        }
    }

    Context 'ToString method' {
        It 'Should format MissingPTR entries correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsOrphanEntry]::new('server02', 'contoso.com', '192.168.1.20', 'MissingPTR')
                $entry.ToString() | Should -Match '\[MissingPTR\]'
                $entry.ToString() | Should -Match 'server02'
                $entry.ToString() | Should -Match '192\.168\.1\.20'
            }
        }

        It 'Should format MissingA entries correctly' {
            InModuleScope $script:moduleName {
                $entry = [PSGDnsOrphanEntry]::new('orphan.contoso.com', '1.168.192.in-addr.arpa', '192.168.1.30', 'MissingA')
                $entry.ToString() | Should -Match '\[MissingA\]'
                $entry.ToString() | Should -Match 'orphan\.contoso\.com'
                $entry.ToString() | Should -Match '192\.168\.1\.30'
            }
        }
    }
}
