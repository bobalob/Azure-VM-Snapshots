# Azure-VM-Snapshots
Powershell Functions for Creating Azure RM VM Snapshots


Usage:

    C:\> . .\AzureSnapFunctions.PS1

Create a New snapshot for all VHDs in a VM

    C:\> Snap-AzureRMVM -VMName MyVM


View the snapshots for all VHDs on a VM

    C:\> Get-AzureRMVMSnap -VMName MyVM


Delete all snapshots for all VHDs on a VM

    C:\> Delete-AzureRMVMSnap -VMName MyVM

Coming soon... Revert functionality which will create a new VM an attach rolled back disks. I also plan to allow the user to select which snapshots to delete based on a date range or similar filters.
