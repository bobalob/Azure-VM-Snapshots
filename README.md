# Azure-VM-Snapshots
Powershell Functions for Creating and Reverting to Azure RM VM Snapshots.

The functions handle multiple disk VMs by saving meta-data to an Azure Table on the OS disk's storage account.

**It is inadvisable to use this on a production VM. The revert function will delete your VM configuration and recreate it using the same settings. It's possible that the script may cause unintended results.**

There are quite a few edge cases that this script will miss. Premium disks are not supported as they do not support Azure Table storage which is required for the script to save it's metadata.

It also won't play nice if disks are removed from the VM after a snap is taken.

Examples:

Load the functions, you will also need to login to your Azure account

    C:\> . .\AzureSnapFunctions.PS1
    C:\> Login-AzureRMAccount

Create a New snapshot for all VHDs in a VM

    C:\> New-AzureRMVMSnap -VMName MyVM -SnapshotName "Foo"


View the snapshots for all VHDs on a VM

    C:\> Get-AzureRMVMSnap -VMName MyVM


Delete all snapshots for all VHDs on a VM

    C:\> Delete-AzureRMVMSnap -VMName MyVM -Force
    

Revert to a snapshots for all VHDs on a VM - This will remove the VM and recreate it using the reverted disk.

    C:\> Revert-AzureRMVMSnap -VMName MyVM

