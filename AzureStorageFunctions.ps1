<#
.SYNOPSIS
    Helper functions for AzureSnapFunctions.ps1
.NOTES
    File Name      : AzureStorageFunctions.ps1
    Author         : Dave Hall
    Prerequisite   : PowerShell V5 (Tested, may work in earlier)
                     AzureRM Powershell Module
    Copyright 2016 - Dave Hall
.LINK
    http://superautomation.blogspot.com
.EXAMPLE
    Example 1
.EXAMPLE
    Example 2
#>

Function Get-StorageTable {
  Param(
    [Parameter(Mandatory=$true)]$TableName,
    [Parameter(Mandatory=$true)]$StorageContext
    )
    $SnapTable = Get-AzureStorageTable -Context $StorageContext | 
        ? {$_.CloudTable.Name -eq $TableName}
    if (!($SnapTable)) {
      $SnapTable = New-AzureStorageTable -Name $TableName -Context $StorageContext
    }
    return $SnapTable
}

Function Retrieve-SnapInfo {
  Param(
      $VMName,
      $SnapGUID,
      [Parameter(Mandatory=$true)]$StorageContext
    )

    $TableName = "AzureVMSnapshots"
    $SnapTable = Get-StorageTable -TableName $TableName -StorageContext $StorageContext

    $query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
    if ($SnapGUID) {
      $Query.FilterString = "PartitionKey eq '$($SnapGUID)'"
    } 

    $SnapInfo = $SnapTable.CloudTable.ExecuteQuery($query)
    foreach ($snap in $SnapInfo) {
      $OutputItem = "" | Select VMName, SnapshotName, DiskNum, SnapGUID, PrimaryUri, SnapshotUri, SnapshotDescription, SnapshotTime
      $OutputItem.SnapGUID = $Snap.PartitionKey
      $OutPutItem.DiskNum = $Snap.RowKey
      $OutputItem.VMName = $Snap.Properties.VMName.StringValue
      $OutputItem.PrimaryUri = $Snap.Properties.BaseURI.StringValue
      $OutputItem.SnapshotUri = $Snap.Properties.SnapshotURI.StringValue
      $OutputItem.SnapshotName = $Snap.Properties.SnapshotName.StringValue
      $OutputItem.SnapshotDescription = $Snap.Properties.SnapshotDescription.StringValue
      $OutputItem.SnapshotTime = $Snap.Properties.SnapshotTime.StringValue
      if ($VMName) { 
        $OutputItem | ? {$_.VMName -eq $VMName}
      } else {
        $OutputItem
      }
    }
}

Function Write-SnapInfo {
  Param(
    [Parameter(Mandatory=$true)]$VMName,
    [Parameter(Mandatory=$true)]$DiskNum,
    [Parameter(Mandatory=$true)]$SnapGUID,
    [Parameter(Mandatory=$true)]$PrimaryUri,
    [Parameter(Mandatory=$true)]$SnapshotUri,
    [Parameter(Mandatory=$true)]$SnapshotName,
    $SnapshotDescription="",
    [Parameter(Mandatory=$true)]$StorageContext
  )
  $TableName = "AzureVMSnapshots"
  $SnapTable = Get-StorageTable -TableName $TableName -StorageContext $StorageContext

    $entity = New-Object "Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity" `
      $SnapGUID, $DiskNum

    $entity.Properties.Add("VMName", $VMName)
    $entity.Properties.Add("BaseURI", $PrimaryUri)
    $entity.Properties.Add("SnapshotURI", $SnapshotUri)
    $entity.Properties.Add("SnapshotName", $SnapshotName)
    $entity.Properties.Add("SnapshotDescription", $SnapshotDescription)
    $entity.Properties.Add("SnapshotTime", ((Get-Date).ToString()))
    $result = $SnapTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Insert($entity))
}

#TODO: Write Clear-SnapInfo($GUID) Function

Function Get-DiskInfo {
    Param([Parameter(Mandatory=$true)]$DiskUri) 
    
    $DiskInfo = "" | Select Uri, StorageAccountName, VHDName, ContainerName
    $DiskInfo.Uri = $DiskUri
    $DiskInfo.StorageAccountName = ($DiskUri -split "https://")[1].Split(".")[0]
    $DiskInfo.VHDName = $DiskUri.Split("/")[-1]
    $DiskInfo.ContainerName = $DiskUri.Split("/")[-2]
    Return $DiskInfo		
}

Function Get-StorageContextForUri {
    Param([Parameter(Mandatory=$true)]$DiskUri) 
			
	$DiskInfo = Get-DiskInfo -DiskUri $DiskUri
				
	$StorageAccountResource = find-azurermresource `
        -ResourceNameContains $DiskInfo.StorageAccountName `
         -WarningAction Ignore

	$StorageKey = Get-AzureRmStorageAccountKey `
        -Name $StorageAccountResource.Name `
        -ResourceGroupName $StorageAccountResource.ResourceGroupName

	$StorageContext = New-AzureStorageContext `
        -StorageAccountName $StorageAccountResource.Name `
        -StorageAccountKey $StorageKey[0].Value

    return $StorageContext
}
