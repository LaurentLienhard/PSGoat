BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'PSGLogger' {
    Context 'Console-only constructor' {
        It 'Should set ServiceName correctly' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.ServiceName | Should -Be 'PSGoat'
            }
        }

        It 'Should set ServiceVersion correctly' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.ServiceVersion | Should -Be '1.0.0'
            }
        }

        It 'Should set FileLoggingEnabled to false' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.FileLoggingEnabled | Should -BeFalse
            }
        }

        It 'Should generate a non-empty TraceId' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.TraceId | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should generate a 32-character TraceId' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.TraceId.Length | Should -Be 32
            }
        }

        It 'Should generate a 16-character SpanId' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.SpanId.Length | Should -Be 16
            }
        }

        It 'Should generate unique TraceIds per instance' {
            InModuleScope $script:moduleName {
                $logger1 = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger2 = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger1.TraceId | Should -Not -Be $logger2.TraceId
            }
        }
    }

    Context 'Console and file constructor' {
        It 'Should set LogFilePath correctly' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.LogFilePath | Should -Be 'C:\Logs\test.log'
            }
        }

        It 'Should set FileLoggingEnabled to true' {
            InModuleScope $script:moduleName {
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.FileLoggingEnabled | Should -BeTrue
            }
        }
    }

    Context 'Info method' {
        It 'Should call Write-Verbose' {
            InModuleScope $script:moduleName {
                Mock -CommandName Write-Verbose -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.Info('Test message')
                Should -Invoke -CommandName Write-Verbose -Exactly -Times 1 -Scope It
            }
        }

        It 'Should not call Add-Content when FileLoggingEnabled is false' {
            InModuleScope $script:moduleName {
                Mock -CommandName Add-Content -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.Info('Test message')
                Should -Invoke -CommandName Add-Content -Exactly -Times 0 -Scope It
            }
        }

        It 'Should call Add-Content when FileLoggingEnabled is true' {
            InModuleScope $script:moduleName {
                Mock -CommandName Add-Content -MockWith {}
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                Should -Invoke -CommandName Add-Content -Exactly -Times 1 -Scope It
            }
        }

        It 'Should write valid JSON to file' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                { $captured | ConvertFrom-Json } | Should -Not -Throw
            }
        }

        It 'Should write severityText INFO to the log record' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                ($captured | ConvertFrom-Json).severityText | Should -Be 'INFO'
            }
        }

        It 'Should write severityNumber 9 to the log record' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                ($captured | ConvertFrom-Json).severityNumber | Should -Be 9
            }
        }

        It 'Should include attributes in the log record' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message', @{ 'dns.zone' = 'contoso.com' })
                ($captured | ConvertFrom-Json).attributes.'dns.zone' | Should -Be 'contoso.com'
            }
        }
    }

    Context 'Debug method' {
        It 'Should call Write-Debug' {
            InModuleScope $script:moduleName {
                Mock -CommandName Write-Debug -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.Debug('Test message')
                Should -Invoke -CommandName Write-Debug -Exactly -Times 1 -Scope It
            }
        }

        It 'Should write severityText DEBUG and severityNumber 5' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Debug('Test message')
                $record = $captured | ConvertFrom-Json
                $record.severityText   | Should -Be 'DEBUG'
                $record.severityNumber | Should -Be 5
            }
        }
    }

    Context 'Warn method' {
        It 'Should call Write-Warning' {
            InModuleScope $script:moduleName {
                Mock -CommandName Write-Warning -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.Warn('Test message')
                Should -Invoke -CommandName Write-Warning -Exactly -Times 1 -Scope It
            }
        }

        It 'Should write severityText WARN and severityNumber 13' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Warn('Test message')
                $record = $captured | ConvertFrom-Json
                $record.severityText   | Should -Be 'WARN'
                $record.severityNumber | Should -Be 13
            }
        }
    }

    Context 'Error method' {
        It 'Should call Write-Error' {
            InModuleScope $script:moduleName {
                Mock -CommandName Write-Error -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0')
                $logger.Error('Test message')
                Should -Invoke -CommandName Write-Error -Exactly -Times 1 -Scope It
            }
        }

        It 'Should write severityText ERROR and severityNumber 17' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Error('Test message')
                $record = $captured | ConvertFrom-Json
                $record.severityText   | Should -Be 'ERROR'
                $record.severityNumber | Should -Be 17
            }
        }
    }

    Context 'Log record structure' {
        It 'Should include the service name in the resource block' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                ($captured | ConvertFrom-Json).resource.'service.name' | Should -Be 'PSGoat'
            }
        }

        It 'Should include the service version in the resource block' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                ($captured | ConvertFrom-Json).resource.'service.version' | Should -Be '1.0.0'
            }
        }

        It 'Should include a non-empty traceId' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                ($captured | ConvertFrom-Json).traceId | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should include the message as the body' {
            InModuleScope $script:moduleName {
                $captured = $null
                Mock -CommandName Add-Content -MockWith { $captured = $Value }
                Mock -CommandName Test-Path -MockWith { $false }
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Hello from PSGoat')
                ($captured | ConvertFrom-Json).body | Should -Be 'Hello from PSGoat'
            }
        }
    }

    Context 'Log rotation' {
        It 'Should call Move-Item when the log file exceeds MaxFileSizeBytes' {
            InModuleScope $script:moduleName {
                Mock -CommandName Add-Content -MockWith {}
                Mock -CommandName Test-Path -MockWith { $true }
                Mock -CommandName Get-Item -MockWith {
                    [PSCustomObject]@{ Length = 11MB }
                }
                Mock -CommandName Move-Item -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                Should -Invoke -CommandName Move-Item -Exactly -Times 1 -Scope It
            }
        }

        It 'Should not call Move-Item when the log file is within size limit' {
            InModuleScope $script:moduleName {
                Mock -CommandName Add-Content -MockWith {}
                Mock -CommandName Test-Path -MockWith { $true }
                Mock -CommandName Get-Item -MockWith {
                    [PSCustomObject]@{ Length = 1MB }
                }
                Mock -CommandName Move-Item -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                Should -Invoke -CommandName Move-Item -Exactly -Times 0 -Scope It
            }
        }

        It 'Should not call Move-Item when the log file does not exist' {
            InModuleScope $script:moduleName {
                Mock -CommandName Add-Content -MockWith {}
                Mock -CommandName Test-Path -MockWith { $false }
                Mock -CommandName Move-Item -MockWith {}
                $logger = [PSGLogger]::new('PSGoat', '1.0.0', 'C:\Logs\test.log')
                $logger.Info('Test message')
                Should -Invoke -CommandName Move-Item -Exactly -Times 0 -Scope It
            }
        }
    }
}
