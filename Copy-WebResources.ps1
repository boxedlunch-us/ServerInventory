function Copy-WebResources{
    param(
    [parameter(parametersetname="User Name")]$userName
    )
    copy-item -Path "\\webhost\Development\Ricky\Server Inventory\webReportResources\*" -Destination "\\share\ameddcs\home_Drive\$userName\serverlist\" -Recurse -Force
}


