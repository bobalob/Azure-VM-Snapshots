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

