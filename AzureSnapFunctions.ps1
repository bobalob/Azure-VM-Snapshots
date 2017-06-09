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

Import-Module AzureRM
#Login-AzureRMAccount
. "$($PSScriptRoot)\AzureStorageFunctions.PS1"

Function New-AzureRmVmSnap {
    Param(
        [Parameter(Mandatory=$true)]$VMName,
        [Parameter(Mandatory=$true)]$SnapshotName,
        $SnapshotDescription="",
        [switch]$Force=$False
    )
	
	Write-Host "Create Snapshot for VM: " -ForegroundColor Yellow -NoNewline
	Write-Host $VMName -ForegroundColor Cyan
    
	$VM = Get-AzureRmVm | Where-Object {$_.Name -eq $VMName}
	if ($VM) {
         
        #Warn if VM OS disk is on Premium storage and break
        if (Test-Premium $VM.StorageProfile.OsDisk.Vhd.Uri) {
            Write-Warning "Premium storage is not currently supported by this function"
            Break
        }

        #Warn if VM is running and break
        $VMState = $VM | Get-AzureRmVm | Get-AzureRmVm -Status | 
            select Name, @{n="Status"; e={$_.Statuses[1].DisplayStatus}}

        if ($VMState.Status -eq "VM Running") {
            #Stop the VM if force enabled
            if ($Force) {
                Write-Host "Stopping VM..."
                $Stopped = $VM | Stop-AzureRmVm -Force
            } else {
                #Show warning
                Write-Warning "VM is currently running, use -force to stop the VM"
                Break
            }
        }

		$SnapshotGUID = New-GUID

        $DiskUriList=@()
		$DiskUriList += $VM.StorageProfile.OsDisk.Vhd.Uri
		Foreach ($Disk in $VM.StorageProfile.DataDisks) {
			$DiskUriList += $Disk.Vhd.Uri
		}
        
        $BaseStorageContext = Get-StorageContextForUri -DiskUri $VM.StorageProfile.OsDisk.Vhd.Uri
        
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
                -StorageContext $BaseStorageContext -DiskNum $DiskUriList.IndexOf($DiskUri) `
                -SnapshotName $SnapshotName -SnapshotDescription $SnapshotDescription

		}
        
        if ($VMState.Status -eq "VM Running") {
            Write-Host "Restarting VM..."
            $Started = $VM | Start-AzureRmVm
        }

        Retrieve-SnapInfo -VMName $VMName -SnapGUID $SnapshotGUID -StorageContext $StorageContext
	} else {
		Write-Host "Unable to get VM"
	}
}

Function Get-AzureRmVmSnap {
	Param(
        [Parameter(Mandatory=$true)]$VMName,
        $SnapshotGUID,
        [switch]$GetBlobs=$False
	)
	$VM = Get-AzureRmVm | Where-Object {$_.Name -eq $VMName}
	if ($VM) {
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri
        $StorageContext = Get-StorageContextForUri -DiskUri $OSDiskUri

        if ($SnapshotGUID) {
            $SnapInfo = Retrieve-SnapInfo -VMName $VMName -SnapGUID $SnapshotGUID -StorageContext $StorageContext
        } else {
            $SnapInfo = Retrieve-SnapInfo -VMName $VMName -StorageContext $StorageContext
        }

        if ($GetBlobs) {
            $SnapshotBlobs = Get-AzureRmVmSnapBlobs -VMName $VMName
            Foreach ($SnapInfo in $SnapInfo) {
                $SnapshotBlobs | ? {$_.ICloudBlob.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString() -eq $SnapInfo.SnapshotUri.ToString()}
            }
        } else {
            $SnapInfo
        }
    }
}

Function Delete-AzureRmVmSnap {
	Param (
        [Parameter(Mandatory=$true)]$VMName, 
        [switch]$Force=$False,
        $SnapshotGuid
    )
	$VM = Get-AzureRmVm | Where-Object {$_.Name -eq $VMName}
	if ($VM) {
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri
        $StorageContext = Get-StorageContextForUri $OSDiskUri
        $SnapInfo = Retrieve-SnapInfo -VMName $VMName -StorageContext $StorageContext
        $UniqueGuids = $SnapInfo | ForEach-Object {$_.SnapGuid} | Sort-Object -Unique
        if ($SnapshotGuid) {$UniqueGuids = $UniqueGuids | Where-Object {$_ -eq $SnapshotGuid}}
        if ($UniqueGuids -ne $null -or $UniqueGuids.Count -gt 0) {
            Foreach ($Guid in $UniqueGuids) {
                $SnapInfo | Where-Object {$_.SnapGUID -eq $Guid}
                $SnapBlobs = Get-AzureRmVmSnap -VMName $VMName -SnapshotGUID $Guid -GetBlobs
                if ($SnapBlobs) {
                    if (!($Force)) {
                        $Delete = Read-Host "$($SnapBlobs.Count) Disk(s) in this snapshot set - Delete this snap? [y/N]: "
                    }
                    if ($Delete -eq "y" -or $Force) {
                        Try {
                            $SnapBlobs | ForEach-Object {$_.ICloudBlob.Delete()}
                        } catch {
                            Write-Error "Unable to delete the snapshot $Guid"
                        } finally {
                            Clear-SnapInfo -SnapGUID $Guid -StorageContext $StorageContext
                        }
                    }
                } else {
                    Write-Error "No snapshot blobs exist for snapshot GUID: $($Guid), Snapshot table is out of sync with actual snapshot blobs"
                }
            }
        } else {
            Write-Warning "Snapshot not found"
        }
    } else {
        Write-Host "Unable to find VM"
    }
}

Function Revert-AzureRmVmSnap {
	Param (
        [Parameter(Mandatory=$true)]$VMName, 
        [switch]$Force=$False,
        $SnapshotGuid
    )
	$VM = Get-AzureRmVm | Where-Object {$_.Name -eq $VMName}
	if ($VM) {
        #Get user selected snapshot
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri
        $StorageContext = Get-StorageContextForUri $OSDiskUri
        $SnapInfo = Retrieve-SnapInfo -VMName $VMName -StorageContext $StorageContext
        $UniqueGuids = $SnapInfo | Foreach-Object {$_.SnapGuid} | Sort-Object -Unique
        if ($SnapshotGuid) {$UniqueGuids = $UniqueGuids | Where-Object {$_ -eq $SnapshotGuid}}
        Foreach ($Guid in $UniqueGuids) {
            $SnapBlobs = Get-AzureRmVmSnap -VMName $VMName -SnapshotGUID $Guid -GetBlobs
            if ($Force -and $UniqueGuids.Count -eq 1) {
                $Revert = "y"
            } else {
                if ($Force) {
                    Write-Warning `
                        "-Force only works with a given GUID or if there is only 1 snapshot set for this VM"
                    Break
                }
                $SnapInfo | Where-Object {$_.SnapGUID -eq $Guid}
                $Revert = Read-Host "$($SnapBlobs.Count) Disks in this snapshot set - Revert to this snap? [y/N]: "
            }
            if ($Revert -eq "y") {
                Write-Host "Reverting to snapshot with GUID: " -ForegroundColor Yellow -NoNewLine
                Write-Host $Guid -ForegroundColor Cyan

                #Shut down the VM
                Try {
                    Write-Host "Stopping the VM..."
                    $VM | Stop-AzureRmVm -Force
                } catch {
                    Write-Error "Failed to stop the VM"
                    Break
                }

                #Back up the VM config in case something goes wrong - recovery function not working yet
                #TODO: Recovery Function
                if (!(Test-Path ".\VM-Backups")) {
                    $Null = New-Item -Path ".\VM-Backups" -ItemType "Directory"
                }
                Export-Clixml -Path ".\VM-Backups\$($VM.Name).Original.xml" -InputObject $VM

                #Remove the VM config
                Try {
                    Write-Host "Removing the VM configuration..."
                    $VM | Remove-AzureRmVm -Force
                } catch {
                    Write-Error "Failed to remove the VM config"
                    if (Get-AzureRmVm | Where-Object {$_.Name -eq $VMName}) {
                        Write-Host "VM Still exists, exiting..."
                        Break
                    } else {
                        Write-Host "VM was actually removed, continuting..."
                    }
                }

                Try {
                    Write-Host "Reverting the snapshot..."
                    Foreach ($SnapBlob in $SnapBlobs) {
                        $ThisSnap = $SnapInfo | ? {$_.SnapGUID -eq $guid -and $_.SnapshotUri -eq `
                            $SnapBlob.ICloudBlob.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString()}
                        Write-Host "Reverting disk $($ThisSnap.DiskNum)..."
                        $DiskInfo = Get-DiskInfo -DiskUri $SnapBlob.ICloudBlob.Uri.OriginalString
                        $OriginalDiskBlob = Get-AzureStorageBlob -Container $DiskInfo.ContainerName `
                            -Context $StorageContext | 
                            Where-Object {$_.Name -eq $DiskInfo.VHDName `
                                    -and -not $_.ICloudBlob.IsSnapshot `
                                    -and $_.SnapshotTime -eq $null
                                }
                        $Copy = $OriginalDiskBlob.ICloudBlob.StartCopy($SnapBlob.ICloudBlob) 
                        Write-Host "Reversion Compete for disk $($ThisSnap.DiskNum) - Copy ID: $($Copy)"
                    }

                } catch {
                    Write-Error "Failed to revert the snapshot, recreating VM with current disk"
                }

                #Remove disallowed settings
                $osType = $VM.StorageProfile.OsDisk.OsType
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
                #TODO: Replace -windows with correct OS
                $vm=Set-AzureRmVmOSDisk -VM $vm -VhdUri $osDiskUri -name $DiskName `
                    -CreateOption attach -Windows -Caching $osDiskCaching 
                
                #Attach data Disks
                if ($VM.StorageProfile.DataDisks.count -gt 0) {
                    Write-Host "Configure additional disks"
                    $DataDisks = $VM.StorageProfile.DataDisks
                    $VM.StorageProfile.DataDisks = $Null
                    foreach ($DataDisk in $DataDisks) {
                        $VM = Add-AzureRmVmDataDisk -VM $VM -VhdUri $DataDisk.Vhd.Uri `
                            -Name $DataDisk.Name -CreateOption "Attach" `
                            -Caching $DataDisk.Caching -DiskSizeInGB $DataDisk.DiskSizeInGB `
                            -Lun $DataDisk.Lun
                    }   
                }

                #If this isn't set the VM will default to Windows and get stuck in the "Updating" state
                #Probably because -windows is set when adding the OS disk!
                $VM.StorageProfile.OsDisk.OsType = $osType

                #Recreate the VM
                Write-Host "`nRecreate the VM..."
                New-AzureRmVm -ResourceGroupName $rgName -Location $locName -VM $VM -WarningAction Ignore

                #Break out of the UniqueGuids loop
                Break
            }
        }
    }
}
