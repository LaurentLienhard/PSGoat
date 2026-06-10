BeforeAll {
    . "$PSScriptRoot/../../../source/Classes/1.PSGGpo.ps1"

    function New-MockEntry
    {
        param([int]$Flags = 0)

        $props = @{
            flags           = [PSCustomObject]@{ Value = $Flags }
            gPCFileSysPath  = [PSCustomObject]@{ Value = "\\domain\sysvol\Policies\{TEST-GUID}" }
        }

        $secDescriptor = [PSCustomObject]@{}
        Add-Member -InputObject $secDescriptor -MemberType ScriptMethod -Name GetSecurityDescriptorSddlForm -Value {
            return "O:DAG:DAD:P"
        }
        Add-Member -InputObject $secDescriptor -MemberType ScriptMethod -Name SetSecurityDescriptorSddlForm -Value {
            param([string]$s)
        }

        $entry = [PSCustomObject]@{
            distinguishedName = "CN={TEST-GUID},CN=Policies,CN=System,DC=test,DC=local"
            ObjectSecurity    = $secDescriptor
            Properties        = $props
        }
        Add-Member -InputObject $entry -MemberType ScriptMethod -Name CommitChanges -Value {}

        return $entry
    }

    function New-MockGpo
    {
        param([int]$Flags = 0)

        $entry = New-MockEntry -Flags $Flags
        $gpo   = [PSGGpo]::new(
            "TestGPO",
            "{TEST-GUID}",
            "CN={TEST-GUID},CN=Policies,CN=System,DC=test,DC=local",
            "\\domain\sysvol\Policies\{TEST-GUID}",
            $Flags,
            $entry
        )
        return $gpo
    }
}

