# PassiveCheck

A powershell script to perform system checks based on predefined configuration file.

## Configuration options

#### Configuration group

First add a configuration group that contains placeholders for the checks:

```
[
  {
    "description": "Group Description",
    "active": true,
    "connectionChecks": [],
    "serviceChecks": [],
    "sqlConnectionChecks": [],
    "sqlCommandChecks": [],
    "portChecks": [],
    "sharedObjectChecks": []
  }
]
```

Then add individual checks into the group placeholders:

#### Server connection check

Template for server connection check (connectionChecks in group template)

```
{
  "active": true,
  "host": "localhost",
  "count": 4
}
```

#### Windows service check

Template for Windows service status (serviceChecks in group template)

```
{
  "active": true,
  "host": "localhost",
  "services": [
    { "name": "MyService", "expectedStatus": "Running" },
	{ "name": "MyOtherService", "expectedStatus": "Stopped" }
  ]
}
```

#### Server port check

Template for server port check (portChecks in group template)

```
{
  "active": true,
  "host": "localhost",
  "ports": [
    { "port": ####, "expectedStatus": "Open" },
	{ "port": ####, "expectedStatus": "Closed" }
  ]
}
```

#### SQL Server connection check

Template for SQL Server connection check (sqlConnectionChecks in group template)

```
{
  "active": true,
  "host": "localhost",
  "instances": [
    { "name": "\\SQL2012", "trustedConnection": false, "user": "MyUser", "password": "MyPassword" },
    { "name": "\\SQL2016", "trustedConnection": true },
	{ "name": "", "trustedConnection": true }
  ]
}
```

#### SQL Server custom command check

Template for a custom SQL Server command (sqlCommandChecks in group template)

```
{
  "active": true,
  "host": "localhost",
  "instance": { "name": "", "trustedConnection": true },
  "command": "SQL command to run",
  "checks": [
    { "expected_row_num": 1 },
    { "row_num": 1, "column": "Primary Replica", "expectedValue": "PRIMARY_SERVER_NAME" }
  ],
  "description": "Availability group check"
}
```

Below is a simple example to verify SQL Server Availability group status

```
{
  "active": true,
  "host": "localhost",
  "instance": { "name": "\\SQL2012", "trustedConnection": true },
  "command": "select AGS.primary_replica as [Primary Replica], AGS.primary_recovery_health_desc as [Recovery Health], AGS.synchronization_health_desc as [Synchronization Health] from sys.availability_groups as AG inner join sys.dm_hadr_availability_group_states as AGS on AG.group_id = AGS.group_id where AG.name = 'AG_Name'",
  "checks": [
    { "expected_row_num": 1 },
    { "row_num": 1, "column": "Primary Replica", "expectedValue": "PRIMARY_SERVER_NAME" },
    { "row_num": 1, "column": "Recovery Health", "expectedValue": "ONLINE" },
    { "row_num": 1, "column": "Synchronization Health", "expectedValue": "HEALTHY" }
  ],
  "description": "Availability group check"
}
```

#### Shared folder check

Template to verify shared folder accessibility (sharedObjectChecks in group template)

```
{
  "active": false,
  "host": "localhost",
  "objects": [
    { "path": "\\\\SomeServer\\D$\\MyFolder", "expected": true }
  ]
}
```