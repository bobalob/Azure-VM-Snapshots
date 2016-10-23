# Azure-VM-Snapshots
Powershell Functions for Creating Azure RM VM Snapshots

**DO NOT USE THIS ON A PRODUCTION VM!**

Usage:

Load the functions

    C:\> . .\AzureSnapFunctions.PS1

Create a New snapshot for all VHDs in a VM (VM Should be powered down)

    C:\> New-AzureRMVMSnap -VMName MyVM


View the snapshots for all VHDs on a VM

    C:\> Get-AzureRMVMSnap -VMName MyVM


Delete all snapshots for all VHDs on a VM

    C:\> Delete-AzureRMVMSnap -VMName MyVM -Force
    

Revert to a snapshots for all VHDs on a VM (VM Must be powered down)

    C:\> Revert-AzureRMVMSnap -VMName MyVM

