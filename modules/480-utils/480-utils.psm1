function 480Banner() {
    Write-Host "Hello Devops"
}

function 480Connect {
    param (
        # VServer address for connection
        [Parameter(Mandatory = $true)]
        [string]$Server
    )
    # Connect to VServer if not already connected
    $conn = $global:DefaultVIServer
    if ($conn) {
        Write-Host -ForegroundColor Green ("Already Connected to: {0}" -f $conn)
    }
    else {
        $conn = Connect-VIServer -Server $Server
    }
}

function Get-480Config {
    param (
        # Path to config file
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (Test-Path $ConfigPath) {
        $conf = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
        Write-Host -ForegroundColor Green "Using configuration at $ConfigPath"
    }
    else {
        $conf = $null
        Write-Host -ForegroundColor Yellow "No valid configuration at $ConfigPath found"
    }
    return $conf
}

function Select-VM {
    param (
        # VCenter VM folder name
        [Parameter(Mandatory = $true)]
        [string]$Folder
    )
    try {
        Write-Host "VMs in folder '${Folder}':"
        $vms = Get-VM -Location $Folder
        for ($index = 0; $index -lt $vms.Length; $index++) {
            Write-Host "[$index] $($vms[$index].name)"
        }

        $indexQuery = { (Read-Host "Which VM index [x] should be used?") -as [int] }
        $index = & $indexQuery
        while ( ($index -isnot [int]) -or ($index -notin 0..$vms.Length) ) {
            Write-Host -ForegroundColor Yellow "Index [x] must be a number between 1 and $($vms.Length)!"
            $index = & $indexQuery
        }

        $selectedVM = $vms[$index]
        Write-Host "Selected VM: $($selectedVM.name)"
        return $selectedVM
    }
    catch {
        Write-Host -ForegroundColor Red "Invalid folder: $folder"
    }
}

function New-480LinkedClone {
    param (
        # VM to clone (VM object, not string)
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$VM,
        # Linked clone name
        [string]$Name,
        # VM Host
        [Parameter(Mandatory = $true)]
        [string]$VMHost,
        # Datastore
        [Parameter(Mandatory = $true)]
        [string]$Datastore,
        # Base snapshot name
        [Parameter(Mandatory = $true)]
        [string]$SnapshotName
    )

    while ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Read-Host "Enter destination VM name"
    }

    try {
        $clone = New-VM -LinkedClone -Name $Name -VM $VM -VMHost $VMHost -Datastore $Datastore -ReferenceSnapshot $SnapshotName
        Write-Host -ForegroundColor Green "Created linked clone: $Name"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to create linked clone from $VM"
    }
    return $clone
}

function New-480FullClone {
    param (
        # VM to clone (VM object, not string)
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$VM,
        # Full clone name
        [string]$Name,
        # VM Host
        [Parameter(Mandatory = $true)]
        [string]$VMHost,
        # Datastore
        [Parameter(Mandatory = $true)]
        [string]$Datastore,
        # Base snapshot name
        [Parameter(Mandatory = $true)]
        [string]$SnapshotName
    )

    while ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Read-Host "Enter destination VM name"
    }

    Write-Host -ForegroundColor Green "Creating full clone $Name"
    try {
        $linkedClone = New-480LinkedClone -VM $VM -Name "$Name.linked" -VMHost $VMHost -Datastore $Datastore -SnapshotName $SnapshotName
        $clone = New-VM -Name $Name -VM $linkedClone -VMHost $VMHost -Datastore $Datastore
        Write-Host -ForegroundColor Green "Created full clone: $Name"
        Remove-VM -VM $linkedClone -Confirm:$false -DeletePermanently
        Write-Host -ForegroundColor Green "Removed temporary linked clone"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to create full clone from $VM"
    }
    return $clone
}

function Set-480NetworkAdapter {
    param (
        # VM for network adapter modification
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$VM
    )

    Write-Host -ForegroundColor Green "Selecting $VM network adapters"

    $networks = Get-VirtualNetwork
    $adapters = Get-NetworkAdapter -VM $VM
    $indexQuery = { (Read-Host "Which Adapter index [x] should be used?") -as [int] }
    
    Write-Host "Available networks:"
    for ($index = 0; $index -lt $networks.Length; $index++) {
        Write-Host "[$index] $($networks[$index].name)"
    }

    try {
        foreach ($adapter in $adapters) {
            Write-Host -ForegroundColor Green "Select network for adapter $($adapter.name):"
            $index = & $indexQuery
            while ( ($index -isnot [int]) -or ($index -notin 0..$networks.Length) ) {
                Write-Host -ForegroundColor Yellow "Index [x] must be a number between 1 and $($networks.Length)!"
                $index = & $indexQuery
            }
            Set-NetworkAdapter -NetworkAdapter $adapter -NetworkName $networks[$index] -Confirm:$false
        }
    }
    catch {
        Write-Host -ForegroundColor Red "Error setting network adapter for VM $VM"
    }
}

function Set-480PowerState {
    param (
        # VM for power state modification
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$VM,
        # Power VM On
        [switch]$PowerOn,
        # Power VM Off
        [switch]$PowerOff
    )

    # If both flags are set, VM will be first powered on, THEN powered off. Not exclusive.
    if ($PowerOn) {
        Start-VM -VM $VM -Confirm:$false
        Write-Host -ForegroundColor Green "Powered on VM"
    }

    if ($PowerOff) {
        Stop-VM -VM $VM -Confirm:$false
        Write-Host -ForegroundColor Green "Powered off (stopped) VM"
    }
}

function Get-IP {
    param (
        # VM for retrieval of networking information
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$VM
    )

    # Write-Host -ForegroundColor Green "Network information for VM with name $VM"
    # $VMObj = Get-VM -Name $VM
    # $VMObj.Guest.IPAddress
    # Write-Host -ForegroundColor Green "MAC Addresses for VM with name $VM"
    # $VMObj | Get-NetworkAdapter | Select -ExpandProperty 'MacAddress'

    $VMObjs = Get-VM -Name $VM

    foreach ($VMObj in $VMObjs) {
        $mac = $VMObj | Get-NetworkAdapter | Select-Object -ExpandProperty 'MacAddress'

        # Credit to LucD for oneliner to extract plaintext value of property:
        # https://communities.vmware.com/t5/VMware-PowerCLI-Discussions/How-do-i-get-MAC-address-and-IP-in-a-format-i-can-use-in-a/m-p/1300063/highlight/true#M38623
        $ip = $VMObj | Select-Object @{N='IP Address';E={@($_.guest.IPAddress[0])}} | Select-Object -ExpandProperty 'IP Address'

        Write-Host "$ip host=$VMObj mac=$mac"
    }
}

function New-Network {
    param (
        # Name of new network
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$VMHost
    )

    try {
        $vswitch = New-VirtualSwitch -Name $Name -VMHost $VMHost
        New-VirtualPortGroup -VirtualSwitch $vswitch -Name $Name

        Write-Host -ForegroundColor Green "Created $Name"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to create $Name"
    }
}
