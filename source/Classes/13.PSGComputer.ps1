class PSGComputer
{
    [string]$ComputerName
    [bool]$IsUp

    PSGComputer() {}

    PSGComputer([string]$ComputerName, [bool]$IsUp)
    {
        $this.ComputerName = $ComputerName
        $this.IsUp         = $IsUp
    }

    # Returns $true if the target responds to ICMP echo.
    static [bool] TestPing([string]$ComputerName)
    {
        try
        {
            return [bool](Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop)
        }
        catch
        {
            return $false
        }
    }

    # Returns $true if a TCP connection to the given port succeeds (PS7+ Test-Connection -TcpPort).
    static [bool] TestPort([string]$ComputerName, [int]$Port)
    {
        try
        {
            return [bool](Test-Connection -ComputerName $ComputerName -TcpPort $Port -Count 1 -Quiet -ErrorAction Stop)
        }
        catch
        {
            return $false
        }
    }

    # Tests machine reachability: ping first, then ports 445/3389/5985 if ping fails.
    static [PSGComputer] TestConnectivity([string]$ComputerName)
    {
        if ([PSGComputer]::TestPing($ComputerName))
        {
            Write-Verbose ('[PSGComputer] {0} responded to ping' -f $ComputerName)
            return [PSGComputer]::new($ComputerName, $true)
        }

        Write-Verbose ('[PSGComputer] {0}: ping failed, testing ports 445/3389/5985' -f $ComputerName)

        $reachable = [PSGComputer]::TestPort($ComputerName, 445) -or
                     [PSGComputer]::TestPort($ComputerName, 3389) -or
                     [PSGComputer]::TestPort($ComputerName, 5985)

        Write-Verbose ('[PSGComputer] {0}: IsUp={1}' -f $ComputerName, $reachable)

        return [PSGComputer]::new($ComputerName, $reachable)
    }

    [string] ToString()
    {
        return '[PSGComputer] {0} -- IsUp: {1}' -f $this.ComputerName, $this.IsUp
    }
}
