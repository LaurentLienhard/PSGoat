function Sync-ZephyrToGPOFilteringSDDL
{
    <#
    .SYNOPSIS
        Synchronise le filtrage de sécurité d'une GPO avec la liste des ordinateurs Zephyr.
    .DESCRIPTION
        Supprime d'abord tous les ordinateurs de domaine présents dans le filtrage de sécurité
        de la GPO cible, puis ajoute les postes retournés par l'API Zephyr dont le statut
        correspond au statut cible, dans la limite du nombre maximum spécifié.

        Les trois ACE nécessaires à l'application d'une GPO sont injectées pour chaque ordinateur :
          - (A;;GX;;;SID)                                  — Generic Execute
          - (OA;;CR;;edacfd8f-ffb3-11d1-b41d-00a4ec21a286;SID) — Apply Group Policy
          - (OA;;RP;;e47a4747-e549-11d1-bc91-00a4ec21a286;SID) — Read Group Policy

        Les modifications sont appliquées en une seule transaction Active Directory.
    .PARAMETER BaseApiUrl
        URL de base de l'API Zephyr.
    .PARAMETER TargetGPOName
        Nom d'affichage (displayName) de la GPO cible dans Active Directory.
    .PARAMETER TargetStatus
        Valeur du champ step_2_status filtrée sur l'API Zephyr. Par défaut : 1.
    .PARAMETER MaxComputers
        Nombre maximum d'ordinateurs à injecter dans le filtrage de sécurité.
        Permet de ne pas dépasser la limite opérationnelle de la GPO.
    .EXAMPLE
        Sync-ZephyrToGPOFilteringSDDL -MaxComputers 50

        Vide le filtrage existant et ajoute jusqu'à 50 ordinateurs depuis Zephyr.
    .EXAMPLE
        Sync-ZephyrToGPOFilteringSDDL -TargetGPOName "MY - GPO - Name" -MaxComputers 100 -WhatIf

        Simule la synchronisation sans appliquer de changements dans l'AD.
    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param
    (
        [Parameter()]
        [String]$BaseApiUrl = "http://caw1tzephyr01.fmlogistic.fr:8000/computers",

        [Parameter()]
        [String]$TargetGPOName = "ALL - WKS - CatoClient-Install",

        [Parameter()]
        [Int]$TargetStatus = 1,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [Int]::MaxValue)]
        [Int]$MaxComputers
    )

    $gpoApplyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
    $gpoReadGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"

    try
    {
        # Localisation de la GPO dans Active Directory
        $gpoSearcher = [ADSISearcher]"(&(objectClass=groupPolicyContainer)(displayName=$TargetGPOName))"
        $gpoSearchResult = $gpoSearcher.FindOne()

        if (-not $gpoSearchResult)
        {
            Write-Error -Message "GPO introuvable dans Active Directory : '$TargetGPOName'."
            return
        }

        $gpoEntry = $gpoSearchResult.GetDirectoryEntry()
        Write-Verbose -Message "GPO trouvée : $($gpoEntry.distinguishedName)"

        $gpoSecurityDescriptor = $gpoEntry.ObjectSecurity
        $currentSddl = $gpoSecurityDescriptor.GetSecurityDescriptorSddlForm(
            [System.Security.AccessControl.AccessControlSections]::Access
        )

        # Suppression de tous les ordinateurs existants dans le filtrage
        Write-Verbose -Message "Suppression des ordinateurs existants du filtrage de sécurité..."
        $currentSddl = Remove-GPOComputerAce -Sddl $currentSddl
        Write-Verbose -Message "Filtrage de sécurité nettoyé."

        # Récupération de la liste des machines depuis l'API Zephyr
        $listUrl = "$BaseApiUrl/list/2"
        Write-Verbose -Message "Interrogation de l'API Zephyr : $listUrl"
        $computersList = Invoke-RestMethod -Uri $listUrl -Method Get -TimeoutSec 10 -ErrorAction Stop

        if (-not $computersList)
        {
            Write-Warning -Message "Aucun ordinateur retourné par l'API Zephyr."
            return
        }

        Write-Verbose -Message "$($computersList.Count) postes récupérés — statut cible : $TargetStatus — limite : $MaxComputers"

        $addedCount = 0

        foreach ($pcName in $computersList)
        {
            if ($addedCount -ge $MaxComputers)
            {
                Write-Warning -Message "Limite de $MaxComputers ordinateurs atteinte. Fin de l'injection."
                break
            }

            try
            {
                $details = Invoke-RestMethod -Uri "$BaseApiUrl/$pcName" -Method Get -TimeoutSec 3 -ErrorAction Stop

                if ($details.step_2_status -ne $TargetStatus)
                {
                    continue
                }

                $computerSearcher = [ADSISearcher]"(&(objectClass=computer)(sAMAccountName=$pcName$))"
                $computerResult = $computerSearcher.FindOne()

                if (-not $computerResult)
                {
                    Write-Warning -Message "Ordinateur '$pcName' introuvable dans Active Directory."
                    continue
                }

                $computerEntry = $computerResult.GetDirectoryEntry()
                $computerSid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList (
                    $computerEntry.Properties.objectSid[0], 0
                )
                $sidString = $computerSid.Value

                $aceGX = "(A;;GX;;;$sidString)"
                $aceCR = "(OA;;CR;;$gpoApplyGuid;$sidString)"
                $aceRP = "(OA;;RP;;$gpoReadGuid;$sidString)"

                $currentSddl = $currentSddl + $aceGX + $aceCR + $aceRP
                $addedCount++

                Write-Verbose -Message "[$addedCount/$MaxComputers] Injecté : $pcName ($sidString)"
            }
            catch
            {
                Write-Warning -Message "Erreur lors du traitement de '$pcName' : $($_.Exception.Message)"
                continue
            }
        }

        # Application des changements dans Active Directory (transaction unique)
        if ($PSCmdlet.ShouldProcess($TargetGPOName, "Mise à jour du filtrage de sécurité GPO ($addedCount ordinateur(s) injecté(s))"))
        {
            $gpoSecurityDescriptor.SetSecurityDescriptorSddlForm($currentSddl)
            $gpoEntry.ObjectSecurity = $gpoSecurityDescriptor
            $gpoEntry.CommitChanges()
            Write-Verbose -Message "Synchronisation réussie : $addedCount ordinateur(s) injecté(s) dans '$TargetGPOName'."
        }
    }
    catch
    {
        Write-Error -Message "Erreur critique lors de la synchronisation : $($_.Exception.Message)"
    }
}
