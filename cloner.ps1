# Given a VM name, clone a snapshot of the VM, with optional configuration.
# Reed Simon, Jan 31, 2023

# Required parameters: source VM name, destination clone name.
# Optional parameters (defaults set): datastore name, snapshot name (Base), VM host, network.
#   If network is set, the cloned VM's network adapter will be set to the specified network.
param (
    [Parameter(Mandatory = $true,
        ValueFromPipeline = $true,
        ParameterSetName = "CloneVM")]
    [string]$VMName,

    [Parameter(Mandatory = $true,
        ParameterSetName = "CloneVM")]
    [string]$CloneName,
    
    [Parameter(Mandatory = $true,
        ParameterSetName = "ListVM")]
    [switch]$List,

    [Parameter(ParameterSetName = "CloneVM")]
    [string]$DatastoreName,

    [Parameter(ParameterSetName = "CloneVM")]
    [string]$SnapshotName = "Base",
    
    [Parameter(ParameterSetName = "CloneVM")]
    [string]$VMHost,

    [Parameter(ParameterSetName = "CloneVM")]
    [string]$Network
)

# Exit on any non-terminating errors for safety
$ErrorActionPreference = "Stop"

# Check if vCenter connection is established
if ($global:DefaultVIServers.count -gt 0) {
    Write-Host "Connected to server $($global:DefaultVIServers[0].name)"
}
else {
    Write-Host "No existing vCenter server connection, attempting to establish..."
    $vserver = (Read-Host -Prompt "Enter server IP/FQDN: ")
    Connect-VIServer -Server $vserver
}

if ($List) {
    Write-Host "`nListing connected VMs"
    # Get-VM | Select-Object Name
    Get-VM | Select-Object Name | Format-Table -AutoSize
    exit
}

if (-Not $VMHost) {
    Write-Host "No VM host specified, using first available"
    $VMHost = (Get-VMHost)[0].name
}

if (-Not $DatastoreName) {
    Write-Host "No Datastore specified, using first available"
    $DatastoreName = (Get-Datastore)[0].name
}

$StartLine = "Cloning snapshot $SnapshotName of $VMName to $CloneName on $VMHost`n"
Write-Host ($StartLine + ("-" * ($StartLine.Length - 1)))

# Get the objects corresponding to given names
$vm = Get-VM -Name $VMName
$snapshot = Get-Snapshot -VM $vm -Name $SnapshotName
$vchost = Get-VMHost -Name $VMHost
$ds = Get-Datastore -Name $DatastoreName

# Create linked clone
Write-Host "Creating linked clone $('{0}.linked' -f $vm.name)"
$lc = New-VM -LinkedClone -Name ("{0}.linked" -f $vm.name) -VM $vm -ReferenceSnapshot $snapshot -VMHost $vchost -Datastore $ds

# Create full VM from linked clone
Write-Host "Creating full clone $CloneName from linked clone $($lc.name)"
$newvm = New-VM -Name $CloneName -VM $lc -VMHost $vchost -Datastore $ds

# Snapshot new VM
Write-Host "Creating snapshot $SnapshotName for new VM $($newvm.name)"
New-Snapshot -VM $newvm -Name $SnapshotName

# Remove linked clone
Write-Host "Removing linked clone $($lc.name)"
Remove-VM -VM $lc -Confirm:$false

# Check if network change was specified
if ($Network) {
    $NetworkAdapter = Get-NetworkAdapter -VM $newvm
    # Check that only one network adapter is present
    if ($NetworkAdapter.count -ne 1) {
        Write-Host "VM $CloneName has $($NetworkAdapter.count) network adapters, skipping adapter change."
    }
    else {
        # Set the VM's network adapter to the specified network
        Write-Host "Setting $CloneName network adapter to $Network"
        Set-NetworkAdapter -NetworkAdapter $NetworkAdapter -NetworkName $Network -Confirm:$false
    }
}
else {
    Write-Host "No new network specified, skipping network adapter change."
}


