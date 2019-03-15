clear

$ErrorActionPreference = "Continue"

function Get-Commands {

    [OutputType([PSCustomObject])]

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$path
    )

    if(-Not (Test-Path $path -PathType leaf)) {
        throw "Configuration file could not be found";
    }

    $config = Get-Content -Raw -Path $path | ConvertFrom-Json;

    return $config;
}

function Check-Connection {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerIdentifier,
        [Parameter(Mandatory=$true, Position=1)][int]$count
    )

    Write-Host "[ INFO ] - Network Connection Check: $($computerIdentifier)" -ForeGroundColor Yellow
    Write-Host ""
    Test-Connection -ComputerName $computerIdentifier -Count $count
    
}

function Check-Services {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerIdentifier,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$services
    )

    Write-Host "[ INFO ] - Windows Service Check: $($computerIdentifier)" -ForeGroundColor Yellow;
    Write-Host ""

    foreach($service in $services) {
        $svc = Get-Service -ComputerName $computerIdentifier -Name $service.name | Select-Object Status;

        if($svc.Status -eq $service.expectedStatus) {
            Write-Host "[  OK  ] - $($service.name) ($($svc.Status))" -ForeGroundColor Green;
        } else {
            if($svc.Status -eq $null) {
                Write-Host "[  ER  ] - $($service.name) (Not Found)" -ForeGroundColor Red;
            } else {
                Write-Host ([string]::Format("[  ER  ] - {0} ({1}) - Expected to be ({2})", $service.name, $svc.Status, $service.expectedStatus)) -ForeGroundColor Red;
            }
        }
    }
}

function Check-SqlConnection {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerName,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$instances
    )

    Write-Host "[ INFO ] - SQL Connection Check: $($computerName)" -ForeGroundColor Yellow
    Write-Host ""

    foreach($instance in $instances) {

        $sqlInstance = [string]::Format("{0}{1}", $computerName, $instance.name);

        if($instance.port -ne $null -and $instance.port -ne 0) {
            $sqlInstance = $sqlInstance + [string]::Format(",{0}", $instance.port);
        }

        $conString = [string]::Format("Data Source={0};Initial Catalog=master;Trusted_Connection={1};", $sqlInstance, $instance.trustedConnection);

        if(-Not $instance.trustedConnection) {
            if($instance.user -eq $null -or $instance.password -eq $null) {
                throw "User name and password must be provided for SQL Server connection verification";
            } else {
                $conString = $conString + [string]::Format("User ID={0};Password={1};", $instance.user, $instance.password);
            }
        }

        try {

            $con = New-Object System.Data.SqlClient.SqlConnection($conString);
            $con.Open();

            Write-Host ([string]::Format("[  OK  ] - Connected to {0}", $sqlInstance)) -ForeGroundColor Green;

        } catch {
            Write-Host ([string]::Format("[  ER  ] - Failed to connect to {0}", $sqlInstance)) -ForeGroundColor Red;
            Write-Host ""
            Write-Host ($_.Exception.Message) -ForeGroundColor Red;
            Write-Host ""
        } finally {
            if($con.State -eq "Open") {
                $con.Close();
            }
        }
    }
}

function Check-Ports {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerIdentifier,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$ports
    )

    Write-Host "[ INFO ] - Port Accessibility Check: $($computerIdentifier)" -ForeGroundColor Yellow
    Write-Host ""

    foreach($port in $ports) {
        
        $client = New-Object Net.Sockets.TcpClient;

        try {

            $client.Connect($computerIdentifier,$port.port);

        } catch {

            if($port.expectedStatus -eq "Open") {
                Write-Host ([string]::Format("[  ER  ] - {0} - Failed to connect", $port.port)) -ForeGroundColor Red;
                Write-Host ""
                Write-Host ($_.Exception.Message) -ForeGroundColor Red;
                Write-Host ""
            } else {
                Write-Host ([string]::Format("[  OK  ] - {0} - Connection denied", $port.port)) -ForeGroundColor Green;
            }
        }

        if($client.Connected) {
            $client.Close();

            if($port.expectedStatus -eq "Closed") {
                Write-Host ([string]::Format("[  ER  ] - {0} - Port accepted connection, but expected to be 'Closed'", $port.port)) -ForeGroundColor Red;
            } else {
                Write-Host ([string]::Format("[  OK  ] - {0} - Connection successful", $port.port)) -ForeGroundColor Green;
            }
        }
    }
}

function Check-SharedObject {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerName,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$objects
    )

    Write-Host "[ INFO ] - Shared Object Check: $($computerName)" -ForeGroundColor Yellow
    Write-Host ""

    foreach($object in $objects) {

        $path = [string]::Format("\\{0}{1}", $computerName, $object.path);

        [bool]$objectExists = [System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path);

        if($objectExists -eq $object.expected) {
            Write-Host ([string]::Format("[  OK  ] - Check object: {0}", $path)) -ForeGroundColor Green;
        } else {
            if($object.expected) {
                Write-Host ([string]::Format("[  ER  ] - Object not found: {0}", $path)) -ForeGroundColor Red;
            } else {
                Write-Host ([string]::Format("[  ER  ] - Invalid object found: {0}", $path)) -ForeGroundColor Red;
            }
        }
    }
}

$commands = Get-Commands ([IO.Path]::GetFullPath("$($PSScriptRoot)\config.json"))

foreach($command in $commands) {

    Write-Host ":::::::::::::::::::::::::::::::::::::::::::::::: $($command.description) ::::::::::::::::::::::::::::::::::::::::::::::::" -ForeGroundColor Yellow
    Write-Host ""

    if($command.connectionChecks -ne $null -and $command.connectionChecks.length -gt 0) {
        foreach($check in $command.connectionChecks) {
            if($check.active) {
                Check-Connection $check.host $check.count;
                Write-Host ""
            }
        }
    }

    if($command.serviceChecks -ne $null -and $command.serviceChecks.length -gt 0) {
        foreach($check in $command.serviceChecks) {
            if($check.active) {
                Check-Services $check.host $check.services;
                Write-Host ""
            }
        }
    }

    if($command.portChecks -ne $null -and $command.portChecks.length -gt 0) {
        foreach($check in $command.portChecks) {
            if($check.active) {
                Check-Ports $check.host $check.ports;
                Write-Host ""
            }
        }
    }

    if($command.sqlChecks -ne $null -and $command.sqlChecks.length -gt 0) {
        foreach($check in $command.sqlChecks) {
            if($check.active) {
                Check-SqlConnection $check.host $check.instances;
                Write-Host ""
            }
        }
    }

    if($command.sharedObjectChecks -ne $null -and $command.sharedObjectChecks.length -gt 0) {
        foreach($check in $command.sharedObjectChecks) {
            if($check.active) {
                Check-SharedObject $check.host $check.objects;
                Write-Host ""
            }
        }
    }
}

# Read-Host -Prompt "Press Enter to exit"