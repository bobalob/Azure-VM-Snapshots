<#
.SYNOPSIS
    A set of functions to create, delete or revert to a snapshot of an Azure RM VM
.DESCRIPTION
    A detailed description of the function or script. This keyword can be
    used only once in each topic.
.NOTES
    File Name      : AzureSnapFunctions.ps1
    Author         : Dave Hall
    Prerequisite   : PowerShell V5 (Tested with V5, may work in earlier)
                     AzureRM Powershell Module (Install-Module AzureRM)
    Copyright 2016 - Dave Hall
.LINK
    http://superautomation.blogspot.com
.EXAMPLE
    Example 1
.EXAMPLE
    Example 2
#>

#Import-Module AzureRM
#Login-AzureRMAccount
. "$($PSScriptRoot)\AzureStorageFunctions.PS1"

#TODO: Add Name/Description for snaps
Function Create-AzureRMVMSnap {
	Param(
		[Parameter(Mandatory=$true)]$VMName
    )
	
	Write-Host "Create Snapshot for VM: " -ForegroundColor Yellow -NoNewline
	Write-Host $VMName -ForegroundColor Cyan

	$VM = Get-AzureRmVM | ? {$_.Name -eq $VMName}
	if ($VM) {
		$SnapshotGUID = New-GUID

        $DiskUriList=@()
		$DiskUriList += $VM.StorageProfile.OsDisk.Vhd.Uri
		Foreach ($Disk in $VM.StorageProfile.DataDisks) {
			$DiskUriList += $Disk.Vhd.Uri
		}

		$Snapshots=@()
        $SnapshotTableInfo=@()
		Foreach ($DiskUri in $DiskUriList) {
			Write-Host "Snapshot disk: " -ForegroundColor Yellow -NoNewline
			Write-Host $DiskUri -ForegroundColor Cyan

	        $DiskInfo = Get-DiskInfo $DiskUri

			$StorageContext = Get-StorageContextForUri -DiskUri $DiskUri

			$DiskBlob = Get-AzureStorageBlob -Container $DiskInfo.ContainerName `
                -Context $StorageContext -Blob $DiskInfo.VHDName

			$Snapshot = $DiskBlob.ICloudBlob.CreateSnapshot()
            
            Write-SnapInfo -VMName $VMName -SnapGUID $SnapshotGUID `
                -PrimaryUri $DiskInfo.Uri.ToString() `
                -SnapshotUri $Snapshot.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString() `
                -StorageContext $StorageContext -DiskNum $DiskUriList.IndexOf($DiskUri)

		}
        #TODO: This will only retrieve storage info for a single context 
        #  so if disks are split over storage accounts it won't work properly
        Retrieve-SnapInfo -VMName $VMName -SnapGUID $SnapshotGUID -StorageContext $StorageContext
	} else {
		Write-Host "Unable to get VM"
	}}
