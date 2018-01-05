########
# Execute
########
# Prerequisites
Write-Host 'Setting prerequisite settings.'
If ( ( Get-ExecutionPolicy -Scope LocalMachine ) -in @( 'Default', 'Restricted', 'Undefined' ) )
{
    Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
}

If ( ( Get-PSRepository -Name 'PSGallery' ).InstallationPolicy -notlike 'Trusted' )
{
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
}

If ( ( Get-PackageProvider | Select-Object -ExpandProperty Name ) -notcontains 'NuGet' )
{
    Install-PackageProvider -Name NuGet
}

Write-Host 'Installing required DSC modules.'
$ModuleList = Get-Module -ListAvailable | Select-Object -ExpandProperty Name
If ( $ModuleList -notcontains 'xSystemSecurity' ){ Install-Module -Name xSystemSecurity }
If ( $ModuleList -notcontains 'xWindowsUpdate' ){ Install-Module -Name xWindowsUpdate }
If ( $ModuleList -notcontains 'xWinEventLog' ){ Install-Module -Name xWinEventLog }

# Build configuration
Write-Host 'Sourcing configuration.'
. .\BeefyWorkstationConfig.ps1

# Compile and manually deploy locally, in case WinRM isn't available. https://blogs.technet.microsoft.com/pstips/2017/03/01/using-dsc-with-the-winrm-service-disabled/
Write-Host 'Building LCM configuration.'
BeefyWorkstationConfigLCM | Out-Null

Write-Host "`tInstalling."
$ConfigurationLCM = [Byte[]][System.IO.File]::ReadAllBytes( ( Resolve-Path -Path '.\BeefyWorkstationConfigLCM\localhost.meta.mof' ) )
Invoke-WmiMethod -Namespace 'root/Microsoft/Windows/DesiredStateConfiguration' -Class 'MSFT_DSCLocalConfigurationManager' -Name 'SendMetaConfigurationApply' -ArgumentList @( $ConfigurationLCM, [System.UInt32]1 )

Write-Host 'Building node configuration.'
BeefyWorkstationConfig -ConfigurationData $Configuration | Out-Null

Write-Host "`tInstalling."
$Configuration = [Byte[]][System.IO.File]::ReadAllBytes( ( Resolve-Path -Path '.\BeefyWorkstationConfig\localhost.mof' ) )
Invoke-WmiMethod -Namespace 'root/Microsoft/Windows/DesiredStateConfiguration' -Class 'MSFT_DSCLocalConfigurationManager' -Name 'SendConfigurationApply' -ArgumentList @( $Configuration, [System.UInt32]1 )

Write-Host 'Forcing additional configuration run.'
Invoke-WmiMethod -Namespace 'root/Microsoft/Windows/DesiredStateConfiguration' -Class 'MSFT_DSCLocalConfigurationManager' -Name 'ApplyConfiguration' -ArgumentList @( [bool]$true )

Write-Host 'Done.'
