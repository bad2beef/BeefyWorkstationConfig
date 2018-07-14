
Param
(
    [String]$Inventory = '.\Install-Software.json',
    [Switch]$SkipChoco,
    [Switch]$SkipCode
)


$Software = Get-Content -Path $Inventory | ConvertFrom-Json

If ( -not $SkipChoco )
{
    $Chocolatey = $Null
    $Chocolatey = Get-Command -Name 'choco' -ErrorAction SilentlyContinue

    If ( -not $Chocolatey )
    {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression -Command (  (New-Object -TypeName System.Net.WebClient).DownloadString( 'https://chocolatey.org/install.ps1' ) ) # Dangerous!
    }

    Get-Member -InputObject $Software.'choco-install' -MemberType NoteProperty | ForEach-Object {
        $Version = $_.Definition.Split('=')[1]
        If ( $Version -notlike 'latest' )
        {
            choco install $_.Name --version $Version --yes
            choco pin add --name $_.Name --version $Version
        }
        Else
        {
            choco install $_.Name --yes
        }
    }
    
    $env:PATH = Get-ItemProperty -Path 'HKLM:System\CurrentControlSet\Control\Session Manager\Environment' -Name Path
}

If ( -not $SkipCode )
{
    $Software.'code-install' | ForEach-Object {
        code --install-extension $_
    }
}
