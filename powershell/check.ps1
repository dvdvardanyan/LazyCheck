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

    Write-Host "[ INFO ] - Network Connection Check: $($computerIdentifier)" -ForeGroundColor White;
    Write-Host "";
    Test-Connection -ComputerName $computerIdentifier -Count $count
    
}

function Check-Services {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerIdentifier,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$services
    )

    Write-Host "[ INFO ] - Windows Service Check: $($computerIdentifier)" -ForeGroundColor White;
    Write-Host "";

    foreach($service in $services) {
        $svc = Get-Service -ComputerName $computerIdentifier -Name $service.name | Select-Object Status;

        if($svc.Status -eq $service.expectedStatus) {
            Write-Host "[ PASS ] - $($service.name) ($($svc.Status))" -ForeGroundColor Green;
        } else {
            if($svc.Status -eq $null) {
                Write-Host "[ FAIL ] - $($service.name) (Not Found)" -ForeGroundColor Red;
            } else {
                Write-Host ([string]::Format("[ FAIL ] - {0} ({1}) - Expected to be ({2})", $service.name, $svc.Status, $service.expectedStatus)) -ForeGroundColor Red;
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

    Write-Host "[ INFO ] - SQL Connection Check: $($computerName)" -ForeGroundColor White;
    Write-Host "";

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

            Write-Host ([string]::Format("[ PASS ] - Connected to {0}", $sqlInstance)) -ForeGroundColor Green;

        } catch {
            Write-Host ([string]::Format("[ FAIL ] - Failed to connect to {0}", $sqlInstance)) -ForeGroundColor Red;
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

function Check-SqlCommand {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerName,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$instance,
        [Parameter(Mandatory=$true, Position=2)][string]$command,
        [Parameter(Mandatory=$true, Position=3)][PSCustomObject]$checks,
		[Parameter(Mandatory=$true, Position=4)][string]$description
    )

    $sqlInstance = [string]::Format("{0}{1}", $computerName, $instance.name);
	
	Write-Host "[ INFO ] - $($description) on $($sqlInstance)" -ForeGroundColor White;
    Write-Host "";

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

        if($checks.length -gt 0) {

            $result = @{};

            foreach($check in $checks) {
                if($check.column -ne $null) {
                    $result.Add($check.column, @());
                }
            }

            $con = New-Object System.Data.SqlClient.SqlConnection($conString);
            $con.Open();

            $cmd = $con.CreateCommand();
            $cmd.CommandText = $command;

            [int]$recordsCount = 0;

            $reader = $cmd.ExecuteReader();

            if($reader.HasRows) {
                while ($reader.Read()) {
                    $recordsCount++;

                    if($result.Keys.Count -gt 0) {
                        foreach($check in $checks) {
                            if($check.column -ne $null) {
                                $result[$check.column] += $reader[$check.column];
                            }
                        }
                    }
                }
            }

            $reader.Close();

            foreach($check in $checks) {

                if($check.expected_row_count -ne $null) {
                    if($recordsCount -ne $check.expected_row_count) {
                        Write-Host ([string]::Format("[ FAIL ] - SQL command expected {0} records, but retrieved: {1}", $check.expected_row_count, $recordsCount)) -ForeGroundColor Red;
                    }
                }

                if($result.Keys.Count -gt 0) {
                    if($check.column -ne $null) {
                        if($result[$check.column][$check.row_num - 1] -eq $check.expectedValue) {
                            Write-Host ([string]::Format("[ PASS ] - {0}: {1}", $check.column, $result[$check.column][$check.row_num - 1])) -ForeGroundColor Green;
                        } else {
                            Write-Host ([string]::Format("[ FAIL ] - {0}: {1}. Expected value: {2}", $check.column, $result[$check.column][$check.row_num - 1], $check.expectedValue)) -ForeGroundColor Red;
                        }
                    }
                }
            }
        }

        
    } catch {
        Write-Host ([string]::Format("[ FAIL ] - Failed to connect to {0}", $sqlInstance)) -ForeGroundColor Red;
        Write-Host ""
        Write-Host ($_.Exception.Message) -ForeGroundColor Red;
        Write-Host ""
    } finally {
        if($con.State -eq "Open") {
            $con.Close();
        }
    }
}

function Check-Ports {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerIdentifier,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$ports
    )

    Write-Host "[ INFO ] - Port Accessibility Check: $($computerIdentifier)" -ForeGroundColor White;
    Write-Host "";

    foreach($port in $ports) {
        
        $client = New-Object Net.Sockets.TcpClient;

        try {

            $client.Connect($computerIdentifier,$port.port);

        } catch {

            if($port.expectedStatus -eq "Open") {
                Write-Host ([string]::Format("[ FAIL ] - {0} - Failed to connect", $port.port)) -ForeGroundColor Red;
                Write-Host ""
                Write-Host ($_.Exception.Message) -ForeGroundColor Red;
                Write-Host ""
            } else {
                Write-Host ([string]::Format("[ PASS ] - {0} - Connection denied", $port.port)) -ForeGroundColor Green;
            }
        }

        if($client.Connected) {
            $client.Close();

            if($port.expectedStatus -eq "Closed") {
                Write-Host ([string]::Format("[ FAIL ] - {0} - Port accepted connection, but expected to be 'Closed'", $port.port)) -ForeGroundColor Red;
            } else {
                Write-Host ([string]::Format("[ PASS ] - {0} - Connection successful", $port.port)) -ForeGroundColor Green;
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

    Write-Host "[ INFO ] - Shared Object Check: $($computerName)" -ForeGroundColor White;
    Write-Host "";

    foreach($object in $objects) {

        $path = [string]::Format("\\{0}{1}", $computerName, $object.path);

        [bool]$objectExists = [System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path);

        if($objectExists -eq $object.expected) {
            Write-Host ([string]::Format("[ PASS ] - Check object: {0}", $path)) -ForeGroundColor Green;
        } else {
            if($object.expected) {
                Write-Host ([string]::Format("[ FAIL ] - Object not found: {0}", $path)) -ForeGroundColor Red;
            } else {
                Write-Host ([string]::Format("[ FAIL ] - Invalid object found: {0}", $path)) -ForeGroundColor Red;
            }
        }
    }
}

function Check-Drives {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$computerName
    )

    Write-Host "[ INFO ] - Drive Check: $($computerName)" -ForeGroundColor White;
    Write-Host "";

    $drives = Get-WmiObject Win32_LogicalDisk -ComputerName $computerName -Filter "DriveType=3" | select DeviceID, @{Name="TotalSpace"; Expression = {[math]::Round($_.Size / 1024 / 1024 / 1024, 2)}}, @{Name="FreeSpace"; Expression = {[math]::Round($_.FreeSpace / 1024 / 1024 / 1024, 2)}};

    foreach($drive in $drives) {
        
        $prctFree = [math]::Round($drive.FreeSpace * 100 / $drive.TotalSpace, 2);

        if($prctFree -ge 30) {
            Write-Host ([string]::Format("[ PASS ] - {0} {1} % free. ({2} GB / {3} GB)", $drive.DeviceId, $prctFree, $drive.TotalSpace, $drive.FreeSpace)) -ForeGroundColor Green;
        } elseif($prctFree -lt 30 -and $prctFree -ge 10) {
            Write-Host ([string]::Format("[ WARN ] - {0} {1} % free. ({2} GB / {3} GB)", $drive.DeviceId, $prctFree, $drive.TotalSpace, $drive.FreeSpace)) -ForeGroundColor Yellow;
        } elseif($prctFree -lt 10) {
            Write-Host ([string]::Format("[ FAIL ] - {0} {1} % free. ({2} GB / {3} GB)", $drive.DeviceId, $prctFree, $drive.TotalSpace, $drive.FreeSpace)) -ForeGroundColor Red;
        }
    }
}

$commands = Get-Commands ([IO.Path]::GetFullPath("$($PSScriptRoot)\config.json"))

foreach($command in $commands) {

	if($command.active) {
	
		Write-Host ":::::::::::::::::::: $($command.description) ::::::::::::::::::::" -ForeGroundColor White;
		Write-Host "";

		if($command.connectionChecks -ne $null -and $command.connectionChecks.length -gt 0) {
			foreach($check in $command.connectionChecks) {
				if($check.active) {
					Check-Connection $check.host $check.count;
					Write-Host "";
				}
			}
		}

		if($command.serviceChecks -ne $null -and $command.serviceChecks.length -gt 0) {
			foreach($check in $command.serviceChecks) {
				if($check.active) {
					Check-Services $check.host $check.services;
					Write-Host "";
				}
			}
		}

		if($command.portChecks -ne $null -and $command.portChecks.length -gt 0) {
			foreach($check in $command.portChecks) {
				if($check.active) {
					Check-Ports $check.host $check.ports;
					Write-Host "";
				}
			}
		}

		if($command.sqlConnectionChecks -ne $null -and $command.sqlConnectionChecks.length -gt 0) {
			foreach($check in $command.sqlConnectionChecks) {
				if($check.active) {
					Check-SqlConnection $check.host $check.instances;
					Write-Host "";
				}
			}
		}

        if($command.sqlCommandChecks -ne $null -and $command.sqlCommandChecks.length -gt 0) {
			foreach($check in $command.sqlCommandChecks) {
				if($check.active) {
					Check-SqlCommand $check.host $check.instance $check.command $check.checks $check.description;
					Write-Host "";
				}
			}
		}

		if($command.sharedObjectChecks -ne $null -and $command.sharedObjectChecks.length -gt 0) {
			foreach($check in $command.sharedObjectChecks) {
				if($check.active) {
					Check-SharedObject $check.host $check.objects;
					Write-Host "";
				}
			}
		}
        
        if($command.driveChecks -ne $null -and $command.driveChecks.length -gt 0) {
            foreach($check in $command.driveChecks) {
				if($check.active) {
					Check-Drives $check.host;
					Write-Host "";
				}
			}
        }
	}
}

Read-Host -Prompt "Press Enter to exit"