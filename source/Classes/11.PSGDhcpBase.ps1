class PSGDhcpBase
{
    # Creates a CimSession for remote execution with credentials. Returns $null for local execution.
    static [object] NewSession([string]$ComputerName, [PSCredential]$Credential)
    {
        if ($null -eq $Credential)
        {
            return $null
        }

        return New-CimSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
    }

    # Removes a CimSession created by NewSession. Safe to call with $null.
    static [void] RemoveSession([object]$CimSession)
    {
        if ($null -ne $CimSession)
        {
            Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
        }
    }

    # Returns all DHCPv4 scopes from the target server.
    static [object[]] GetScopes([string]$ComputerName, [object]$CimSession)
    {
        $params = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        return @(Get-DhcpServerv4Scope @params -ErrorAction Stop)
    }
}
