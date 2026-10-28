Set-StrictMode -Version Latest
# System-wide ad and tracker blocking for every app and game launcher: Windows uses AdGuard DNS (free, no
# account; blocks ad, tracker and analytics domains) over encrypted DNS-over-HTTPS. The DNS servers each
# network adapter had before are saved and put back by Disable-BakaAdBlockDns or "Restore BAKA System Tuning".

$script:Providers=@{
    AdGuard=[pscustomobject]@{
        Name='AdGuard DNS'
        IPv4=@('94.140.14.14','94.140.15.15'); IPv6=@('2a10:50c0::ad1:ff','2a10:50c0::ad2:ff')
        Template='https://dns.adguard-dns.com/dns-query'
    }
}
function Get-BakaAdBlockDnsStatePath { Join-Path $env:ProgramData 'BAKA\AdBlockDnsBackup.json' }

function Get-BakaDnsAdapters {
    # Physical and Wi-Fi adapters that are up; VPN, Hyper-V and loopback adapters are left alone.
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
}

function Enable-BakaAdBlockDns {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([ValidateSet('AdGuard')][string]$Provider='AdGuard')
    $p=$script:Providers[$Provider]
    if(-not $PSCmdlet.ShouldProcess($p.Name,'Use encrypted ad-blocking DNS')){return}
    $statePath=Get-BakaAdBlockDnsStatePath
    $state=if(Test-Path -LiteralPath $statePath){Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json}else{$null}
    $saved=@{}
    if($state){foreach($a in @($state.Adapters)){$saved[[string]$a.InterfaceAlias]=$a}}
    # Windows only encrypts DNS to servers it has a DoH template for.
    foreach($server in @($p.IPv4+$p.IPv6)){
        try{
            if(-not (Get-DnsClientDohServerAddress -ServerAddress $server -ErrorAction SilentlyContinue)){
                Add-DnsClientDohServerAddress -ServerAddress $server -DohTemplate $p.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop|Out-Null
            }else{Set-DnsClientDohServerAddress -ServerAddress $server -DohTemplate $p.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop|Out-Null}
        }catch{Write-Verbose "DoH template for $server not set: $($_.Exception.Message)"}
    }
    $changed=@()
    foreach($adapter in Get-BakaDnsAdapters){
        $alias=$adapter.InterfaceAlias
        if(-not $saved.ContainsKey($alias)){
            $v4=@((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
            $v6=@((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses)
            # An adapter that was on automatic (DHCP) DNS goes back to automatic.
            $dhcp=((Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp -eq 'Enabled') -and -not (Get-ItemProperty -LiteralPath ("HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}" -f $adapter.InterfaceGuid) -Name NameServer -ErrorAction SilentlyContinue).NameServer
            $saved[$alias]=[pscustomobject]@{InterfaceAlias=$alias;Automatic=[bool]$dhcp;IPv4=$v4;IPv6=$v6}
        }
        try{
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($p.IPv4+$p.IPv6) -ErrorAction Stop
            $changed+=$alias
        }catch{Write-Verbose "DNS for $alias not changed: $($_.Exception.Message)"}
    }
    $out=[pscustomobject]@{Provider=$Provider;EnabledAt=(Get-Date).ToString('o');Adapters=@($saved.Values)}
    New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force|Out-Null
    $out|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $statePath -Encoding UTF8
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    [pscustomobject]@{Enabled=$true;Provider=$p.Name;Adapters=$changed}
}

function Disable-BakaAdBlockDns {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    $statePath=Get-BakaAdBlockDnsStatePath
    if(-not (Test-Path -LiteralPath $statePath)){return [pscustomobject]@{Enabled=$false;Restored=@()}}
    if(-not $PSCmdlet.ShouldProcess('DNS servers','Restore the previous DNS settings')){return}
    $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
    $restored=@()
    foreach($a in @($state.Adapters)){
        $adapter=Get-NetAdapter -Name $a.InterfaceAlias -ErrorAction SilentlyContinue
        if(-not $adapter){continue}
        try{
            if($a.Automatic -or -not (@($a.IPv4)+@($a.IPv6)).Count){Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop}
            else{Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @(@($a.IPv4)+@($a.IPv6)) -ErrorAction Stop}
            $restored+=$a.InterfaceAlias
        }catch{Write-Verbose "DNS for $($a.InterfaceAlias) not restored: $($_.Exception.Message)"}
    }
    Remove-Item -LiteralPath $statePath -Force
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    [pscustomobject]@{Enabled=$false;Restored=$restored}
}

function Get-BakaAdBlockDnsStatus {
    $statePath=Get-BakaAdBlockDnsStatePath
    [pscustomobject]@{Enabled=(Test-Path -LiteralPath $statePath);StatePath=$statePath}
}

Export-ModuleMember -Function Enable-BakaAdBlockDns,Disable-BakaAdBlockDns,Get-BakaAdBlockDnsStatus,Get-BakaDnsAdapters
