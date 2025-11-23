# Administrator-Rechte prüfen
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Dieses Skript benötigt Administrator-Rechte!" -ForegroundColor Red
    Write-Host "Bitte PowerShell als Administrator ausführen." -ForegroundColor Yellow
    exit
}

Write-Host "Suche nach Adobe und Creative Cloud Prozessen und Diensten..." -ForegroundColor Cyan

# Erweiterte Liste von Adobe und Creative Cloud Prozessnamen
$adobeProcessPatterns = @(
    "*adobe*", "*acrobat*", "*photoshop*", "*illustrator*", "*premiere*", "*aftereffects*", 
    "*creative*cloud*", "*ccxprocess*", "*coresync*", "*cclibrary*", "*ccleaner*", 
    "*adobeipc*", "*aam*", "*adobegc*", "*ccxprocess*", "*adobe desktop service*",
    "*adobecc*", "*accc*", "*adobe camera raw*", "*adobe media encoder*"
)

# 1. Laufende Adobe und Creative Cloud Prozesse finden
Write-Host "`n=== Laufende Adobe/Creative Cloud Prozesse ===" -ForegroundColor Yellow
$adobeProcesses = Get-Process | Where-Object { 
    $processName = $_.ProcessName.ToLower()
    $adobeProcessPatterns | ForEach-Object { $processName -like $_ }
} | Sort-Object ProcessName

if ($adobeProcesses) {
    $adobeProcesses | Format-Table ProcessName, Id, CPU, WorkingSet -AutoSize
    $totalMemory = ($adobeProcesses | Measure-Object -Property WorkingSet -Sum).Sum / 1MB
    Write-Host "Gesamter Speicherverbrauch: $([math]::Round($totalMemory, 2)) MB" -ForegroundColor Magenta
} else {
    Write-Host "Keine Adobe/Creative Cloud Prozesse gefunden." -ForegroundColor Green
}

# 2. Adobe und Creative Cloud Dienste finden
Write-Host "`n=== Adobe/Creative Cloud Dienste ===" -ForegroundColor Yellow
$servicePatterns = @("*adobe*", "*creative*", "*acrobat*", "*cc*")
$adobeServices = Get-Service | Where-Object { 
    $serviceName = $_.Name.ToLower()
    $displayName = $_.DisplayName.ToLower()
    $servicePatterns | ForEach-Object { $serviceName -like $_ -or $displayName -like $_ }
} | Sort-Object DisplayName

if ($adobeServices) {
    $adobeServices | Format-Table Name, DisplayName, Status, StartType -AutoSize
} else {
    Write-Host "Keine Adobe/Creative Cloud Dienste gefunden." -ForegroundColor Green
}

# 3. Autostart-Einträge von Adobe und Creative Cloud finden
Write-Host "`n=== Adobe/Creative Cloud Autostart-Einträge ===" -ForegroundColor Yellow

# Registry Autostart-Pfade
$registryPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run", 
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

$adobeStartupEntries = @()
foreach ($path in $registryPaths) {
    if (Test-Path $path) {
        Get-ItemProperty $path | ForEach-Object {
            $props = $_.PSObject.Properties | Where-Object { 
                $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider") -and
                ($_.Value -like "*adobe*" -or $_.Value -like "*acrobat*" -or $_.Value -like "*creative*cloud*" -or 
                 $_.Value -like "*cc*" -or $_.Name -like "*adobe*" -or $_.Name -like "*acrobat*" -or 
                 $_.Name -like "*creative*" -or $_.Name -like "*cc*")
            }
            foreach ($prop in $props) {
                $adobeStartupEntries += [PSCustomObject]@{
                    RegistryPath = $path
                    EntryName = $prop.Name
                    EntryValue = $prop.Value
                }
            }
        }
    }
}

# Startup-Ordner durchsuchen
$startupFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"
)

