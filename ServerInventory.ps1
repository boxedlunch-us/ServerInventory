# Add VMware PowerCLI module
Add-PSSnapin VMware.VimAutomation.Core

#import NetApp DOT module 
Import-Module DataONTAP

# function to create uniform inventory object
function Set-VMInventoryObject{
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
        $current_host,
        $bay
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
        bay = $bay




    }

    return $object

}

$today = get-date -Format "yyyyMMdd"

# admin server name
$aServerName = 'AdminServer'

$ScriptDir = Split-Path $script:MyInvocation.mycommand.path

#dot-source saninfo
.  "$ScriptDir\Get-SanInfo_1.5.ps1"
.  "$ScriptDir\Copy-WebResources.ps1"
.  "$ScriptDir\Get-BayNumber.ps1"

#import list of DMLSS and SCCM machines
$physical = Import-Csv -Path "$ScriptDir\resources\PhysicalDeviceList.csv"

# array of vCenter servers
$vCenters = @('vc1','vc2','vc3')

#Get San information                
$SANList = @('filer1','filer2','filer3','filer4')

#hash table to hold objects
$inventoryhash = @()

# Get vCenter server credentials
$cred = Get-Credential -Message "Enter credentials for vCenter servers."

foreach($v in $vCenters){
    # vCenter Server
    $vc = $v


    # connect to the vCenter server with local account; -credential is also acceptable, but i took the long way 'round
    write-host("Connecting to $v")
    Connect-VIServer $vc -User $cred.GetNetworkCredential().UserName -Password $cred.GetNetworkCredential().Password

    # get list of ESXi Hosts
    Write-Host("Getting list of Hosts")
    $hosts = Get-VMHost

    # loop thru list of hosts to add info to object
    foreach($h in $hosts){
        
        # no dynamic variable needed
        $node = 'ESXi Host'


        $name = $h.Name

        write-host("Gathering information on $name (ESXi Host)")

        # cmdlet to get the network info
        $ip = Get-VMHostNetworkAdapter -VMHost $h

        $mac = $ip[0].mac

        $bay = Get-BayNumber -MAC $mac  

        $ip = $ip | Where-Object{$_.ip -ne ''}

        #split the array by semicolon for readability
        $ip = $ip.ip -join '; '

        $notes = Get-Annotation $h



        #get wwpn and wwnn
        $storage = Get-VMHostHba -VMHost $h
        $storage = $storage | Where-Object{$_.type -match 'FibreChannel'}

        $wwnn = $storage.nodeworldwidename -join '; '
        $wwpn = $storage.portworldwidename -join '; '
        
        # call object to hold host values
        $object = Set-VMInventoryObject -nodetype $node -hostname $name -ip $ip -OS $h.ApiVersion -notes "ESXi Host" -model $h.Model -cluster $h.Parent.Name -WWPN $wwpn -WWNN $wwnn -current_host 'N/A' -bay $bay
        
        write-host("Adding information on $name to the table")
        #add object to hash for export
        $inventoryhash += $object
    }#<--- End loop thru ESXi hosts
    
    #gettting list of VMs
    write-host("Getting list of VMs")
    $VMs = Get-VM -Server $vc

    # loop thru the list of VMs for this vCenter server
    foreach($vm in $VMs){
        write-host("Getting information on " + $vm.Name)
        if($vm.VMHost.parent.Name -ne 'Server you needs to skip over'){
            # get guest VM object for enum
            $guest = Get-VMGuest -VM $vm

            $ip = $guest.nics.ipaddress -join '; '

            # get notes for VM (description)
            $notes = $vm.Notes

            if($notes -eq $null -or $notes -eq ''){
                # if no notes exist, insert generic description
                $notes = 'Virtual Machine - ' + $vm.Name
            }

            $vobject = Set-VMInventoryObject -nodetype 'VM' -hostname $vm.Name -ip $ip -OS $guest.OSFullName -notes $notes -model $vm.Version -cluster $vm.VMHost.Parent.Name -WWPN 'N/A' -WWNN 'N/A' -current_host $vm.VMHost
            
            write-host("Adding information on "+$vm.Name+ " to the table")
            $inventoryhash += $vobject
        }else{
            ""+$vm.Name + " is a placeholder"
        }
        
    }
    Disconnect-VIServer -Server $vc -Confirm:$false
    
} #<--- End loop thru vCenter servers



