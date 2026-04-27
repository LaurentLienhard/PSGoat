BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGDnsCnameChain' {
    Context 'Constructor' {
        It 'Should create an instance with the default constructor' {
            InModuleScope $script:moduleName {
                [PSGDnsCnameChain]::new() | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should set all properties via the parameterized constructor' {
            InModuleScope $script:moduleName {
                $chain = @('alias.contoso.com', 'intermediate.contoso.com', 'server01.contoso.com')
                $obj   = [PSGDnsCnameChain]::new('alias', 'contoso.com', $chain, 2, $false)
                $obj.HostName   | Should -Be 'alias'
                $obj.ZoneName   | Should -Be 'contoso.com'
                $obj.Chain      | Should -HaveCount 3
                $obj.Depth      | Should -Be 2
                $obj.IsCircular | Should -BeFalse
            }
        }
    }

    Context 'ToString method' {
        It 'Should include [CIRCULAR] when IsCircular is true' {
            InModuleScope $script:moduleName {
                $chain = @('a.contoso.com', 'b.contoso.com', 'a.contoso.com')
                $obj   = [PSGDnsCnameChain]::new('a', 'contoso.com', $chain, 2, $true)
                $obj.ToString() | Should -BeLike '*[CIRCULAR]*'
            }
        }

        It 'Should not include [CIRCULAR] when IsCircular is false' {
            InModuleScope $script:moduleName {
                $chain = @('alias.contoso.com', 'mid.contoso.com', 'server01.contoso.com')
                $obj   = [PSGDnsCnameChain]::new('alias', 'contoso.com', $chain, 2, $false)
                $obj.ToString() | Should -Not -BeLike '*[CIRCULAR]*'
            }
        }
    }

    Context 'FindCnameChains static method' {
        It 'Should detect a chain of depth 2' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @(
                        [PSCustomObject]@{ HostName = 'alias';        RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'intermediate.contoso.com.' } },
                        [PSCustomObject]@{ HostName = 'intermediate'; RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com.' } }
                    )
                }

                $results = [PSGDnsCnameChain]::FindCnameChains('localhost', @('contoso.com'), 2, $null)
                $results | Should -HaveCount 1
                $results[0].HostName   | Should -Be 'alias'
                $results[0].Depth      | Should -Be 2
                $results[0].IsCircular | Should -BeFalse
            }
        }

        It 'Should not report a chain shorter than MinDepth' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @([PSCustomObject]@{ HostName = 'alias'; RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com.' } })
                }

                $results = [PSGDnsCnameChain]::FindCnameChains('localhost', @('contoso.com'), 2, $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should detect a circular CNAME reference regardless of MinDepth' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @(
                        [PSCustomObject]@{ HostName = 'a'; RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'b.contoso.com.' } },
                        [PSCustomObject]@{ HostName = 'b'; RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'a.contoso.com.' } }
                    )
                }

                $results = [PSGDnsCnameChain]::FindCnameChains('localhost', @('contoso.com'), 10, $null)
                $circularResults = @($results | Where-Object -FilterScript { $_.IsCircular })
                $circularResults | Should -HaveCount 2
            }
        }

        It 'Should not follow chains outside the managed zones' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                    @([PSCustomObject]@{ HostName = 'alias'; RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.external.com.' } })
                }

                $results = [PSGDnsCnameChain]::FindCnameChains('localhost', @('contoso.com'), 2, $null)
                $results | Should -HaveCount 0
            }
        }

        It 'Should use CimSession parameter when provided' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsCnameChain]::FindCnameChains('dc01.contoso.com', @('contoso.com'), 2, [PSCustomObject]@{ Id = 1 })

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $null -ne $CimSession } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should use ComputerName parameter when CimSession is null' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                [PSGDnsCnameChain]::FindCnameChains('dc01.contoso.com', @('contoso.com'), 2, $null)

                Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It
            }
        }

        It 'Should return an empty array when there are no CNAME records' {
            InModuleScope $script:moduleName {
                Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }

                $results = [PSGDnsCnameChain]::FindCnameChains('localhost', @('contoso.com'), 2, $null)
                $results | Should -HaveCount 0
            }
        }
    }
}
