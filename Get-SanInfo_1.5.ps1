Import-Module DataONTAP

function Get-SanInfo{
    param(
    $controllerName
    )

    #function to create SAN object for append to serverlist
    function Set-SanObject{
    param
    (
        $nodetype,
        $hostname,
        $ip,
        $OS,
        $notes,
        $model,
        $cluster,
        $WWPN,
        $WWNN,
        $current_host
    )
    
    $object = New-Object psobject -Property @{

        current_host = $current_host
        node_type = $nodetype
        hostname = $hostname
        ip_address = $ip
        OS_version = $OS
        notes = $notes
        model = $model
        cluster = $cluster
        WWPN = $WWPN
        WWNN = $WWNN




    }

    return $object

}

    #connect to NetApp SAN COntroller
    $conn = Connect-NaController -Name $controllerName

    $hostname = $conn.name

    #get interface info, create an array to store values, join into string with semicolon
    $net = Get-NaNetInterface -Controller $conn | Where-Object{$_.PrimaryAddresses -ne ""}
    [array]$ipArray = $null
    $net|ForEach-Object{$iparray += $_.Interface.ToString() + " " + $_.PrimaryAddresses.tostring()}
    $ip = $ipArray -join '; '

    #Trim OS version using regex
    $OSVersion = $conn.Version -replace '\:.*$'

    #Get the model of the filer using nasysteminfo
    $model = Get-NaSystemInfo -Controller $conn
    $model = $model.SystemModel

    #get fc wwpn
    $wwpn = Get-NaFcpPortName -Controller $conn
    $wwpn = $wwpn | Where-Object{$_.isused -eq $true}
    $wwpn = $wwpn | ForEach-Object{$_.FcpAdapter + ": " + $_.PortName}
    $wwpn = $wwpn -join '; '

    #get fcp node name
    $wwnn = Get-NaFcpNodeName -Controller $conn

    # record values to object
    $object = Set-SanObject -nodetype 'SAN' -hostname $hostname -ip $ip -OS $OSVersion -notes "NetApp Filer $controllerName" -model $model -cluster 'N/A' -WWPN $wwpn -WWNN $wwnn -current_host 'N/A'
    
    #return object to array
    return $object
}