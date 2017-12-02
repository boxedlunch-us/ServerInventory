function Get-BayNumber{
    param(
    $MAC
    )
    #get inventory of rack - currently just E2 Prod

    #connect to OA of enclosure
    $OA = Connect-HPOA -Username Administrator -Password 'pasword' -OA 'OA_IP_Address'
    
    #get installed blade servers per enclosure
    $serverlist = Get-HPOAServerInfo -Connection $oa
    $serverlist = $serverlist.ServerBlade | Where-Object{$_.bladestatus -ne 'No Server Blade Installed'}

    $bay = $serverlist | Where-Object{$_.flexfabricembeddedethernet -match $mac}

    return $bay.bay

}