$head = Get-Content -Encoding UTF8 -Path "$scriptdir\resources\combined_head.htm"


write-host("Creating HTML table from VMware host and virtual machine information")
#Inventory Hash is looped thru to create server and host list
$gurl = foreach($h in $inventoryhash){
    $node_type= $h.node_type
    $hostname = $h.hostname
    $desc = $h.notes.Trim("`n")
    $ip = $h.ip_address
    $os = $h.OS_version
    $cluster = $h.cluster
    $current_host = $h.current_host
    $wwpn = $h.wwpn
    $wwnn = $h.wwnn
    $model = $h.model
    $bay = $h.bay           
'{
    "node_type": "'+$node_type+ '",
    "hostname": "'+$hostname+'",
    "description": "'+$desc+'",
    "IP": "'+$ip+'",
    "os": "'+$os+'",
    "cluster": "'+$cluster+'",
    "current_host": "'+$current_host+'",
    "wwpn": "'+$wwpn+'",
    "wwnn": "'+$wwnn+'",
    "model": "'+$model+'",
    "bay": "'+$bay+'"
},' + "`n`n"
}

Write-Host("Getting info for special physical applications")
$physical = foreach($dm in $physical){
    '{
    "node_type": "'+$dm.node_type+ '",
    "hostname": "'+$dm.hostname+'",
    "description": "'+$dm.description+'",
    "IP": "'+$dm.ipAddresses+'",
    "os": "'+$dm.OS+'",
    "cluster": "'+$dm.Cluster+'",
    "current_host": "'+$dm.current_host+'",
    "wwpn": "'+$dm.wwpn+'",
    "wwnn": "'+$dm.wwnn+'",
    "model": "'+$dm.model+'",
    "bay": "'+$dm.bay+'"
},' + "`n`n"

# Add DMLSS info to inventory hash
$sObject = Set-VMInventoryObject -nodetype $dm.Node_type -hostname $dm.hostname -ip $dm.ipAddresses -OS $dm.OS -notes $dm.description -model $dm.model -cluster $dm.cluster -WWPN $dm.wwpn -WWNN $dm.wwnn -current_host $dm.current_host
$inventoryhash += $sObject
}

Write-Host("Getting info for SAN filers")
# loop thru array of SAN controllers
$SANARRAY = foreach($f in $SANList){
    $SANinfo = Get-SanInfo -controllerName $f
    #translated single variables
    $SANNodeType = $SANinfo.node_type
    $SANHostname = $SANinfo.hostname
    $SANIPAddress = $SANinfo.ip_address
    $SANOS = $SANinfo.OS_version
    $SANNotes = $SANinfo.notes
    $SANWWPN = $SANinfo.WWPN
    $SANWWNN = $SANinfo.WWNN
    $SANModel = $SANinfo.model
    '{
    "node_type": "'+$SANinfo.node_type+ '",
    "hostname": "'+$SANinfo.hostname+'",
    "description": "'+$SANinfo.notes+'",
    "IP": "'+$SANinfo.ip_address+'",
    "os": "'+$SANinfo.OS_version+'",
    "cluster": "'+$dm.Cluster+'",
    "current_host": "N/A",
    "wwpn": "'+$SANinfo.WWPN+'",
    "wwnn": "'+$SANinfo.WWNN+'",
    "model": "'+$SANinfo.model+'",
    "bay": "N/A"
},' + "`n`n"
        


# Add SAN info to inventory hash
$sanObject = Set-VMInventoryObject -nodetype $SANNodeType -hostname $SANHostname -ip $SANIPAddress -OS $SANOS -notes $SANNotes -model $SANModel -cluster 'N/A' -WWPN $SANWWPN -WWNN $SANWWNN -current_host 'N/A'
$inventoryhash += $sObject
}

