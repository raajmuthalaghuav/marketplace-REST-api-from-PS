#----------------please type user inputs below....
$RESTAPIServer = "1.48.70.114"
$RESTAPIUser = "admin"
$RESTAPIPassword = "Nutanix/4U"

$MPIName = "SingleService"
$MPIVersion = "1.1.1.1" 
$ProjectName = "default"
$AppName = "RaajApp8"
#---------end of user input

# Environment setting
if ("TrustAllCertsPolicy" -as [type]) {} else {
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

$BaseURL = "https://" + $RESTAPIServer + ":9440/api/nutanix/v3/"
$Header = @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RESTAPIUser+":"+$RESTAPIPassword))}
$Type = "application/json"

#----------------list project
$URL = $BaseURL+"projects/list"
$body = @"
{ "kind" : "project",
  "offset": 0,
  "length": 123
}
"@
try {
    $response = Invoke-WebRequest -Uri $URL -Method "POST" -Headers $Header -Body $body -ContentType $Type -UseBasicParsing
}Catch { 
    write-host "Please Check the user inputs at the beginning of the code. $($_.Exception.Message)"  -ForegroundColor Red; exit 1
 }
$x = $response | ConvertFrom-Json
$project_uuid = ($x.entities | ? {$_.status.name -eq $ProjectName}).metadata.uuid
echo ("project uuid: " + $project_uuid)

#----------------------- get project object and environment from uuid
$URL = $BaseURL+ "projects/" + $project_uuid
$response = Invoke-WebRequest -Uri $URL -Method "GET" -Headers $Header -ContentType $Type -UseBasicParsing

$Project = $response | ConvertFrom-Json
$env_uuid = $Project.status.resources.environment_reference_list.uuid
echo ("Env uuid : " + $env_uuid)

#---------------------- list mpi
$URL = $BaseURL+"marketplace_items/list"
$body = @" 
{ "filter": "name==$MPIName;version==$MPIVersion",
  "kind" : "marketplace_item",
  "offset": 0,
  "length": 123
} 
"@
$response = Invoke-WebRequest -Uri $URL -Method "POST" -Headers $Header -Body $body -ContentType $Type -UseBasicParsing

$x = $response | ConvertFrom-Json
$mpi_uuid = $x.entities[0].metadata.uuid

echo ("mpi uuid : " + $mpi_uuid)

#------------------------------------- get mpi object from uuid
$URL = $BaseURL+ "calm_marketplace_items/" + $mpi_uuid
$response = Invoke-WebRequest -Uri $URL -Method "GET" -Headers $Header -ContentType $Type -UseBasicParsing

$mpi = $response | ConvertFrom-Json
$bp_name = $mpi.status.resources.app_blueprint_template.status.name

echo ("bp name : " + $bp_name)

#------------simple marketplace bp launch
#list bp
$URL = $BaseURL+"blueprints/list"
$body = @" 
{ "kind" : "blueprint",
  "offset": 0,
  "length": 123
} 
"@
$response = Invoke-WebRequest -Uri $URL -Method "POST" -Headers $Header -Body $body -ContentType $Type -UseBasicParsing
$x = $response | ConvertFrom-Json
$BPuuid = ($x.entities.status | ? {$_.name -eq $bp_name}).uuid
echo ("bp uuid : " + $BPuuid)

#get bp resources, app_profile
$URL = $BaseURL+ "blueprints/" + $BPuuid + "/runtime_editables"
$response = Invoke-WebRequest -Uri $URL -Method "GET" -Headers $Header -ContentType $Type -UseBasicParsing
$y = $response | ConvertFrom-Json
$app_profile = $y.resources.app_profile_reference | ConvertTo-Json
$runtime = $y.resources.runtime_editables | ConvertTo-Json

$body = @"
{
  "spec": {
	"app_profile_reference": $app_profile,
  	"app_name": `"$AppName`",
	"app_description": `"$AppName`"
      }
}
"@

# simple marketplace blueprint launch 
$URL = $BaseURL+ "blueprints/" + $BPuuid +"/simple_launch"
$response = Invoke-WebRequest -Uri $URL -Method "POST" -Headers $Header -Body $body -ContentType $Type -UseBasicParsing
$x = $response | ConvertFrom-Json
$request_id = $x.status.request_id
echo ("mpi request id : " + $request_id)

#------------------- get launch status and app status
echo "Waiting 15s for App to provision..."; Start-Sleep -s 15

$URL = $BaseURL+ "blueprints/" + $BPuuid +"/pending_launches/" + $request_id
$response = Invoke-WebRequest -Uri $URL -Method "GET" -Headers $Header -ContentType $Type -UseBasicParsing
$x = $response | ConvertFrom-Json
$app_uuid = $x.status.application_uuid
echo ("app uuid : " + $app_uuid)

$URL = $BaseURL+ "apps/" + $app_uuid
$response = Invoke-WebRequest -Uri $URL -Method "GET" -Headers $Header -ContentType $Type -UseBasicParsing
$x = $response | ConvertFrom-Json
echo ("Status of Marketplace bp launch: " + $x.status.state)

