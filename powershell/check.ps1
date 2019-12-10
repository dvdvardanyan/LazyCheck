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

    $config = Get-Content -Raw -Path $path;

    return ConvertFrom-Json $config;
}

function Get-InstanceName {

    [OutputType([string])]

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$host_name,
        [Parameter(Mandatory=$false, Position=1)][string]$instance_name
    )

    if($instance_name -eq $null -or $instance_name -eq "") {
        return $host_name;
    } else {
        return [string]::Format("{0}\{1}", $host_name, $instance_name);
    }
}

function Get-SqlConnectionString {

    [OutputType([string])]

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$host_name,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$instance_obj
    )

    $instance_name = Get-InstanceName $host_name $instance_obj.name;
    
    if($instance_obj.port -eq $null -or $instance_obj.port -eq "") {
        $port_number = "1433";
    } else {
        [string]$port_number = $instance_obj.port;
    }

    if($instance_obj.database -eq $null -or $instance_obj.database -eq "") {
        $database_name = "master";
    } else {
        $database_name = $instance_obj.database;
    }

    return [string]::Format("Data Source={0},{1};Initial Catalog={2};Trusted_Connection={3};", $instance_name, $port_number, $database_name, $instance_obj.trustedConnection);
}

function Check-Connection {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject[]]$hosts,
        [Parameter(Mandatory=$true, Position=1)][int]$count
    )

    Write-Host " Network Connection Check: $($computerIdentifier)" -ForeGroundColor White;
    Write-Host "";

    foreach($host_obj in $hosts) {

        if($host_obj.active) {

            Write-Host "    - $($host_obj.name)";
            Write-Host "";

            Test-Connection -ComputerName $host_obj.name -Count $count | Format-Table;

            Write-Host "";
        }
    }
}

function Check-Services {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject[]]$hosts,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject[]]$services
    )

    Write-Host " Windows Service Check" -ForeGroundColor White;
    Write-Host "";
        
    foreach($host_obj in $hosts) {

        if($host_obj.active) {

            Write-Host "    - $($host_obj.name)";
            Write-Host "";

            foreach($service in $services) {
                $svc = Get-Service -ComputerName $host_obj.name -Name $service.name | Select-Object Status;

                if($svc.Status -eq $service.expectedStatus) {
                    Write-Host "    [ PASS ] - $($service.name) ($($svc.Status))" -ForeGroundColor Green;
                } else {
                    if($svc.Status -eq $null) {
                        Write-Host "    [ FAIL ] - $($service.name) (Not Found)" -ForeGroundColor Red;
                    } else {
                        Write-Host ([string]::Format("    [ FAIL ] - {0} ({1}) - Expected to be ({2})", $service.name, $svc.Status, $service.expectedStatus)) -ForeGroundColor Red;
                    }
                }
            }

            Write-Host "";
        }
    }
}

function Check-SqlConnection {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject[]]$hosts
    )

    Write-Host " SQL Connection Check: $($computerName)" -ForeGroundColor White;
    Write-Host "";

    foreach($host_obj in $hosts) {

        if($host_obj.active) {
            
            Write-Host "    - $($host_obj.name)";
            Write-Host "";

            foreach($instance in $host_obj.instances) {

                $sqlInstance = Get-InstanceName $host_obj.name $instance.name;

                $conString = Get-SqlConnectionString $host_obj.name $instance;

                try {

                    $con = New-Object System.Data.SqlClient.SqlConnection($conString);
                    $con.Open();

                    Write-Host ([string]::Format("    [ PASS ] - Connected to {0}", $sqlInstance)) -ForeGroundColor Green;

                } catch {
                    Write-Host ([string]::Format("    [ FAIL ] - Failed to connect to {0}", $sqlInstance)) -ForeGroundColor Red;
                    Write-Host ""
                    Write-Host ($_.Exception.Message) -ForeGroundColor Red;
                    Write-Host ""
                } finally {
                    if($con.State -eq "Open") {
                        $con.Close();
                    }
                }
            }

            Write-Host "";
        }
    }
}