foreach ($folder in $startupFolders) {
    if (Test-Path $folder) {
        Get-ChildItem $folder -File | Where-Object { 
            $_.Name -like "*adobe*" -or $_.Name -like "*acrobat*" -or $_.Name -like "*creative*" -or $_.Name -like "*cc*"
        } | ForEach-Object {
            $adobeStartupEntries += [PSCustomObject]@{
                RegistryPath = "File System"
                EntryName = $_.Name
                EntryValue = $_.FullName
            }
        }
    }
}

# Geplante Tasks für Adobe/Creative Cloud
Write-Host "`n=== Adobe/Creative Cloud Geplante Tasks ===" -ForegroundColor Yellow
$adobeTasks = Get-ScheduledTask | Where-Object { 
    $_.TaskName -like "*adobe*" -or $_.TaskName -like "*creative*" -or $_.TaskName -like "*acrobat*" -or $_.TaskName -like "*cc*"
} | Where-Object { $_.State -eq "Ready" }

if ($adobeTasks) {
    $adobeTasks | Format-Table TaskName, State -AutoSize
} else {
    Write-Host "Keine Adobe/Creative Cloud geplanten Tasks gefunden." -ForegroundColor Green
}

if ($adobeStartupEntries) {
    $adobeStartupEntries | Format-Table RegistryPath, EntryName, EntryValue -AutoSize
} else {
    Write-Host "Keine Adobe/Creative Cloud Autostart-Einträge gefunden." -ForegroundColor Green
}

# 4. Bestätigung für das Beenden und Deaktivieren
if (-NOT ($adobeProcesses -or $adobeServices -or $adobeStartupEntries -or $adobeTasks)) {
    Write-Host "`nKeine Adobe/Creative Cloud Komponenten gefunden, die bearbeitet werden können." -ForegroundColor Yellow
    exit
}

Write-Host "`nMöchten Sie:" -ForegroundColor Cyan
Write-Host "1. Adobe/Creative Cloud Prozesse und Dienste SOFORT beenden" -ForegroundColor White
Write-Host "2. Adobe/Creative Cloud Autostart DEAKTIVIEREN (für zukünftige Starts)" -ForegroundColor White
Write-Host "3. BEIDES: Sofort beenden UND Autostart deaktivieren" -ForegroundColor White
Write-Host "4. Abbrechen" -ForegroundColor White

$choice = Read-Host "`nIhre Wahl (1-4)"

if ($choice -eq "4") {
    Write-Host "Vorgang abgebrochen." -ForegroundColor Yellow
    exit
}

# 5. Prozesse und Dienste beenden (wenn gewählt)
if ($choice -in @("1", "3")) {
    Write-Host "`nBeende Adobe/Creative Cloud Prozesse..." -ForegroundColor Yellow
    
    # Creative Cloud Prozesse zuerst sanft beenden
    $ccProcesses = $adobeProcesses | Where-Object { $_.ProcessName -like "*creative*cloud*" -or $_.ProcessName -like "*cc*" }
    if ($ccProcesses) {
        Write-Host "Versuche Creative Cloud Prozesse sanft zu beenden..." -ForegroundColor Yellow
        foreach ($process in $ccProcesses) {
            try {
                # Zuerst versuchen, den Prozess normal zu beenden
                $process.CloseMainWindow() | Out-Null
                Start-Sleep -Seconds 2
                if (!$process.HasExited) {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    Write-Host "Prozess beendet: $($process.ProcessName) (PID: $($process.Id))" -ForegroundColor Green
                }
            } catch {
                Write-Host "Konnte Prozess nicht beenden: $($process.ProcessName) (PID: $($process.Id))" -ForegroundColor Red
            }
        }
    }
    
    # Andere Adobe Prozesse beenden
    $otherProcesses = $adobeProcesses | Where-Object { $_.ProcessName -notlike "*creative*cloud*" -and $_.ProcessName -notlike "*cc*" }
    if ($otherProcesses) {
        foreach ($process in $otherProcesses) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Write-Host "Prozess beendet: $($process.ProcessName) (PID: $($process.Id))" -ForegroundColor Green
            } catch {
                Write-Host "Konnte Prozess nicht beenden: $($process.ProcessName) (PID: $($process.Id))" -ForegroundColor Red
            }
        }
    }
    
    # Dienste stoppen
    if ($adobeServices) {
        foreach ($service in $adobeServices) {
            try {
                if ($service.Status -eq "Running") {
                    Stop-Service -Name $service.Name -Force -ErrorAction Stop
                    Write-Host "Dienst gestoppt: $($service.DisplayName)" -ForegroundColor Green
                }
            } catch {
                Write-Host "Konnte Dienst nicht stoppen: $($service.DisplayName)" -ForegroundColor Red
            }
        }
    }
}

