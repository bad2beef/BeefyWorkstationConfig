########
# Configure
########
$DisabledExecutableFileTypes = @(
    'batfile',
    'cmdfile',
    'comfile',
    'htafile',
    'inffile',
    'JobObject',
    'JSEFile',
    'JSFile',
    'Microsoft.PowerShellConsole.1',
    'Microsoft.PowerShellData.1',
    'Microsoft.PowerShellModule.1',
    'Microsoft.PowerShellScript.1',
    'Microsoft.PowerShellXMLData.1',
    'regfile',
    'scrfile',
    'scriptletfile',
    'SHCmdFile',
    'VBEFile',
    'VBSFile',
    'VisualStudio.vb.14.0',
    'Windows.CompositeFont',
    'WSFFile',
    'WSHFile'
)

$DisabledWindowsOptionalFeatures = @(
    'MicrosoftWindowsPowerShellV2',
    'MicrosoftWindowsPowerShellV2Root',
    'SMB1Protocol-Client',
    'SMB1Protocol-Server',
    'SMB1Protocol'
)

$DisabledServices = @(
    'iphlpsvc',
    'NetTcpPortSharing',
    'RasMan',
    'RemoteRegistry'
)

$HardenPerUser = {
    Set-ItemProperty -Force -Name 'WpadOverride' -Value 1 -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad'

    Set-ItemProperty -Force -Name 'HideFileExt' -Value 0 -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-ItemProperty -Force -Name 'HideDrivesWithNoMedia' -Value 0 -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    Set-ItemProperty -Force -Name 'Enabled' -Value 0 -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
}

$Configuration =
@{
    AllNodes =
    @(
        # Default data. DO NOT MODIFY.
        @{
            NodeName                        = '*'
            DisabledExecutableFileTypes     = $DisabledExecutableFileTypes
            DisabledWindowsOptionalFeatures = $DisabledWindowsOptionalFeatures
            DisabledServices                = $DisabledServices
            EnforceExecutableFileTypes      = $true
            EnforceWindowsOptionalFeatures  = $true
            EnforceServices                 = $true
            EnforceWindowsUpdate            = $true
            EnforceEventLog                 = $true
            EnforceIEESC                    = $true
            EnforceNBTCPIP                  = $true
        },

        # Node 'localhost'. OVERRIDE HERE.
        @{
            NodeName                        = 'localhost'
        }
    )
}


########
# DSC Configuration
########
[DSCLocalConfigurationManager()]
Configuration BeefyWorkstationConfigLCM
{
    Node localhost
    {
        Settings
        {
            ConfigurationMode              = 'ApplyAndAutoCorrect'
            ConfigurationModeFrequencyMins = 90
        }
    }
}

