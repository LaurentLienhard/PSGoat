class PSGComputer
{
    [string]$ComputerName
    [bool]$IsUp
    [string]$DetectionMethod
    [bool]$PingSuccess
    [bool]$Port445Open
    [bool]$Port3389Open
    [bool]$Port5985Open

    PSGComputer() {}

    PSGComputer(
        [string]$ComputerName,
        [bool]$IsUp,
        [string]$DetectionMethod,
        [bool]$PingSuccess,
        [bool]$Port445Open,
        [bool]$Port3389Open,
        [bool]$Port5985Open
    )
    {
        $this.ComputerName    = $ComputerName
        $this.IsUp            = $IsUp
        $this.DetectionMethod = $DetectionMethod
        $this.PingSuccess     = $PingSuccess
        $this.Port445Open     = $Port445Open
        $this.Port3389Open    = $Port3389Open
        $this.Port5985Open    = $Port5985Open
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
        $pingOk = [PSGComputer]::TestPing($ComputerName)

        if ($pingOk)
        {
            Write-Verbose ('[PSGComputer] {0} responded to ping' -f $ComputerName)
            return [PSGComputer]::new($ComputerName, $true, 'Ping', $true, $false, $false, $false)
        }

        Write-Verbose ('[PSGComputer] {0}: ping failed, testing ports 445/3389/5985' -f $ComputerName)

        $p445  = [PSGComputer]::TestPort($ComputerName, 445)
        $p3389 = [PSGComputer]::TestPort($ComputerName, 3389)
        $p5985 = [PSGComputer]::TestPort($ComputerName, 5985)

        $reachable = $p445 -or $p3389 -or $p5985
        $method    = if ($reachable) { 'Port' } else { 'Unreachable' }

        Write-Verbose ('[PSGComputer] {0}: Port 445={1} 3389={2} 5985={3} -- IsUp={4}' -f $ComputerName, $p445, $p3389, $p5985, $reachable)

        return [PSGComputer]::new($ComputerName, $reachable, $method, $false, $p445, $p3389, $p5985)
    }

    [string] ToString()
    {
        return '[PSGComputer] {0} -- IsUp: {1} ({2})' -f $this.ComputerName, $this.IsUp, $this.DetectionMethod
    }
}
