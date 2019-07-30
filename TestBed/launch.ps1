param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$StorageName,
    [Parameter(Mandatory=$true)][string]$FunctionPrefix,
    [ValidateSet('create', 'delete', 'deploy', 'starttest', "stoptest")][string]$Command = "create"
)

$PERIODS = @(5, 30, 60, 90, 120) # Unit: second
$PROCESS_TIMES = @(3, 60) # Unit: second
$TYPES = "http" #, "queue", "blob"
$DEPLOYMENT_PATH = "$PSScriptRoot\deployment"
$PROJECT_ROOT = "$PSScriptRoot\.."
$LOG_PATH = "$ENV:HOME\Desktop"


function create([string]$resourceGroupName, [string]$storageName, [string]$functionPrefix) {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                $function_name = "$functionPrefix-$type-$period-$process_time"
                Start-Process -FilePath "az" -NoNewWindow -ArgumentList functionapp,create,"-n","$function_name","-s","$storageName","-g","$resourceGroupName","-c",eastasia,"--os-type",Linux,"--runtime",node,"--disable-app-insights"
            }
        }
    }
}

function delete([string]$resourceGroupName, [string]$storageName, [string]$functionPrefix) {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                $function_name = "$functionPrefix-$type-$period-$process_time"
                Start-Process -NoNewWindow -FilePath "az" -ArgumentList functionapp,delete,"-n","$function_name","-g","$resourceGroupName"
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

function deploy_blob_trigger([string]$functionName) {
    $functionJson = Get-Content -Raw -Path "$DEPLOYMENT_PATH\BlobTrigger\function.json" | ConvertFrom-Json
    $functionJson.bindings[0].path = "$functionName/{name}"
    Set-Content -Path "$DEPLOYMENT_PATH\BlobTrigger\function.json" -Value (ConvertTo-Json $functionJson) -Force
}

function deploy([string]$type, [int]$period, [int]$process_time) {
    $lowercasedType = $type.ToLower()
    $triggerName = (Get-Culture).TextInfo.ToTitleCase($lowercasedType) + "Trigger"
    $functionName = "$FunctionPrefix-$lowercasedType-$period-$process_time"
    Copy-Item -Recurse -Force -Path "$PROJECT_ROOT\$triggerName" -Destination "$DEPLOYMENT_PATH"
    New-Item -ItemType Directory -Path "$DEPLOYMENT_PATH\dist" -Force
    Copy-Item -Recurse -Force -Path "$PROJECT_ROOT\dist\$triggerName" -Destination "$DEPLOYMENT_PATH\dist"

    if ($type.ToLower() -eq "blob") {
        deploy_blob_trigger $functionName
    }

    Start-Process -NoNewWindow -WorkingDirectory "$DEPLOYMENT_PATH" -FilePath "func" -ArgumentList "azure","functionapp","publish","$functionName" -Wait
}

function testHttpTrigger([string]$function_name, [int]$period, [int]$process_time) {
    Start-Job -ScriptBlock {
        param ([string]$function_name, [int]$period, [int]$process_time, [string]$log_path)
         = "$env:HOME\Desktop"
        while ($true) {
            Start-Sleep -Seconds $period
            $timestamp = (Get-Date)
            $result = $null
            try {
                $url = "https://$function_name.azurewebsites.net/api/HttpTrigger?busySeconds=$process_time"
                "$timestamp Requesting $url" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
                $result = Invoke-WebRequest -Method Get -Uri $url
                "$timestamp Result $result" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            } catch {
                $message = $_.Exception.Message
                "$timestamp Error $message" | Out-File -FilePath "$log_path" -Force -Append -Encoding "string"
            }
        }
    } -Name "$function_name-test" -ArgumentList $function_name,$period,$process_time,"$LOG_PATH\$function_name.log"
}

function testTrigger([string]$type, [int]$period, [int]$process_time) {
    $lowercasedType = $type.ToLower()
    $function_name = "$FunctionPrefix-$lowercasedType-$period-$process_time"
    if ($type.ToLower() -eq "http") {
        testHttpTrigger $function_name $period $process_time
    }
}

function stopTest([string]$type, [int]$period, [int]$process_time) {
    $lowercasedType = $type.ToLower()
    $function_name = "$FunctionPrefix-$lowercasedType-$period-$process_time"
    Stop-Job -Id (Get-Job -Name "$function_name-test").Id
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