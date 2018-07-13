
Try
{
    $Choco = Get-Command -Name 'choco'
}
Catch
{
    Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) # Dangerous!
}

$Software = Get-Content -Path .\Install-Software.json | ConvertFrom-Json
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

Get-Member -InputObject $Software.'vscode-install' -MemberType NoteProperty | ForEach-Object {
    code --install-extension $_
}
