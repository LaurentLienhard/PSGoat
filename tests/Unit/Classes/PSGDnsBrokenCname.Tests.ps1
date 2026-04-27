BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsBrokenCname' {
    Context 'Constructor' {
        It 'Should create an instance with default constructor' {
            InModuleScope $script:moduleName {
                $obj = [PSGDnsBrokenCname]::new()
                $obj | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should set properties via parameterized constructor' {
            InModuleScope $script:moduleName {
                $obj = [PSGDnsBrokenCname]::new('alias', 'contoso.com', 'missing.contoso.com')
                $obj.HostName | Should -Be 'alias'
                $obj.ZoneName | Should -Be 'contoso.com'
                $obj.Target   | Should -Be 'missing.contoso.com'
            }
        }
    }

    Context 'ToString method' {
        It 'Should return the expected formatted string' {
            InModuleScope $script:moduleName {
                $obj = [PSGDnsBrokenCname]::new('alias', 'contoso.com', 'missing.contoso.com')
                $obj.ToString() | Should -Be '[BrokenCNAME] alias.contoso.com -> missing.contoso.com (target not found)'
            }
        }
    }

    Context 'FindBrokenCnames static method' {
        It 'Should return a broken CNAME when target has no A, AAAA or CNAME record' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($ZoneName, $RRType)
                    if ($RRType -eq 'CNAME')
                    {
                        @([PSCustomObject]@{
                            HostName   = 'alias'
                            RecordType = 'CNAME'
                            RecordData = [PSCustomObject]@{ HostNameAlias = 'missing.contoso.com.' }
                        })
                    }
                    else
                    {
                        $null
                    }
                }

                $results = [PSGDnsBrokenCname]::FindBrokenCnames('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 1
                $results[0].HostName | Should -Be 'alias'
                $results[0].ZoneName | Should -Be 'contoso.com'
                $results[0].Target   | Should -Be 'missing.contoso.com'
            }
        }

        It 'Should not report a CNAME when the target has an A record' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($ZoneName, $RRType, $Name)
                    if ($RRType -eq 'CNAME')
                    {
                        @([PSCustomObject]@{
                            HostName   = 'alias'
                            RecordType = 'CNAME'
                            RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com.' }
                        })
                    }
                    else
                    {
                        @([PSCustomObject]@{ RecordType = 'A' })
                    }
                }

                $results = [PSGDnsBrokenCname]::FindBrokenCnames('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should skip CNAME records pointing to external zones' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($RRType)
                    if ($RRType -eq 'CNAME')
                    {
                        @([PSCustomObject]@{
                            HostName   = 'alias'
                            RecordType = 'CNAME'
                            RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.external.com.' }
                        })
                    }
                }

                $results = [PSGDnsBrokenCname]::FindBrokenCnames('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should handle a CNAME pointing to the zone apex (@)' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    param ($ZoneName, $RRType, $Name)
                    if ($RRType -eq 'CNAME')
                    {
                        @([PSCustomObject]@{
                            HostName   = 'alias'
                            RecordType = 'CNAME'
                            RecordData = [PSCustomObject]@{ HostNameAlias = 'contoso.com.' }
                        })
                    }
                    else
                    {
                        $null
                    }
                }

                $results = [PSGDnsBrokenCname]::FindBrokenCnames('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 1
                $results[0].Target | Should -Be 'contoso.com'
            }
        }

        It 'Should use CimSession parameter when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsBrokenCname]::FindBrokenCnames('dc01.contoso.com', @('contoso.com'), [PSCustomObject]@{ Id = 1 })

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should use ComputerName parameter when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsBrokenCname]::FindBrokenCnames('dc01.contoso.com', @('contoso.com'), $null)

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should return an empty array when there are no CNAME records' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                $results = [PSGDnsBrokenCname]::FindBrokenCnames('localhost', @('contoso.com'), $null)
                $results | Should -HaveCount 0
            }
        }
    }
}
