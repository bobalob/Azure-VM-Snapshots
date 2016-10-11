# SnapshotVM.ps1
# Create snapshot of the given Azure RM VM 

Function Create-AzureRMVMSnap {
	Param(
		[Parameter(Mandatory=$true)]$VMName
    )
	
	Write-Host "Create Snapshot for VM: " -ForegroundColor Yellow -NoNewline
	Write-Host $VMName -ForegroundColor Cyan

	if (!(Get-AzureAccount)) {
		$AzureAccount = Add-AzureAccount
	}

	$VM = Get-AzureRmVM | ? {$_.Name -eq $VMName}
	if ($VM) {
		$DiskUriList=@()
		$DiskUriList += $VM.StorageProfile.OsDisk.Vhd.Uri
		Foreach ($Disk in $VM.StorageProfile.DataDisks) {
			$DiskUriList += $Disk.Vhd.Uri
		}
		
		$Snapshots=@()
		Foreach ($DiskUri in $DiskUriList) {
			Write-Host "Snapshot disk: " -ForegroundColor Yellow -NoNewline
			Write-Host $DiskUri -ForegroundColor Cyan
			
			$DiskToSnap = "" | Select Uri, StorageAccountName, VHDName, ContainerName
			$DiskToSnap.Uri = $DiskUri
			$DiskToSnap.StorageAccountName = ($DiskUri -split "https://")[1].Split(".")[0]
			$DiskToSnap.VHDName = $DiskUri.Split("/")[-1]
			$DiskToSnap.ContainerName = $DiskUri.Split("/")[-2]
				
			$StorageAccountResource = find-azurermresource -ResourceNameContains `
                $DiskToSnap.StorageAccountName

			$StorageKey = Get-AzureRmStorageAccountKey `
                -Name $StorageAccountResource.Name `
                -ResourceGroupName $StorageAccountResource.ResourceGroupName

			$StorageContext = New-AzureStorageContext `
                -StorageAccountName $StorageAccountResource.Name `
                -StorageAccountKey $StorageKey[0].Value

			$DiskBlob = Get-AzureStorageBlob -Container $DiskToSnap.ContainerName `
                -Context $StorageContext -Blob $DiskToSnap.VHDName

			$Snapshots += $DiskBlob.ICloudBlob.CreateSnapshot()

		}

		$Snapshots

	} else {
		Write-Host "Unable to get VM"
	}}

Function Get-AzureRMVMSnap {
	Param(
		[Parameter(Mandatory=$true)]$VMName
	)

	if (!(Get-AzureAccount)) {
		$AzureAccount = Add-AzureAccount
	}

	$VM = Get-AzureRmVM | ? {$_.Name -eq $VMName}
	if ($VM) {
		$DiskUriList=@()
		$DiskUriList += $VM.StorageProfile.OsDisk.Vhd.Uri
		Foreach ($Disk in $VM.StorageProfile.DataDisks) {
			$DiskUriList += $Disk.Vhd.Uri
		}
		
		$Snapshots=@()
		Foreach ($DiskUri in $DiskUriList) {
			Write-Host "Snapshots for Disk: " -ForegroundColor Yellow -NoNewline
			Write-Host $DiskUri -ForegroundColor Cyan
			
			$DiskToSnap = "" | Select Uri, StorageAccountName, VHDName, ContainerName
			$DiskToSnap.Uri = $DiskUri
			$DiskToSnap.StorageAccountName = ($DiskUri -split "https://")[1].Split(".")[0]
			$DiskToSnap.VHDName = $DiskUri.Split("/")[-1]
			$DiskToSnap.ContainerName = $DiskUri.Split("/")[-2]
				
			$StorageAccountResource = find-azurermresource `
                -ResourceNameContains $DiskToSnap.StorageAccountName

			$StorageKey = Get-AzureRmStorageAccountKey `
                -Name $StorageAccountResource.Name `
                -ResourceGroupName $StorageAccountResource.ResourceGroupName

			$StorageContext = New-AzureStorageContext `
                -StorageAccountName $StorageAccountResource.Name `
                -StorageAccountKey $StorageKey[0].Value

			Get-AzureStorageBlob -Container $DiskToSnap.ContainerName `
                -Context $StorageContext | 
                ? {$_.Name -eq $DiskToSnap.VHDName `
                        -and $_.ICloudBlob.IsSnapshot `
                        -and $_.SnapshotTime -ne $null
            }
		}

	} else {
		Write-Host "Unable to get VM"
	}
}

Function Delete-AzureRMVMSnap {
	Param (
        [Parameter(Mandatory=$true)]$VMName, 
        [switch]$DeleteAll=$False
    )
	
    $DiskSnaps = Get-AzureRMVMSnap -VMName $VMName 

    if ($DeleteAll) {
        $DiskSnaps | % {$_.ICloudBlob.Delete()}
    } else {
        Foreach ($Snap in $DiskSnaps) {
            $Snap
            $Delete = Read-Host "Delete this snap? [y/N]: "
            if ($Delete -eq "y") {
                $Snap.ICloudBlob.Delete()
            }
        }
    }
    
}