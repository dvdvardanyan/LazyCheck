# PassiveCheck

A powershell script to perform manual system checks based on predefined configuration file.

## Configuration options

#### Server connection check

Configuration template for server connection check

```
{
  "type": "ping",
  "active": false,
  "hosts": [
    { "name": "SVR01PROD", "active": true }
  ],
  "count": 1
}
```

#### Windows service check

Configuration template for Windows service status check

```
{
  "type": "winservice",
  "active": true,
  "hosts": [
    { "name": "SVR01PROD", "active": true }
  ],
  "services": [
    { "name": "MyService1", "expectedStatus": "Running" },
    { "name": "MyService2", "expectedStatus": "Stopped" }
  ]
}
```

#### Server port check

Configuration template for server port check

```
{
  "type": "port",
  "active": true,
  "hosts": [
    { "name": "SVR01PROD", "active": true }
  ],
  "ports": [
    { "port": 5378, "expectedStatus": "Open" }
  ]
}
```

#### Server drives free space check

Configuration template for server drives check

```
{
  "type": "drivespace",
  "active": true,
  "hosts": [
    { "name": "SVR01PROD", "active": true }
  ]
}
```

#### SQL Server connection check

Configuration template for SQL Server connection check

```
{
  "type": "mssqlconnection",
  "active": true,
  "hosts": [
    {
      "name": "SVR01PROD",
      "instances": [{ "name": "", "trustedConnection": true }],
      "active": true
    }
  ]
}
```

#### SQL Server custom command check

Configuration template for a custom SQL Server command

```
{
  "type": "mssqlcommand",
  "active": true,
  "hosts": [
    {
      "name": "SVR01PROD",
      "instances": [{ "name": "", "trustedConnection": true }],
      "active": true
    }
  ],
  "commands": [
    {
      "type": "scalar",
      "active": true,
      "description": "Command Description",
      "command": "SQL_COMMAND_GOES_HERE",
      "checks": [
        { "description": "Value description to display for check", "comparison": "eq", "value": "COMPARISON_VALUE_HERE" }
      ]
    }, {
      "type": "table",
      "active": true,
      "description": "Command Description",
      "command": "SQL_COMMAND_GOES_HERE",
      "checks": [
        { "column": "Column1", "comparison": "eq", "value": "COMPARISON_VALUE_HERE" },
        { "column": "Column2", "comparison": "eq", "value": "COMPARISON_VALUE_HERE" }
      ]
    }
  ],
  "description": "Command Description"
}
```

Below is a simple example to verify SQL Server Availability group status

```
{
  "type": "mssqlcommand",
  "active": true,
  "hosts": [
    {
      "name": "SVR01PROD",
      "instances": [{ "name": "", "trustedConnection": true }],
      "active": true
    }
  ],
  "commands": [
    {
      "type": "table",
      "active": true,
      "description": "Availability group check",
      "command": "select AGS.primary_replica as [Primary Replica], AGS.primary_recovery_health_desc as [Recovery Health], AGS.synchronization_health_desc as [Synchronization Health] from sys.availability_groups as AG inner join sys.dm_hadr_availability_group_states as AGS on AG.group_id = AGS.group_id where AG.name = 'MyAgName'",
      "checks": [
        { "column": "Primary Replica", "comparison": "eq", "value": "SVR01PROD" },
        { "column": "Recovery Health", "comparison": "eq", "value": "ONLINE" },
        { "column": "Synchronization Health", "comparison": "eq", "value": "HEALTHY" }
      ]
    }
  ],
  "description": "Availability group check"
}
```