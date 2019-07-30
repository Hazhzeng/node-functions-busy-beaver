### Billing Test Script Location
TestBed\launch.ps1
You may want to change the scripts:
- $PERIODS: an array keeping how frequently your function app should be called (in second)
- $PROCESS_TIMES: an array keeping how long each invocation should last for
- $TYPES: what kind of trigger do you want to test (Currently only support **http**)
- $LOG_PATH: where do your logs need to go

### To Create Function Apps
`.\launch.ps1 -ResourceGroupName <RG> -StorageName <STORAGE> -FunctionPrefix <NOSPACE FUNCTIONAPP PREFIX> -Command create`
This command will deploy a bunch of test function apps to record the bill.
The function app name is constructing with schema `$FUNCTION_PREFIX-$TYPE-$PERIOD-$PROCESS_TIME`

### To Delete Function Apps
`.\launch.ps1 -ResourceGroupName <RG> -StorageName <STORAGE> -FunctionPrefix <NOSPACE FUNCTIONAPP PREFIX> -Command delete`
This command will remove all function apps related to this test.

### To Deploy Project to Function Apps
`.\launch.ps1 -ResourceGroupName <RG> -StorageName <STORAGE> -FunctionPrefix <NOSPACE FUNCTIONAPP PREFIX> -Command deploy`
Deploy local content (busy beaver) to function apps.

### To Start Test
`.\launch.ps1 -ResourceGroupName <RG> -StorageName <STORAGE> -FunctionPrefix <NOSPACE FUNCTIONAPP PREFIX> -Command starttest`
Will generate logs in your `$LOG_PATH` location.
You can use (Get-Job) to list all the ongoing tasks.

### To Stop Test
`.\launch.ps1 -ResourceGroupName <RG> -StorageName <STORAGE> -FunctionPrefix <NOSPACE FUNCTIONAPP PREFIX> -Command stoptest`
You can use (Get-Job) to list all stopped tasks.