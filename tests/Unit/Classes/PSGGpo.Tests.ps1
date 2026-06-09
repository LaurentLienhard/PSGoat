BeforeAll {
    $script:classPath = "$PSScriptRoot/../../../source/Classes/1.PSGGpo.ps1"
    . $script:classPath
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
            $gpo.DistinguishedName | Should -BeNullOrEmpty
            $gpo.Sddl              | Should -BeNullOrEmpty
        }
    }

    Context "ToString()" {
        It "Retourne une représentation lisible" {
            $gpo = [PSGGpo]::new()
            $gpo.Name              = "TestGPO"
            $gpo.DistinguishedName = "CN=TestGPO,DC=test,DC=local"
            $gpo.ToString() | Should -Be "[PSGGpo] TestGPO -- DN: CN=TestGPO,DC=test,DC=local"
        }
    }

    Context "ClearComputerAces()" {
        It "Supprime les 3 ACE d'un ordinateur connu" {
            $aceGX = "(A;;GX;;;$script:sid1)"
            $aceCR = "(OA;;CR;;$script:applyGuid;$script:sid1)"
            $aceRP = "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = "$script:sddlBase$aceGX$aceCR$aceRP"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
        }

        It "Préserve les ACE non ordinateur (ex: Authenticated Users)" {
            $aceAU = "(A;;LCRPLORC;;;S-1-5-11)"
            $aceCR = "(OA;;CR;;$script:applyGuid;$script:sid1)"
            $aceGX = "(A;;GX;;;$script:sid1)"
            $aceRP = "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = "$script:sddlBase$aceAU$aceGX$aceCR$aceRP"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Match "\(A;;LCRPLORC;;;S-1-5-11\)"
        }

        It "Supprime plusieurs ordinateurs en une seule passe" {
            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)" +
                "(A;;GX;;;$script:sid2)" +
                "(OA;;CR;;$script:applyGuid;$script:sid2)" +
                "(OA;;RP;;$script:readGuid;$script:sid2)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }

        It "Laisse le SDDL inchangé si aucun ordinateur n'est présent" {
            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = "$script:sddlBase(A;;LCRPLORC;;;S-1-5-11)"

            $before = $gpo.Sddl
            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Be $before
        }
    }

    Context "GrantComputerApplyRight()" {
        It "Ajoute les 3 ACE (GX, Apply GUID, Read GUID) pour un SID" {
            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = $script:sddlBase

            $gpo.GrantComputerApplyRight($script:sid1)

            $gpo.Sddl | Should -Match "\(A;;GX;;;$([regex]::Escape($script:sid1))\)"
            $gpo.Sddl | Should -Match "\(OA;;CR;;$script:applyGuid;$([regex]::Escape($script:sid1))\)"
            $gpo.Sddl | Should -Match "\(OA;;RP;;$script:readGuid;$([regex]::Escape($script:sid1))\)"
        }

        It "Remplace les ACE existantes pour éviter les doublons" {
            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.GrantComputerApplyRight($script:sid1)

            $applyAceCount = ([System.Text.RegularExpressions.Regex]::Matches(
                $gpo.Sddl,
                "\(OA;;CR;;$script:applyGuid;$([regex]::Escape($script:sid1))\)"
            )).Count

            $applyAceCount | Should -Be 1
        }

        It "N'affecte pas les ACE des autres SIDs" {
            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid2)" +
                "(OA;;CR;;$script:applyGuid;$script:sid2)"

            $gpo.GrantComputerApplyRight($script:sid1)

            $gpo.Sddl | Should -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }
    }

    Context "ClearComputerAces() puis GrantComputerApplyRight()" {
        It "Repart d'un filtrage propre et ajoute uniquement les SIDs demandés" {
            $gpo      = [PSGGpo]::new()
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.ClearComputerAces()
            $gpo.GrantComputerApplyRight($script:sid2)

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $gpo.Sddl | Should -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }
    }
}
