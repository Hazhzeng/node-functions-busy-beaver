param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$StorageName,
    [Parameter(Mandatory=$true)][string]$FunctionPrefix,
    [string]$Command = "create"
)

$PERIODS = 5
$PROCESS_TIMES = 1
$TYPES = "http", "queue", "blob"
$DEPLOYMENT_PATH = "$PSScriptRoot\deployment"
$PROJECT_ROOT = "$PSScriptRoot\.."

function create([string]$resourceGroupName, [string]$storageName, [string]$functionPrefix) {
    ForEach ($period in $PERIODS) {
        ForEach ($process_time in $PROCESS_TIMES) {
            ForEach($type in $TYPES) {
                $function_name = "$functionPrefix-$type-$period-$process_time"
                Start-Process -FilePath "az" -NoNewWindow -ArgumentList functionapp,create,"-n","$function_name","-s","$storageName","-g","$resourceGroupName","-c",westus,"--os-type",Linux,"--runtime",node,"--disable-app-insights"
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
    Write-Host -ForegroundColor Yellow "Deploying to function app... Check your portal constantly."
}