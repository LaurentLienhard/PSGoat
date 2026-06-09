function Remove-GPOComputerAce
{
    <#
    .SYNOPSIS
        Supprime toutes les ACE de type ordinateur (domaine) d'une chaîne SDDL de GPO.
    .DESCRIPTION
        Identifie les SIDs de domaine présents dans les ACE "Apply GPO" de la chaîne SDDL
        fournie et supprime l'ensemble des entrées d'accès (GX, CR, RP) associées à ces SIDs.
        Seuls les SIDs de comptes de domaine (S-1-5-21-...) sont ciblés afin de préserver
        les principaux de sécurité intégrés (Authenticated Users, Domain Computers, etc.).
    .PARAMETER Sddl
        Chaîne SDDL de la GPO dont les ACE ordinateur doivent être supprimées.
    .EXAMPLE
        $sddlNettoyee = Remove-GPOComputerAce -Sddl $sddlActuelle
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]$Sddl
    )

    $gpoApplyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
    $domainSidSegment = "S-1-5-21-\d+-\d+-\d+-\d+"

    $applyAcePattern = "\(OA;;CR;;$gpoApplyGuid;($domainSidSegment)\)"
    $applyMatches = [System.Text.RegularExpressions.Regex]::Matches($Sddl, $applyAcePattern)

    $sidsToRemove = $applyMatches |
        ForEach-Object -Process { $_.Groups[1].Value } |
        Select-Object -Unique

    foreach ($sid in $sidsToRemove)
    {
        $escapedSid = [System.Text.RegularExpressions.Regex]::Escape($sid)
        $Sddl = $Sddl -replace "\([^)]+$escapedSid\)", ""
        Write-Verbose -Message "ACE supprimée pour le SID : $sid"
    }

    return $Sddl
}