#TODO: Combine the Get functions
Function Get-AzureRMVMSnapBlobs {
	Param(
		[Parameter(Mandatory=$true)]$VMName
	)

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

	        $DiskInfo = Get-DiskInfo -DiskUri $DiskUri

			$StorageContext = Get-StorageContextForUri -DiskUri $DiskUri

                Get-AzureStorageBlob -Container $DiskInfo.ContainerName `
                    -Context $StorageContext | 
                    ? {$_.Name -eq $DiskInfo.VHDName `
                            -and $_.ICloudBlob.IsSnapshot `
                            -and $_.SnapshotTime -ne $null
                    }
		}

	} else {
		Write-Host "Unable to get VM"
	}
}

Function Get-AzureRMVMSnap {
	Param(
		[Parameter(Mandatory=$true)]$VMName,
        $SnapshotGUID
	)
	$VM = Get-AzureRmVM | ? {$_.Name -eq $VMName}
	if ($VM) {
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri
        $StorageContext = Get-StorageContextForUri -DiskUri $OSDiskUri

        if ($SnapshotGUID) {
            $SnapInfo = Retrieve-SnapInfo -VMName $VMName -SnapGUID $SnapshotGUID -StorageContext $StorageContext
        } else {
            $SnapInfo = Retrieve-SnapInfo -VMName $VMName -StorageContext $StorageContext
        }

        $SnapshotBlobs = Get-AzureRMVMSnapBlobs -VMName $VMName
        Foreach ($SnapInfo in $SnapInfo) {
            $SnapshotBlobs | ? {$_.ICloudBlob.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString() -eq $SnapInfo.SnapshotUri.ToString()}
        }

    }


}

Function Delete-AzureRMVMSnapBlobs {
	Param (
        [Parameter(Mandatory=$true)]$VMName, 
        [switch]$DeleteAll=$False
    )
	
    if ($DeleteAll) {
        $DiskSnaps = Get-AzureRMVMSnapBlobs -VMName $VMName
        $DiskSnaps | % {$_.ICloudBlob.Delete()}
    } else {
	    $VM = Get-AzureRmVM | ? {$_.Name -eq $VMName}
	    if ($VM) {
            $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri
            $StorageContext = Get-StorageContextForUri $OSDiskUri
            $SnapInfo = Retrieve-SnapInfo -VMName $VMName -StorageContext $StorageContext
            $UniqueGuids = $SnapInfo | % {$_.SnapGuid} | Sort -Unique
            Foreach ($Guid in $UniqueGuids) {
                $SnapBlobs = Get-AzureRMVMSnap -VMName $VMName -SnapshotGUID $Guid
                $SnapBlobs | Select -First 1
                $Delete = Read-Host "$($SnapBlobs.Count) Disks in this snapshot set - Delete this snap? [y/N]: "
                if ($Delete -eq "y") {
                    $SnapBlobs | % {$_.ICloudBlob.Delete()}
                }
            }
        } else {
            Write-Host "Unable to find VM"
        }
    }   
}

Function Revert-AzureRMVMSnap {
	Param(
		[Parameter(Mandatory=$true)]$VMName
	)
	$VM = Get-AzureRmVM | ? {$_.Name -eq $VMName}
	if ($VM) {
        #Get user selected snapshot
        #TODO: Accept snapshot GUID or Name as parameter
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri
        $StorageContext = Get-StorageContextForUri $OSDiskUri
        $SnapInfo = Retrieve-SnapInfo -VMName $VMName -StorageContext $StorageContext
        $UniqueGuids = $SnapInfo | % {$_.SnapGuid} | Sort -Unique
        Foreach ($Guid in $UniqueGuids) {
            $SnapBlobs = Get-AzureRMVMSnap -VMName $VMName -SnapshotGUID $Guid
            $SnapBlobs | Select -First 1
            $Revert = Read-Host "$($SnapBlobs.Count) Disks in this snapshot set - Revert to this snap? [y/N]: "
            if ($Revert -eq "y") {

                #Shut down the VM
                Write-Host "Stopping the VM..."
                $VM | Stop-AzureRMVM -Force

                #Delete the VM
                Write-Host "Deleting the VM..."
                $VM | Remove-AzureRmVm -Force

                Foreach ($SnapBlob in $SnapBlobs) {
                    $ThisSnap = $SnapInfo | ? {$_.SnapGUID -eq $guid -and $_.SnapshotUri -eq `
                        $SnapBlob.ICloudBlob.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString()}
                    Write-Host "Reverting disk $($ThisSnap.DiskNum)..."
                    $DiskInfo = Get-DiskInfo -DiskUri $SnapBlob.ICloudBlob.Uri.OriginalString
                    $OriginalDiskBlob = Get-AzureStorageBlob -Container $DiskInfo.ContainerName `
                        -Context $StorageContext | 
                        ? {$_.Name -eq $DiskInfo.VHDName `
                                -and -not $_.ICloudBlob.IsSnapshot `
                                -and $_.SnapshotTime -eq $null
                        }
                    $OriginalDiskBlob.ICloudBlob.StartCopyFromBlob($SnapBlob.ICloudBlob) 
                    #TODO: Enter into loop until copy finished     
                }

                #Remove disallowed settings
                Write-Host "Recreate the VM..."
                $VM.StorageProfile.OsDisk.OsType = $null
                $VM.StorageProfile.ImageReference = $Null
                $VM.OSProfile = $null

                #Old VM Information
                $rgName=$VM.ResourceGroupName
                $locName=$VM.Location
                $osDiskUri=$VM.StorageProfile.OsDisk.Vhd.Uri
                $diskName=$VM.StorageProfile.OsDisk.Name
                $osDiskCaching = $VM.StorageProfile.OsDisk.Caching

                #Set the OS disk to attach
                $vm=Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskUri -name $DiskName `
                    -CreateOption attach -Windows -Caching $osDiskCaching

                #Recreate the VM
                New-AzureRmVM -ResourceGroupName $rgName -Location $locName -VM $VM

                #Break out of the loop
                Break
            }
        }


    }
}
