Import-Module '480-utils' -Force

# Test function to ensure correct import
# 480Banner

$conf = Get-480Config -ConfigPath "/home/reed/NET-480-2023SP/480.json"

$server = Read-Host "VCenter host [$($conf.vcenter_server)]"
if (-not $server) {
    $server = $conf.vcenter_server
}

480Connect -Server $server

$vm_folder = Read-Host "Base VM Folder [$($conf.vm_folder)]"
if (-not $vm_folder) { $vm_folder = $conf.vm_folder }

$vm = Select-VM -Folder $vm_folder

# Allow selection between full/linked clone type
$clonePrompt = { Read-Host "[F]ull clone, [L]inked clone, or [Q]uit" }
$cloneType = & $clonePrompt

while ($cloneType.ToUpper() -notin @("F", "L", "Q")) {
    Write-Host -ForegroundColor Yellow "Please select between F, L, or Q!"
    $cloneType = & $clonePrompt
}

switch ($cloneType.ToUpper()) {
    "F" { $clone = New-480FullClone -VM $vm -VMHost $conf.esxi_host -Datastore $conf.default_datastore -SnapshotName $conf.base_snapshot_name }
    "L" { $clone = New-480LinkedClone -VM $vm -VMHost $conf.esxi_host -Datastore $conf.default_datastore -SnapshotName $conf.base_snapshot_name }
    "Q" {
        Write-Host "Quit selected, exiting..."
        exit
    }
    Default { Write-Host -ForegroundColor Yellow "No valid clone type selected!" }
}

# $linkedClone = New-480LinkedClone -VM $vm -Name ("{0}.linked" -f $vm.name) -VMHost $conf.esxi_host -Datastore $conf.default_datastore -SnapshotName $conf.base_snapshot_name

if ((Read-Host "Set network adapters? [Y/N]").ToUpper() -eq "Y") {
    Set-480NetworkAdapter -VM $clone
}

if ((Read-Host "Power on the VM? [Y/N]").ToUpper() -eq "Y") {
    Set-480PowerState -PowerOn -VM $clone
}

Write-Host -ForegroundColor Green "Complete!"
