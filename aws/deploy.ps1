# Despliega la app en el servidor EC2 desde tu ordenador, SIN SSH:
# copia aws/deploy/* al servidor y ejecuta deploy.sh, usando SSM Run Command.
#
# Uso:  .\aws\deploy.ps1                 (despliega la imagen "latest")
#       .\aws\deploy.ps1 -Tag v2         (despliega una versión concreta)
param([string]$Tag = "latest")
$ErrorActionPreference = "Stop"

$aws = "aws"
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { $aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe" }
. "$PSScriptRoot\config.ps1"      # $instanceId (no está en git: ver config.example.ps1)
$dbHost = & $aws rds describe-db-instances --db-instance-identifier ragpeat-db --query "DBInstances[0].Endpoint.Address" --output text

# La app no necesita credenciales de AWS (sus claves le llegan en .env). Con IMDSv2 obligatorio y un solo salto de
# red, al servicio de metadatos solo llega el propio servidor (deploy.sh, Docker), no los contenedores: quien se
# colara en la app no podría sacar las credenciales del rol. Si ya está así, no cambia nada.
& $aws ec2 modify-instance-metadata-options --instance-id $instanceId --http-tokens required `
    --http-put-response-hop-limit 1 --http-endpoint enabled | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "Aviso: no se pudo limitar el servicio de metadatos del servidor" }

# Cada archivo viaja en base64 dentro del comando: así no hay problemas con comillas ni saltos de línea.
$commands = @("mkdir -p /opt/ragpeat")
foreach ($file in "docker-compose.yml", "Caddyfile", "deploy.sh") {
    $content = [IO.File]::ReadAllText("$PSScriptRoot\deploy\$file") -replace "`r`n", "`n"   # saltos de línea de Linux
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    $commands += "echo $b64 | base64 -d > /opt/ragpeat/$file"
}
$commands += "chmod +x /opt/ragpeat/deploy.sh"
$commands += "/opt/ragpeat/deploy.sh $dbHost $Tag"

$paramsFile = New-TemporaryFile
@{ commands = $commands } | ConvertTo-Json | Set-Content -Path $paramsFile -Encoding ascii
$commandId = & $aws ssm send-command --instance-ids $instanceId --document-name AWS-RunShellScript `
    --comment "deploy rag-peat $Tag" --parameters "file://$paramsFile" --query Command.CommandId --output text
Remove-Item $paramsFile

Write-Host "Desplegando ($commandId)..."
& $aws ssm wait command-executed --command-id $commandId --instance-id $instanceId 2>$null
& $aws ssm get-command-invocation --command-id $commandId --instance-id $instanceId `
    --query "[Status, StandardOutputContent, StandardErrorContent]" --output text
