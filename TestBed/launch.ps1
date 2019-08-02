param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$StorageName,
    [Parameter(Mandatory=$true)][string]$FunctionPrefix,
    [ValidateSet('Windows', 'Linux')][Parameter(Mandatory=$false)][string]$OsType = 'Linux',
    [ValidateSet('create', 'delete', 'deploy', 'starttest', "stoptest")][string]$Command = "create"
)

$PERIODS = @(5, 60, 900) # Unit: second. How often do you want to invoke the function app
$PROCESS_TIMES = @(60) # Unit: second. How long does the function app need to process for each request
$TYPES = @("timer", "queue", "http") # Type: timer, queue, http. What type of function app you want to test on.
$DEPLOYMENT_PATH = "$PSScriptRoot\deployment"
$PROJECT_ROOT = "$PSScriptRoot\.."
$LOG_PATH = "$ENV:HOME\Desktop"


function create([string]$resourceGroupName, [string]$storageName, [string]$functionPrefix) {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                $function_name = "$functionPrefix-$type-$period-$process_time"
                Start-Process -FilePath "az" -NoNewWindow -ArgumentList functionapp,create,"-n","$function_name","-s","$storageName","-g","$resourceGroupName","-c",eastasia,"--os-type",$OsType,"--runtime",node
            }
        }
    }
}

function delete([string]$resourceGroupName, [string]$storageName, [string]$functionPrefix) {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                $function_name = "$functionPrefix-$type-$period-$process_time"
                Start-Process -NoNewWindow -FilePath "az" -ArgumentList functionapp,delete,"-n","$function_name","-g","$resourceGroupName" -
                Start-Process -NoNewWindow -FilePath "az" -ArgumentList resource,delete,"-n","$function_name","-g","$resourceGroupName","--resource-type","Microsoft.Insights/components"
            }
        }
    }
}

function pre_deploy() {
    New-Item -ItemType Directory -Path "$DEPLOYMENT_PATH" -Force

    Start-Process -NoNewWindow -WorkingDirectory "$PROJECT_ROOT" -FilePath "npm" -ArgumentList "run","build" -Wait
    Start-Process -NoNewWindow -WorkingDirectory "$PROJECT_ROOT" -FilePath "func" -ArgumentList "extensions","install" -Wait

    Copy-Item -Path "$PROJECT_ROOT\bin" -Destination "$DEPLOYMENT_PATH" -Recurse -Force
    Copy-Item -Path "$PROJECT_ROOT\node_modules" -Destination "$DEPLOYMENT_PATH" -Recurse -Force
    Copy-Item -Path "$PROJECT_ROOT\local.settings.json" -Destination "$DEPLOYMENT_PATH"
    Copy-Item -Path "$PROJECT_ROOT\host.json" -Destination "$DEPLOYMENT_PATH"
    Copy-Item -Path "$PROJECT_ROOT\package.json" -Destination "$DEPLOYMENT_PATH"
    Copy-Item -Path "$PROJECT_ROOT\tsconfig.json" -Destination "$DEPLOYMENT_PATH"
}

function cleanup_deploy() {
    Remove-Item -Recurse -Force -Path "$DEPLOYMENT_PATH\*Trigger"
    Remove-Item -Recurse -Force -Path "$DEPLOYMENT_PATH\dist\*Trigger"
}

function post_deploy() {
    Remove-Item -Recurse -Force -Path "$DEPLOYMENT_PATH"
}

function deploy_timer_trigger([string]$functionName, [int]$period) {
    $cron = "* * * * * *"
    if ($period -lt 60) {
        $adjust = [math]::floor($period)
        $cron = "*/$adjust * * * * *"
    } elseif ($period -lt 3600) {
        $adjust = [math]::floor($period/60)
        $cron = "0 */$adjust * * * *"
    }

    $functionJson = Get-Content -Raw -Path "$DEPLOYMENT_PATH\TimerTrigger\function.json" | ConvertFrom-Json
    $functionJson.bindings[0].schedule = "$cron"
    Set-Content -Path "$DEPLOYMENT_PATH\TimerTrigger\function.json" -Value (ConvertTo-Json $functionJson) -Force
}

function deploy_queue_trigger([string]$functionName) {
    Start-Process -NoNewWindow -Wait -FilePath "az" -ArgumentList storage,queue,create,"-n","$functionName","--account-name","$StorageName"

    $functionJson = Get-Content -Raw -Path "$DEPLOYMENT_PATH\QueueTrigger\function.json" | ConvertFrom-Json
    $functionJson.bindings[0].queueName = "$functionName"
    Set-Content -Path "$DEPLOYMENT_PATH\QueueTrigger\function.json" -Value (ConvertTo-Json $functionJson) -Force
}