# 6. Autostart deaktivieren (wenn gewählt)
if ($choice -in @("2", "3")) {
    Write-Host "`nDeaktiviere Adobe/Creative Cloud Autostart..." -ForegroundColor Yellow
    
    # Registry-Einträge deaktivieren
    if ($adobeStartupEntries) {
        foreach ($entry in $adobeStartupEntries) {
            if ($entry.RegistryPath -ne "File System") {
                try {
                    # Eintrag sichern und dann löschen
                    $backupPath = "HKCU:\Software\AdobeStartupBackup"
                    if (-not (Test-Path $backupPath)) {
                        New-Item -Path $backupPath -Force | Out-Null
                    }
                    $originalValue = Get-ItemProperty -Path $entry.RegistryPath -Name $entry.EntryName -ErrorAction SilentlyContinue
                    if ($originalValue) {
                        Set-ItemProperty -Path $backupPath -Name $entry.EntryName -Value $originalValue.$($entry.EntryName) -Force
                    }
                    
                    Remove-ItemProperty -Path $entry.RegistryPath -Name $entry.EntryName -Force -ErrorAction Stop
                    Write-Host "Autostart deaktiviert: $($entry.EntryName)" -ForegroundColor Green
                } catch {
                    Write-Host "Konnte Autostart nicht deaktivieren: $($entry.EntryName)" -ForegroundColor Red
                }
            } else {
                # Dateien im Startup-Ordner umbenennen
                try {
                    $newName = "$($entry.EntryName).disabled"
                    Rename-Item -Path $entry.EntryValue -NewName $newName -Force -ErrorAction Stop
                    Write-Host "Autostart deaktiviert: $($entry.EntryName)" -ForegroundColor Green
                } catch {
                    Write-Host "Konnte Autostart nicht deaktivieren: $($entry.EntryName)" -ForegroundColor Red
                }
            }
        }
    }
    
    # Adobe-Dienste auf "manuell" setzen
    if ($adobeServices) {
        foreach ($service in $adobeServices) {
            try {
                Set-Service -Name $service.Name -StartupType Manual -ErrorAction Stop
                Write-Host "Dienst auf manuell gesetzt: $($service.DisplayName)" -ForegroundColor Green
            } catch {
                Write-Host "Konnte Dienst-Starttyp nicht ändern: $($service.DisplayName)" -ForegroundColor Red
            }
        }
    }
    
    # Geplante Tasks deaktivieren
    if ($adobeTasks) {
        foreach ($task in $adobeTasks) {
            try {
                Disable-ScheduledTask -TaskName $task.TaskName -ErrorAction Stop
                Write-Host "Geplanten Task deaktiviert: $($task.TaskName)" -ForegroundColor Green
            } catch {
                Write-Host "Konnte geplanten Task nicht deaktivieren: $($task.TaskName)" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`nVorgang abgeschlossen!" -ForegroundColor Cyan
Write-Host "`nWichtige Hinweise:" -ForegroundColor Yellow
Write-Host "- Creative Cloud startet nicht mehr automatisch mit Windows" -ForegroundColor White
Write-Host "- Adobe-Anwendungen funktionieren weiterhin bei manuellem Start" -ForegroundColor White
Write-Host "- Um Creative Cloud manuell zu starten: Startmenü > Adobe Creative Cloud" -ForegroundColor White
Write-Host "- Backup der Autostart-Einträge wurde unter HKCU:\Software\AdobeStartupBackup gespeichert" -ForegroundColor White