Describe "PSGGpo" {
    BeforeAll {
        $script:applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $script:readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"
        $script:sid1      = "S-1-5-21-1234567890-987654321-111111111-1001"
        $script:sid2      = "S-1-5-21-1234567890-987654321-111111111-1002"
        $script:sddlBase  = "O:DAG:DAD:P"
    }

    Context "Constructeur par défaut" {
        It "Crée une instance avec des propriétés vides" {
            $gpo = [PSGGpo]::new()
            $gpo.Name              | Should -BeNullOrEmpty
            $gpo.Id                | Should -BeNullOrEmpty
            $gpo.DistinguishedName | Should -BeNullOrEmpty
            $gpo.SysvolPath        | Should -BeNullOrEmpty
            $gpo.Flags             | Should -Be 0
        }
    }

    Context "ToString()" {
        It "Retourne le nom, l'Id, les flags et le DN" {
            $gpo = New-MockGpo
            $gpo.ToString() | Should -Match "TestGPO"
            $gpo.ToString() | Should -Match "\{TEST-GUID\}"
            $gpo.ToString() | Should -Match "DN:"
        }
    }

    Context "Enable() / Disable()" {
        It "Enable() positionne Flags à 0 et met à jour la propriété" {
            $gpo = New-MockGpo -Flags 3
            $gpo.Enable()
            $gpo.Flags | Should -Be 0
        }

        It "Disable() positionne Flags à 3 et met à jour la propriété" {
            $gpo = New-MockGpo -Flags 0
            $gpo.Disable()
            $gpo.Flags | Should -Be 3
        }
    }

    Context "DisableUserSettings() / EnableUserSettings()" {
        It "DisableUserSettings() active le bit 0" {
            $gpo = New-MockGpo -Flags 0
            $gpo.DisableUserSettings()
            $gpo.Flags | Should -Be 1
        }

        It "EnableUserSettings() efface le bit 0 sans toucher au bit 1" {
            $gpo = New-MockGpo -Flags 3
            $gpo.EnableUserSettings()
            $gpo.Flags | Should -Be 2
        }

        It "EnableUserSettings() sur GPO déjà active laisse Flags à 0" {
            $gpo = New-MockGpo -Flags 0
            $gpo.EnableUserSettings()
            $gpo.Flags | Should -Be 0
        }
    }

    Context "DisableComputerSettings() / EnableComputerSettings()" {
        It "DisableComputerSettings() active le bit 1" {
            $gpo = New-MockGpo -Flags 0
            $gpo.DisableComputerSettings()
            $gpo.Flags | Should -Be 2
        }

        It "EnableComputerSettings() efface le bit 1 sans toucher au bit 0" {
            $gpo = New-MockGpo -Flags 3
            $gpo.EnableComputerSettings()
            $gpo.Flags | Should -Be 1
        }

        It "EnableComputerSettings() sur GPO déjà active laisse Flags à 0" {
            $gpo = New-MockGpo -Flags 0
            $gpo.EnableComputerSettings()
            $gpo.Flags | Should -Be 0
        }
    }

    Context "AddLink() / RemoveLink()" {
        BeforeEach {
            $script:ouProps = @{ gPLink = [PSCustomObject]@{ Value = "" } }
            $script:ouEntry = [PSCustomObject]@{ Properties = $script:ouProps }
            Add-Member -InputObject $script:ouEntry -MemberType ScriptMethod -Name CommitChanges -Value {}
        }

        It "AddLink() ajoute l'entrée dans gPLink si absente" {
            $gpo = New-MockGpo

            Mock -CommandName ADSI -MockWith { return $script:ouEntry }

            $gpo.AddLink("OU=TestOU,DC=test,DC=local")

            $script:ouEntry.Properties['gPLink'].Value | Should -Match [System.Text.RegularExpressions.Regex]::Escape($gpo.DistinguishedName)
        }

        It "AddLink() n'ajoute pas de doublon si déjà lié" {
            $gpo = New-MockGpo
            $script:ouEntry.Properties['gPLink'].Value = "[LDAP://$($gpo.DistinguishedName);0]"

            $gpo.AddLink("OU=TestOU,DC=test,DC=local")

            $count = ([regex]::Matches($script:ouEntry.Properties['gPLink'].Value, [regex]::Escape($gpo.Id))).Count
            $count | Should -Be 1
        }

        It "RemoveLink() retire l'entrée de gPLink" {
            $gpo = New-MockGpo
            $script:ouEntry.Properties['gPLink'].Value = "[LDAP://$($gpo.DistinguishedName);0]"

            $gpo.RemoveLink("OU=TestOU,DC=test,DC=local")

            $script:ouEntry.Properties['gPLink'].Value | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($gpo.Id)
        }

        It "RemoveLink() préserve les autres liens présents" {
            $gpo    = New-MockGpo
            $otherId = "{OTHER-GUID}"
            $script:ouEntry.Properties['gPLink'].Value = "[LDAP://CN=$otherId,CN=Policies,DC=test;0][LDAP://$($gpo.DistinguishedName);0]"

            $gpo.RemoveLink("OU=TestOU,DC=test,DC=local")

            $script:ouEntry.Properties['gPLink'].Value | Should -Match [System.Text.RegularExpressions.Regex]::Escape($otherId)
        }
    }

    Context "ClearComputerAces()" {
        It "Supprime les 3 ACE d'un ordinateur" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
        }

        It "Préserve les ACE non ordinateur" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(A;;LCRPLORC;;;S-1-5-11)" +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Match "\(A;;LCRPLORC;;;S-1-5-11\)"
        }

        It "Supprime plusieurs ordinateurs en une seule passe" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid2)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }
    }

    Context "GrantComputerApplyRight()" {
        It "Ajoute les 3 ACE pour un SID" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase

            $gpo.GrantComputerApplyRight($script:sid1)

            $gpo.Sddl | Should -Match "\(A;;GX;;;$([regex]::Escape($script:sid1))\)"
            $gpo.Sddl | Should -Match "\(OA;;CR;;$script:applyGuid;$([regex]::Escape($script:sid1))\)"
            $gpo.Sddl | Should -Match "\(OA;;RP;;$script:readGuid;$([regex]::Escape($script:sid1))\)"
        }

        It "Remplace les ACE existantes (pas de doublon)" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.GrantComputerApplyRight($script:sid1)

            $count = ([regex]::Matches($gpo.Sddl, "\(OA;;CR;;$script:applyGuid;$([regex]::Escape($script:sid1))\)")).Count
            $count | Should -Be 1
        }
    }

    Context "ClearComputerAces() puis GrantComputerApplyRight()" {
        It "Repart d'un filtrage propre et injecte uniquement le nouveau SID" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(OA;;CR;;$script:applyGuid;$script:sid1)"

            $gpo.ClearComputerAces()
            $gpo.GrantComputerApplyRight($script:sid2)

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $gpo.Sddl | Should -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }
    }
}