function deploy([string]$type, [int]$period, [int]$process_time) {
    $lowercasedType = $type.ToLower()
    $triggerName = (Get-Culture).TextInfo.ToTitleCase($lowercasedType) + "Trigger"
    $functionName = "$FunctionPrefix-$lowercasedType-$period-$process_time"
    Copy-Item -Recurse -Force -Path "$PROJECT_ROOT\$triggerName" -Destination "$DEPLOYMENT_PATH"
    New-Item -ItemType Directory -Path "$DEPLOYMENT_PATH\dist" -Force
    Copy-Item -Recurse -Force -Path "$PROJECT_ROOT\dist\$triggerName" -Destination "$DEPLOYMENT_PATH\dist"

    if ($type.ToLower() -eq "timer") {
        deploy_timer_trigger $functionName $period
    } elseif ($type.ToLower() -eq "queue") {
        deploy_queue_trigger $functionName
    }

    Start-Process -NoNewWindow -WorkingDirectory "$DEPLOYMENT_PATH" -FilePath "func" -ArgumentList "azure","functionapp","publish","$functionName" -Wait
}

function testHttpTrigger([string]$function_name, [int]$period, [int]$process_time) {
    Start-Job -ScriptBlock {
        param ([string]$function_name, [int]$period, [int]$process_time, [string]$log_path)
        while ($true) {
            Start-Sleep -Seconds $period
            $timestamp = (Get-Date)
            $result = $null
            try {
                $url = "https://$function_name.azurewebsites.net/api/HttpTrigger?busySeconds=$process_time"
                "$timestamp Requesting $url" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
                $result = Invoke-WebRequest -Method Get -Uri $url
                "$timestamp Succeeded $result" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            } catch {
                $message = $_.Exception.Message
                "$timestamp Failed $message" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            }
        }
    } -Name "$function_name-test" -ArgumentList $function_name,$period,$process_time,"$LOG_PATH\$function_name.log"
}

function testQueueTrigger([string]$function_name, [int]$period, [int]$process_time) {
    Start-Job -ScriptBlock {
        param ([string]$function_name, [int]$period, [int]$process_time, [string]$account_name, [string]$log_path)
        while ($true) {
            Start-Sleep -Seconds $period
            $timestamp = (Get-Date)
            $message = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$process_time"))
            "$timestamp Pushing message $process_time to account $account_name and queue $function_name" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            try {
                Start-Process -NoNewWindow -FilePath "az" -ArgumentList "storage","message","put","--content","$message","-q","$function_name","--account-name","$account_name"
                "$timestamp Succeeded" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            } catch {
                $excep = $_.Exception.Message
                "$timestamp Failed $excep" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            }
        }
    } -Name "$function_name-test" -ArgumentList $function_name,$period,$process_time,$StorageName,"$LOG_PATH\$function_name.log"
}

function testTrigger([string]$type, [int]$period, [int]$process_time) {
    $lowercasedType = $type.ToLower()
    $function_name = "$FunctionPrefix-$lowercasedType-$period-$process_time"
    if ($type.ToLower() -eq "http") {
        testHttpTrigger $function_name $period $process_time
    } elseif ($type.ToLower() -eq "queue") {
        testQueueTrigger $function_name $period $process_time
    }
}

function stopTest([string]$type, [int]$period, [int]$process_time) {
    $lowercasedType = $type.ToLower()
    $function_name = "$FunctionPrefix-$lowercasedType-$period-$process_time"

    $workers = Get-Job -Name "$function_name-test" -ErrorAction SilentlyContinue
    if ($null -ne $workers) {
        Write-Host "Clean Up $function_name"
        Stop-Job -Id $workers.Id
    }
}

if ($Command.ToLower() -eq "create") {
    create $ResourceGroupName $StorageName $FunctionPrefix
    Write-Host -ForegroundColor Yellow "Creating function app asynchronously. Check your portal constantly."
} elseif ($Command.ToLower() -eq "delete") {
    delete $ResourceGroupName $StorageName $FunctionPrefix
    Write-Host -ForegroundColor Yellow "Deleting function app asynchronously. Check your portal constantly."
} elseif ($Command.ToLower() -eq "deploy") {
    pre_deploy
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                deploy $type $period $process_time
                cleanup_deploy
            }
        }
    }
    post_deploy
    Write-Host -ForegroundColor Yellow "Deployed to function app... Check your portal."
} elseif ($Command.ToLower() -eq "starttest") {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                testTrigger $type $period $process_time
            }
        }
    }
    Write-Host -ForegroundColor Yellow "Check your log in $LOG_PATH"
} elseif ($Command.ToLower() -eq "stoptest") {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                stopTest $type $period $process_time
            }
        }
    }
}
