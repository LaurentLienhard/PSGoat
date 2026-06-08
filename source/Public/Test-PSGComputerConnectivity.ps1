function Test-PSGComputerConnectivity
{
    <#
      .SYNOPSIS
        Tests whether a computer is reachable on the network.

      .DESCRIPTION
        Tests machine reachability using a two-stage probe. First, an ICMP echo (ping)
        is sent. If the target does not respond to ping, TCP connectivity is attempted
        on ports 445 (SMB), 3389 (RDP), and 5985 (WinRM HTTP).

        A machine is considered UP if it responds to ping or if at least one of the
        probed ports is open. Machines that respond to neither are reported as
        Unreachable.

        Each result object includes the computer name, an IsUp boolean, the detection
        method used (Ping, Port, or Unreachable), and individual boolean flags for
        PingSuccess, Port445Open, Port3389Open, and Port5985Open. Port flags are $false
        when ping succeeds (ports are not probed in that case).

        Supports pipeline input to test multiple machines in sequence.

      .PARAMETER ComputerName
        The machine name or IP address to test. Accepts pipeline input. Defaults to
        the local machine.

      .EXAMPLE
        Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'

        Tests a single remote machine.

      .EXAMPLE
        'server01.contoso.com', 'server02.contoso.com' | Test-PSGComputerConnectivity

        Tests multiple machines by piping their names.

      .EXAMPLE
        Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com' |
            Select-Object ComputerName, IsUp, DetectionMethod, Port445Open, Port3389Open, Port5985Open

        Returns a detailed connectivity summary for a machine that did not respond to ping.

      .EXAMPLE
        Get-ADComputer -Filter * | Select-Object -ExpandProperty DNSHostName |
            Test-PSGComputerConnectivity |
            Where-Object -FilterScript { -not $_.IsUp }

        Identifies all unreachable AD computers.
    #>
    [CmdletBinding()]
    [OutputType([PSGComputer])]
    param
    (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $ComputerName = $env:COMPUTERNAME
    )

    process
    {
        Write-Verbose ('Testing connectivity to {0}' -f $ComputerName)
        [PSGComputer]::TestConnectivity($ComputerName)
    }
}