# Combine vmware output with physical list csv
$combined = $gurl + $physical + $SANARRAY


# Clean up unwanted characters in the ajax output
# via C# call
$ajaxData = "{`n" + '"data": [' + "`n" + [regex]::replace($combined, ',(?=[^,]*$)', "") + "`n`n" + "]" + "`n`n" + "}" | out-file -FilePath "$ScriptDir\http_host\data\server_data.json" -Encoding utf8

#Users
$serverteam = @('consultant1','consultant2','consultant3','consultant4')

#server team workstations
$workstations = @('10.0.0.12','10.0.0.13','10.0.0.14','10.0.0.15')

#export .csv to the admin share
write-host("Exporting Device inventory to .csv")
$inventoryhash | Export-Csv -Path "\\share\organization\admin\serverlist\serverlist_$today.csv" -NoTypeInformation -Force

#cleanup files
$oldServerlists = Get-ChildItem "\\share\organization\admin\serverlist\"
$oldServerlists = $oldServerlists | where {$_.creationtime -lt (get-date).AddDays(-7) -and $_.name -like "*.csv*"}
$oldServerlists | ForEach-Object{remove-item $_.FullName}

#Creating Serverlists for Server Team Members
foreach($member in $serverteam){

    #check to see if serverlist directory exists
    Write-Host("Checking $member's home drive folder for a serverlist directory")
    $testpath = test-path -Path "\\share\ameddcs\home_Drive\$member\serverlist\"
    
    if($testpath){
        #save serverlist
        Write-Host("Writing CSV report to $member's serverlist folder on the I drive")
        $inventoryhash | Export-Csv -Path "\\share\organization\home_Drive\$member\serverlist\serverlist_$today.csv" -NoTypeInformation -Force

        #cleanup files
        $oldServerlists = Get-ChildItem "\\139.232.7.71\organization\home_Drive\$member\serverlist\"
        $oldServerlists = $oldServerlists | where {$_.creationtime -lt (get-date).AddDays(-7) -and $_.name -like "*.csv*"}
        $oldServerlists | ForEach-Object{remove-item $_.FullName}
    }else{
        Try{
            Write-Host("Creating serverlist directory")
            New-Item -Path "\\share\ameddcs\home_Drive\$member\" -ItemType Directory -Name 'serverlist'
        }catch{
            "Unable to complete save to $member's home Drive folder"
        }
    }
}

#Creating Serverlists for Server Team Members (Local Dicktop)
foreach($w in $workstations){

    #check to see if serverlist directory exists
    Write-Host("Checking $w's C:\temp folder for a serverlist directory")
    $testpath = test-path -Path "\\$w\C$\temp\serverlist\"

    $testforTemp = Test-Path -Path "\\$w\C$\temp\" 

    if(!$testforTemp){
        New-Item -Path "\\$w\C$\" -ItemType Directory -Name 'temp'
    }

    
    if($testpath){
        #save serverlist
        Write-Host("Writing CSV report to $w's serverlist folder on the I drive")
        $inventoryhash | Export-Csv -Path "\\$w\C$\temp\serverlist\serverlist_$today.csv" -NoTypeInformation -Force
        
        #cleanup files
        $oldServerlists = Get-ChildItem "\\$w\C$\temp\serverlist\"
        $oldServerlists = $oldServerlists | where {$_.creationtime -lt (get-date).AddDays(-7) -and $_.name -like "*.csv*"}
        $oldServerlists | ForEach-Object{remove-item $_.FullName}
    }else{
        Try{
            Write-Host("Creating serverlist directory")
            New-Item -Path "\\$w\C$\temp\" -ItemType Directory -Name 'serverlist'

            # save CSV
            Write-Host("Writing CSV report to $w's serverlist folder on the I drive")
            $inventoryhash | Export-Csv -Path "\\$w\C$\temp\serverlist\serverlist_$today.csv" -NoTypeInformation -Force

        }catch{
            "Unable to complete save to $w's I Drive folder"
        }
    }
}

# Creating website
copy-item -Path "$ScriptDir\http_host\*" -Destination "\\webhost\e$\http_host\" -Recurse -Force