Configuration BeefyWorkstationConfig
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xSystemSecurity
    Import-DscResource -ModuleName xWindowsUpdate
    Import-DscResource -ModuleName xWinEventLog

    #### Base OS
    Node $AllNodes.Where{ $_.EnforceExecutableFileTypes }.NodeName
    {
        # Force executable file types listed in configuration to open via edit command by default.
        $Node.DisabledExecutableFileTypes.ForEach({
            Registry $_
            {
                Ensure    = 'Present'
                Key       = ( 'HKEY_CLASSES_ROOT\{0}\shell' -f $_ )
                ValueName = '(Default)'
                ValueData = 'edit'
            }
        })
    }

    Node $AllNodes.Where{ $_.EnforceWindowsOptionalFeatures }.NodeName
    {
        # Disable / remove Windows Optional Features listed in configuration.
        $Node.DisabledWindowsOptionalFeatures.ForEach({
            WindowsOptionalFeature $_
            {
                Ensure    = 'Disable'
                Name      =  $_
            }
        })
    }

    Node $AllNodes.Where{ $_.EnforceServices }.NodeName
    {
        # Stop / Disable risky Services
        $Node.DisabledServices.ForEach({
            Service $_
            {
                State       = 'Stopped'
                StartupType = 'Disabled'
                Name        =  $_
            }
        })
    }

    Node $AllNodes.Where{ $_.EnforceWindowsUpdate }.NodeName
    {
        # Force Windows Update to be enabled and install Security and Important updates.
        xWindowsUpdateAgent WindowsUpdate
        {
            Category         = @( 'Security', 'Important', 'Optional' )
            Notifications    = 'ScheduledInstallation'
            Source           = 'MicrosoftUpdate' # Or WindowsUpdate for Windows-only
            UpdateNow        = $true
            IsSingleInstance = 'Yes'
        }
    }

    Node $AllNodes.Where{ $_.EnforceEventLog }.NodeName
    {
        # Set event log sizes
        xWinEventLog EventLogApplication
        {
            LogName            = 'Application'
            IsEnabled          = $true
            LogMode            = 'Circular'
            MaximumSizeInBytes = 32mb
        }
        xWinEventLog EventLogSystem
        {
            LogName            = 'System'
            IsEnabled          = $true
            LogMode            = 'Circular'
            MaximumSizeInBytes = 32mb
        }
        xWinEventLog EventLogSecurity
        {
            LogName            = 'Security'
            IsEnabled          = $true
            LogMode            = 'Circular'
            MaximumSizeInBytes = 196mb
        }
    }

    Node $AllNodes.Where{ $_.IEESC }.NodeName
    {
        # Force enable IE ESC.
        xIEEsc IEESCAdministrators
        {
            UserRole = 'Administrators'
            IsEnabled = $true
        }
        xIEEsc IEESCUsers
        {
            UserRole = 'Users'
            IsEnabled = $true
        }
    }

    #### Network
    # Aggregate actions over all adapters blindly rather than trying to generate a list of adapters and configs at compile time.
    Node $AllNodes.Where{ $_.EnforceNBTCPIP }.NodeName
    {
        Script NetBIOS
        {
            GetScript = {
                @{ 'Result' = [System.Convert]::ToBoolean( ( Get-WmiObject -Class 'win32_networkadapterconfiguration' | ForEach-Object { $_.TcpipNetbiosOptions } | Measure-Object -Sum ).Sum ).ToString() }
            }

            SetScript = {
                Get-WmiObject -Class 'win32_networkadapterconfiguration' | ForEach-Object { $_.SetTcpipNetbios(2) } | Out-Null
            }

            TestScript = {
                [System.Convert]::ToBoolean( ( Get-WmiObject -Class 'win32_networkadapterconfiguration' | ForEach-Object { $_.TcpipNetbiosOptions } | Measure-Object -Sum ).Sum )
            }
        }
    }
    

    #### Untoggable items.
    Node $AllNodes.NodeName
    {
        #### GUI
        # Force enable UAC.
        xUAC UAC
        {
            Setting = 'AlwaysNotify'
        }

        # Disable Start menu web search.
        Registry DisableWebConnectedSearch
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            ValueName = 'ConnectedSearchUseWeb'
            ValueData = 0
        }
        Registry DisableWebSearch
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            ValueName = 'DisableWebSearch'
            ValueData = 1
        }

        # Enable Ctrl+Alt+Del
        Registry DisableCad
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            ValueName = 'DisableCad'
            ValueData = 0
        }

        # Disable untrsuted fonts
        Registry MitigationOptions
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel'
            ValueName = 'MitigationOptions'
            ValueData = 1000000000000
        }

        #### Network
        # Disable "Delivery Optimization" P2P Windows Updates
        Registry DownloadMode
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'
            ValueName = 'DownloadMode'
            ValueData = 0
        }

        # Disable DCOM
        Registry EnableDCOM
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Ole'
            ValueName = 'EnableDCOM'
            ValueData = 'N'
        }

        # Force NTLMv2 only
        Registry LmCompatibilityLevel
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa'
            ValueName = 'LmCompatibilityLevel'
            ValueData = 5
        }

        # Disable WPAD Service
        Service WinHttpAutoProxySvc
        {
            Ensure      = 'Present'
            Name        = 'dmwappushservice'
            StartupType = 'Disabled'
            State       = 'Stopped'
        }
        
        #### Privacy
        # Disable Telemetry
        Registry AllowTelemetry
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            ValueName = 'AllowTelemetry'
            ValueData = 0
        }

        # Disable Telemetry Service
        Service dmwappushservice
        {
            Ensure      = 'Present'
            Name        = 'dmwappushservice'
            StartupType = 'Disabled'
            State       = 'Stopped'
        }

        #### Per-User scripts. *SHOULD* be safe, assuming SYSTEM creates this directory first.
        File HardenPerUserDirectory
        {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = [System.Environment]::ExpandEnvironmentVariables( '%ALLUSERSPROFILE%\HardenWindows10' )
        }
        File HardenPerUserScript
        {
            DependsOn       = '[File]HardenPerUserDirectory'
            Ensure          = 'Present'
            Type            = 'File'
            DestinationPath = [System.Environment]::ExpandEnvironmentVariables( '%ALLUSERSPROFILE%\HardenWindows10\HardenWindows10PerUser.ps1' )
            Contents        = $HardenPerUser.toString()
        }
        Registry HardenPerUserScript
        {
            DependsOn = '[File]HardenPerUserScript'
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            ValueName = 'HardenWindows10'
            ValueData = '{0} -Exec Bypass -NonI -NoP -Win Hidden -File "{1}"' -f @( ( Get-Command -Name powershell.exe ).Path, [System.Environment]::ExpandEnvironmentVariables( '%ALLUSERSPROFILE%\HardenWindows10\HardenWindows10PerUser.ps1' )  )
        }
    }
}