function Check-SqlCommand {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject]$hosts,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject]$commands,
        [Parameter(Mandatory=$false, Position=2)][PSCustomObject]$description
    )

    if($description -eq $null -or $description -eq "") {
        Write-Host " SQL Command Check" -ForeGroundColor White;
        Write-Host "";
    } else {
        Write-Host " $($description)" -ForeGroundColor White;
        Write-Host "";
    }

    foreach($host_obj in $hosts) {
        if($host_obj.active) {
            foreach($instance_obj in $host_obj.instances) {
        
                $instanceName = Get-InstanceName $host_obj.name $instance_obj.name;

                Write-Host "    - $($instanceName)" -ForeGroundColor White;
                Write-Host "";

                $conString = Get-SqlConnectionString $host_obj.name $instance_obj;

                $con = New-Object System.Data.SqlClient.SqlConnection($conString);

                try {

                    $con.Open();

                    foreach($command in $commands) {

                        if($command.active) {

                            try {

                                $cmd = $con.CreateCommand();
                                $cmd.CommandText = $command.command;

                                switch($command.type) {

                                    "scalar" {

                                        $value = $cmd.ExecuteScalar();
                                        foreach($check in $command.checks) {
                                            if($check.comparison -eq $null -or $check.comparison -eq "" -or $check.comparison -eq "eq") {
                                                # Check for equals
                                                if($value -eq $check.value) {
                                                    Write-Host ([string]::Format("    [ PASS ] - {0}: {1}", $check.description, $value)) -ForeGroundColor Green;
                                                } else {
                                                    Write-Host ([string]::Format("    [ FAIL ] - {0}: {1}. Expected: {2}", $check.description, $value, $check.value)) -ForeGroundColor Red;
                                                }
                                            } else {
                                                switch($check.comparison) {
                                                    # Greater than
                                                    "gt" {
                                                        if($value -gt $check.value) {
                                                            Write-Host ([string]::Format("    [ PASS ] - {0}: {1}", $check.description, $value)) -ForeGroundColor Green;
                                                        } else {
                                                            Write-Host ([string]::Format("    [ FAIL ] - {0}: {1}. Expected greater than: {2}", $check.description, $value, $check.value)) -ForeGroundColor Red;
                                                        }
                                                    }
                                                    # Less than
                                                    "lt" {
                                                        if($value -lt $check.value) {
                                                            Write-Host ([string]::Format("    [ PASS ] - {0}: ", $check.description, $value)) -ForeGroundColor Green;
                                                        } else {
                                                            Write-Host ([string]::Format("    [ FAIL ] - {0}: {1}. Expected less than: {2}", $check.description, $value, $check.value)) -ForeGroundColor Red;
                                                        }
                                                    }
                                                    # Not equals
                                                    "ne" {
                                                        if($value -ne $check.value) {
                                                            Write-Host ([string]::Format("    [ PASS ] - {0}: {1}", $check.description, $value)) -ForeGroundColor Green;
                                                        } else {
                                                            Write-Host ([string]::Format("    [ FAIL ] - {0}: {1}. Current value is not expected.", $check.description, $value)) -ForeGroundColor Red;
                                                        }
                                                    }
                                                    # Less or equal
                                                    "le" {
                                                        if($value -le $check.value) {
                                                            Write-Host ([string]::Format("    [ PASS ] - {0}: {1}", $check.description, $value)) -ForeGroundColor Green;
                                                        } else {
                                                            Write-Host ([string]::Format("    [ FAIL ] - {0}: {1}. Expected less or equal to: {2}", $check.description, $value, $check.value)) -ForeGroundColor Red;
                                                        }
                                                    }
                                                    # Greater or equal
                                                    "ge" {
                                                        if($value -ge $check.value) {
                                                            Write-Host ([string]::Format("    [ PASS ] - {0}: {1}", $check.description, $value)) -ForeGroundColor Green;
                                                        } else {
                                                            Write-Host ([string]::Format("    [ FAIL ] - {0}: {1}. Expected greater or equal to: {2}", $check.description, $value, $check.value)) -ForeGroundColor Red;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    "table" {

                                        $reader = $cmd.ExecuteReader();

                                        if($reader.HasRows) {

                                            Write-Host ([string]::Format("    [ GRID ] - {0}.", $command.description)) -ForeGroundColor Cyan;

                                            [int]$recordsCount = 0;

                                            while ($reader.Read()) {

                                                $recordsCount++;

                                                Write-Host "      :: $($recordsCount)" -ForeGroundColor Cyan;
                                                
                                                foreach($check in $command.checks) {

                                                    $value = $reader[$check.column];

                                                    if($value -eq $null) {
                                                        Write-Host ([string]::Format("        [ FAIL ] - No column name: {0}.", $check.column)) -ForeGroundColor Red;
                                                        $record_valid = $false;
                                                    } else {
                                                        if($check.comparison -eq $null -or $check.comparison -eq "" -or $check.comparison -eq "eq") {
                                                            if($value -eq $check.value) {
                                                                Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Green;
                                                            } else {
                                                                Write-Host ([string]::Format("        [ FAIL ] - {0}: {1}. Expected value: {2}", $check.column, $value, $check.value))  -ForeGroundColor Red;
                                                            }
                                                        } else {

                                                            switch($check.comparison) {
                                                                # No comparison. Display only
                                                                "none" {
                                                                    Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Cyan;
                                                                }
                                                                # Greater than
                                                                "gt" {
                                                                    if($value -gt $check.value) {
                                                                        Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Green;
                                                                    } else {
                                                                        Write-Host ([string]::Format("        [ FAIL ] - {0}: {1}. Expected value greater than: {2}", $check.column, $value, $check.value))  -ForeGroundColor Red;
                                                                    }
                                                                }
                                                                # Less than
                                                                "lt" {
                                                                    if($value -gt $check.value) {
                                                                        Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Green;
                                                                    } else {
                                                                        Write-Host ([string]::Format("        [ FAIL ] - {0}: {1}. Expected value less than: {2}", $check.column, $value, $check.value))  -ForeGroundColor Red;
                                                                    }
                                                                }
                                                                # Not equals
                                                                "ne" {
                                                                    if($value -gt $check.value) {
                                                                        Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Green;
                                                                    } else {
                                                                        Write-Host ([string]::Format("        [ FAIL ] - {0}: {1}. Expected value not equal to: {2}", $check.column, $value, $check.value))  -ForeGroundColor Red;
                                                                    }
                                                                }
                                                                # Less or equal
                                                                "le" {
                                                                    if($value -gt $check.value) {
                                                                        Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Green;
                                                                    } else {
                                                                        Write-Host ([string]::Format("        [ FAIL ] - {0}: {1}. Expected value less or equal to: {2}", $check.column, $value, $check.value))  -ForeGroundColor Red;
                                                                    }
                                                                }
                                                                # Greater or equal
                                                                "ge" {
                                                                    if($value -gt $check.value) {
                                                                        Write-Host ([string]::Format("        [ PASS ] - {0}: {1}", $check.column, $value))  -ForeGroundColor Green;
                                                                    } else {
                                                                        Write-Host ([string]::Format("        [ FAIL ] - {0}: {1}. Expected value greater or equal to: {2}", $check.column, $value, $check.value))  -ForeGroundColor Red;
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }                                                
                                            }
                                        } else {
                                            Write-Host ([string]::Format("    [ WARN ] - No records were returned for command: {0}.", $command.description)) -ForeGroundColor Yellow;
                                        }

                                        $reader.Close();
                                    }

                                    default {
                                        Write-Host "    [ FAIL ] - Unknown command type '$($command.type)'" -ForeGroundColor Red;
                                    }
                                }

                            } catch {
                                Write-Host ([string]::Format("    [ FAIL ] - Error occured while executing command: '{0}'.", $command.command)) -ForeGroundColor Red;
                                Write-Host "";
                                Write-Host ($_.Exception.Message) -ForeGroundColor Red;
                                Write-Host "";
                            }
                        }
                    }
                } catch {
                    Write-Host ([string]::Format("    [ FAIL ] - Error occured while connecting to instance: '{0}'.", $instanceName)) -ForeGroundColor Red;
                    Write-Host "";
                    Write-Host ($_.Exception.Message) -ForeGroundColor Red;
                    Write-Host "";
                } finally {
                    if($con.State -eq "Open") {
                        $con.Close();
                    }
                }

                Write-Host "";
            }
        }
    }
}

function Check-Ports {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject[]]$hosts,
        [Parameter(Mandatory=$true, Position=1)][PSCustomObject[]]$ports
    )

    Write-Host " Port Accessibility Check" -ForeGroundColor White;
    Write-Host "";

    foreach($host_obj in $hosts) {

        if($host_obj.active) {
            
            Write-Host "    - $($host_obj.name)";
            Write-Host "";

            foreach($port in $ports) {
        
                $client = New-Object Net.Sockets.TcpClient;

                try {

                    $client.Connect($host_obj.name, $port.port);

                } catch {

                    if($port.expectedStatus -eq "Open") {
                        Write-Host ([string]::Format("    [ FAIL ] - {0} - Failed to connect", $port.port)) -ForeGroundColor Red;
                        Write-Host ""
                        Write-Host ($_.Exception.Message) -ForeGroundColor Red;
                        Write-Host ""
                    } else {
                        Write-Host ([string]::Format("    [ PASS ] - {0} - Connection denied", $port.port)) -ForeGroundColor Green;
                    }
                }

                if($client.Connected) {
                    $client.Close();

                    if($port.expectedStatus -eq "Closed") {
                        Write-Host ([string]::Format("    [ FAIL ] - {0} - Port accepted connection. Expected to be 'Closed'", $port.port)) -ForeGroundColor Red;
                    } else {
                        Write-Host ([string]::Format("    [ PASS ] - {0} - Connection successful", $port.port)) -ForeGroundColor Green;
                    }
                }
            }

            Write-Host "";
        }
    }
}

function Replace-Tokens {

    [OutputType([string])]

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$value,
        [Parameter(Mandatory=$false, Position=1)][PSCustomObject[]]$tokens
    )

    foreach($token in $tokens) {
        
        switch($token.type) {
            
            "text" {

                if([string]::IsNullOrWhiteSpace($token.token) -or [string]::IsNullOrWhiteSpace($token.value)) {
                    Write-Host "    [ FAIL ] - Neither token nor value can be null" -ForeGroundColor Red;
                } else {
                    $value = $value.Replace($token.token, $token.value);
                }
            }

            "date" {

                if([string]::IsNullOrWhiteSpace($token.token) -or [string]::IsNullOrWhiteSpace($token.format)) {
                    Write-Host "    [ FAIL ] - Neither token nor format can be null" -ForeGroundColor Red;
                } else {

                    [DateTime]$date = Get-Date;

                    if($token.offset -ne $null) {
                        if(-not [string]::IsNullOrWhiteSpace($token.offset.type) -and $token.offset.value -ne $null) {
                            switch($token.offset.type) {
                                "dd" {
                                    $date = $date.AddDays($token.offset.value);
                                }
                            }
                        }
                    }

                    $value = $value.Replace($token.token, $date.ToString($token.format));
                }
            }

            default {
                Write-Host "    [ FAIL ] - Unknown token type '$($token.type)'" -ForeGroundColor Red;
            }
        }

    }

    return $value;
}

function Check-Items {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject[]]$items
    )

    Write-Host " Item Check" -ForeGroundColor White;
    Write-Host "";

    foreach($item in $items) {

        switch($item.type) {

            "file" {

                if($item.tokens -ne $null -and $item.tokens.length -gt 0) {
                    $item.path = Replace-Tokens $item.path $item.tokens;
                }

                [bool]$item_exists = [System.IO.File]::Exists($item.path);

                if($item_exists -eq $item.expected) {
                    Write-Host ([string]::Format("    [ PASS ] - Item check: {0}", $item.path)) -ForeGroundColor Green;
                } else {
                    Write-Host ([string]::Format("    [ FAIL ] - Item check: {0}. Exists: {1}. Expected: {2}", $item.path, $item_exists.ToString(), $item.expected)) -ForeGroundColor Red;
                }
            }
            
            "folder" {

                if($item.tokens -ne $null -and $item.tokens.length -gt 0) {
                    $item.path = Replace-Tokens $item.path $item.tokens;
                }

                [bool]$item_exists = [System.IO.Directory]::Exists($item.path);

                if($item_exists -eq $item.expected) {
                    Write-Host ([string]::Format("    [ PASS ] - Item check: {0}", $item.path)) -ForeGroundColor Green;
                } else {
                    Write-Host ([string]::Format("    [ FAIL ] - Item check: {0}. Exists: {1}. Expected: {2}", $item.path, $item_exists.ToString(), $item.expected)) -ForeGroundColor Red;
                }
            }

            "registry" {

                foreach($reg in $item.items) {

                    $key = $reg.name;
                    $key_object = Get-ItemProperty -Path $item.path -Name $key;
                    $value = $key_object.$key;

                    if($reg.comparison -eq $null -or $reg.comparison -eq "" -or $reg.comparison -eq "eq") {
                        if($value -eq $reg.value) {
                            Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Green;
                        } else {
                            Write-Host ([string]::Format("        [ FAIL ] - {0}\{1}: {2}. Expected value: {3}", $item.path, $key, $value, $reg.value))  -ForeGroundColor Red;
                        }
                    } else {

                        switch($reg.comparison) {
                            # No comparison. Display only
                            "none" {
                                Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Cyan;
                            }
                            # Greater than
                            "gt" {
                                if($value -gt $reg.value) {
                                    Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Green;
                                } else {
                                    Write-Host ([string]::Format("        [ FAIL ] - {0}\{1}: {2}. Expected value greater than: {3}", $item.path, $key, $value, $reg.value))  -ForeGroundColor Red;
                                }
                            }
                            # Less than
                            "lt" {
                                if($value -gt $reg.value) {
                                    Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Green;
                                } else {
                                    Write-Host ([string]::Format("        [ FAIL ] - {0}\{1}: {2}. Expected value less than: {3}", $item.path, $key, $value, $reg.value))  -ForeGroundColor Red;
                                }
                            }
                            # Not equals
                            "ne" {
                                if($value -gt $reg.value) {
                                    Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Green;
                                } else {
                                    Write-Host ([string]::Format("        [ FAIL ] - {0}\{1}: {2}. Expected value not equal to: {3}", $item.path, $key, $value, $reg.value))  -ForeGroundColor Red;
                                }
                            }
                            # Less or equal
                            "le" {
                                if($value -gt $reg.value) {
                                    Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Green;
                                } else {
                                    Write-Host ([string]::Format("        [ FAIL ] - {0}\{1}: {2}. Expected value less or equal to: {3}", $item.path, $key, $value, $reg.value))  -ForeGroundColor Red;
                                }
                            }
                            # Greater or equal
                            "ge" {
                                if($value -gt $reg.value) {
                                    Write-Host ([string]::Format("        [ PASS ] - {0}\{1}: {2}", $item.path, $key, $value))  -ForeGroundColor Green;
                                } else {
                                    Write-Host ([string]::Format("        [ FAIL ] - {0}\{1}: {2}. Expected value greater or equal to: {3}", $item.path, $key, $value, $reg.value))  -ForeGroundColor Red;
                                }
                            }
                        }
                    }
                    
                }

            }

            default {
                Write-Host "    [ FAIL ] - Unknown item type '$($item.type)'" -ForeGroundColor Red;
            }
        }
    }
}

function Check-Drives {

    Param
    (
        [Parameter(Mandatory=$true, Position=0)][PSCustomObject[]]$hosts
    )

    Write-Host " Drive Check" -ForeGroundColor White;
    Write-Host "";

    foreach($host_obj in $hosts) {
        if($host_obj.active) {
            Write-Host "    - $($host_obj.name)";
            Write-Host "";

            $drives = Get-WmiObject Win32_LogicalDisk -ComputerName $host_obj.name -Filter "DriveType=3" | select DeviceID, @{Name="TotalSpace"; Expression = {[math]::Round($_.Size / 1024 / 1024 / 1024, 2)}}, @{Name="FreeSpace"; Expression = {[math]::Round($_.FreeSpace / 1024 / 1024 / 1024, 2)}};

            foreach($drive in $drives) {
        
                $prctFree = [math]::Round($drive.FreeSpace * 100 / $drive.TotalSpace, 2);

                if($prctFree -ge 30) {
                    Write-Host ([string]::Format("    [ PASS ] - {0} {1} % free. ({2} GB / {3} GB)", $drive.DeviceId, $prctFree, $drive.TotalSpace, $drive.FreeSpace)) -ForeGroundColor Green;
                } elseif($prctFree -lt 30 -and $prctFree -ge 10) {
                    Write-Host ([string]::Format("    [ WARN ] - {0} {1} % free. ({2} GB / {3} GB)", $drive.DeviceId, $prctFree, $drive.TotalSpace, $drive.FreeSpace)) -ForeGroundColor Yellow;
                } elseif($prctFree -lt 10) {
                    Write-Host ([string]::Format("    [ FAIL ] - {0} {1} % free. ({2} GB / {3} GB)", $drive.DeviceId, $prctFree, $drive.TotalSpace, $drive.FreeSpace)) -ForeGroundColor Red;
                }
            }
        }

        Write-Host "";
    }
}

$commands = Get-Commands ([IO.Path]::GetFullPath("$($PSScriptRoot)\config.json"))
    
if($commands -ne $null) {

    if($commands.Length -gt 0) {

        foreach($command in $commands) {
            
            if($command.active) {

                Write-Host ":::::::::::::::::::: $($command.description) ::::::::::::::::::::" -ForeGroundColor White;
	            Write-Host "";

                if($command.checks.Count -gt 0) {

                    foreach($check in $command.checks) {

                        if($check.active) {

                            switch($check.type) {

                                "ping" {
                                    Check-Connection $check.hosts $check.count;
                                    Write-Host "";
                                }

                                "winservice" {
                                    Check-Services $check.hosts $check.services;
				                    Write-Host "";
                                }

                                "port" {
                                    Check-Ports $check.hosts $check.ports;
                                    Write-Host "";
                                }

                                "drivespace" {
                                    Check-Drives $check.hosts;
				                    Write-Host "";
                                }

                                "mssqlconnection" {
                                    Check-SqlConnection $check.hosts;
				                    Write-Host "";
                                }

                                "mssqlcommand" {
                                    Check-SqlCommand $check.hosts $check.commands $check.description;
				                    Write-Host "";
                                }

                                "checkitem" {
                                    Check-Items $check.items;
                                    Write-Host "";
                                }

                                default {
                                    Write-Host "[ FAIL ] - Unknown check '$($check.type)'" -ForeGroundColor Red;
                                    Write-Host "";
                                }
                            }
                        }
                    }
                } else {
                    Write-Host "    [ FAIL ] - No checks in configuration file entry" -ForeGroundColor Red;
                    Write-Host "";
                }
            }
        }
    } else {
        Write-Host "    [ FAIL ] - No entries in configuration file" -ForeGroundColor Red;
        Write-Host "";
    }
} else {
    Write-Host "    [ FAIL ] - Configuration file is empty" -ForeGroundColor Red;
    Write-Host "";
}

Read-Host -Prompt "Press Enter to exit"