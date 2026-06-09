class PSGGpo
{
    [string]$Name
    [string]$DistinguishedName
    [string]$Sddl

    hidden [object]$_entry
    hidden [object]$_securityDescriptor

    PSGGpo() {}

    PSGGpo([string]$Name, [string]$DistinguishedName, [object]$Entry)
    {
        $this.Name                 = $Name
        $this.DistinguishedName    = $DistinguishedName
        $this._entry               = $Entry
        $this._securityDescriptor  = $Entry.ObjectSecurity
        $this.Sddl = $this._securityDescriptor.GetSecurityDescriptorSddlForm(
            [System.Security.AccessControl.AccessControlSections]::Access
        )
    }

    # Finds and returns a PSGGpo from Active Directory by display name. Returns $null if not found.
    static [PSGGpo] Get([string]$DisplayName)
    {
        $searcher = [ADSISearcher]"(&(objectClass=groupPolicyContainer)(displayName=$DisplayName))"
        $result   = $searcher.FindOne()

        if (-not $result)
        {
            return $null
        }

        $entry = $result.GetDirectoryEntry()
        return [PSGGpo]::new($DisplayName, [string]$entry.distinguishedName, $entry)
    }

    # Removes all domain computer ACEs from the security filtering SDDL (in memory, call Save() to persist).
    [void] ClearComputerAces()
    {
        $applyGuid        = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $domainSidSegment = "S-1-5-21-\d+-\d+-\d+-\d+"
        $applyAcePattern  = "\(OA;;CR;;$applyGuid;($domainSidSegment)\)"

        $aceMatches = [System.Text.RegularExpressions.Regex]::Matches($this.Sddl, $applyAcePattern)
        $sidsToRemove = $aceMatches |
            ForEach-Object -Process { $_.Groups[1].Value } |
            Select-Object -Unique

        foreach ($sid in $sidsToRemove)
        {
            $escaped   = [System.Text.RegularExpressions.Regex]::Escape($sid)
            $this.Sddl = $this.Sddl -replace "\([^)]+$escaped\)", ""
        }
    }

    # Grants a computer SID the right to apply this GPO by injecting three ACEs (GX + Apply GUID + Read GUID).
    # Any existing ACEs for that SID are replaced to avoid duplicates.
    [void] GrantComputerApplyRight([string]$SidString)
    {
        $applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"

        $escaped   = [System.Text.RegularExpressions.Regex]::Escape($SidString)
        $this.Sddl = $this.Sddl -replace "\([^)]+$escaped\)", ""

        $this.Sddl += "(A;;GX;;;$SidString)"
        $this.Sddl += "(OA;;CR;;$applyGuid;$SidString)"
        $this.Sddl += "(OA;;RP;;$readGuid;$SidString)"
    }

    # Commits the current SDDL to Active Directory in a single transaction.
    [void] Save()
    {
        $this._securityDescriptor.SetSecurityDescriptorSddlForm($this.Sddl)
        $this._entry.ObjectSecurity = $this._securityDescriptor
        $this._entry.CommitChanges()
    }

    [string] ToString()
    {
        return '[PSGGpo] {0} -- DN: {1}' -f $this.Name, $this.DistinguishedName
    }
}
