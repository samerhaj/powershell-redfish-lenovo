﻿###
#
# Lenovo Redfish examples - Get the System information
#
# Copyright Notice:
#
# Copyright 2018 Lenovo Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
###


###
#  Import utility libraries
###
Import-module $PSScriptRoot\lenovo_utils.psm1

function lenovo_get_system_inventory
{
    <#
   .Synopsis
    Cmdlet used to get system inventory
   .DESCRIPTION
    Cmdlet used to get system inventory from BMC using Redfish API. system info will be printed to the screen. Connection information can be specified via command parameter or configuration file.
    - ip: Pass in BMC IP address
    - username: Pass in BMC username
    - password: Pass in BMC username password
    - system_id:Pass in ComputerSystem instance id(None: first instance, all: all instances)
    - config_file: Pass in configuration file path, default configuration file is config.ini.
   .EXAMPLE
    lenovo_get_system_inventory -ip 10.10.10.10 -username USERID -password PASSW0RD
   #>
   
    param(
        [Parameter(Mandatory=$False)]
        [string]$ip="",
        [Parameter(Mandatory=$False)]
        [string]$username="",
        [Parameter(Mandatory=$False)]
        [string]$password="",
        [Parameter(Mandatory=$False)]
        [string]$system_id="None",
        [Parameter(Mandatory=$False)]
        [string]$config_file="config.ini"
        )
        

    # Get configuration info from config file
    $ht_config_ini_info = read_config -config_file $config_file
    
    # If the parameter is not specified via command line, use the setting from configuration file
    if ($ip -eq "")
    { 
        $ip = [string]($ht_config_ini_info['BmcIp'])
    }
    if ($username -eq "")
    {
        $username = [string]($ht_config_ini_info['BmcUsername'])
    }
    if ($password -eq "")
    {
        $password = [string]($ht_config_ini_info['BmcUserpassword'])
    }
    if ($system_id -eq "")
    {
        $system_id = [string]($ht_config_ini_info['SystemId'])
    }

    try
    {
        $session_key = ""
        $session_location = ""

        # Create session
        $session = create_session -ip $ip -username $username -password $password
        $session_key = $session.'X-Auth-Token'
        $session_location = $session.Location

        # Build headers with sesison key for authentication
        $JsonHeader = @{ "X-Auth-Token" = $session_key
        }
        
        # Get the system url collection
        $system_url_collection = @()
        $system_url_collection = get_system_urls -bmcip $ip -session $session -system_id $system_id

        # Loop all System resource instance in $system_url_collection
        foreach($system_url_string in $system_url_collection)
        {
            # Hash table for system info
            $ht_system_info = @{}

            # Get system resource
            $url_address_system = "https://$ip" + $system_url_string
            $response = Invoke-WebRequest -Uri $url_address_system -Headers $JsonHeader -Method Get -UseBasicParsing
            $converted_object = $response.Content | ConvertFrom-Json
            $ht_system_info["HostName"] = $converted_object.HostName
            $ht_system_info["Model"] = $converted_object.Model
            $ht_system_info["SerialNumber"] = $converted_object.SerialNumber
            $ht_system_info["AssetTag"] = $converted_object.AssetTag
            $ht_system_info["UUID"] = $converted_object.UUID
            $ht_system_info["ProcesorsModel"] = $converted_object.ProcessorSummary.Model
            $ht_system_info["ProcesorsCount"] = $converted_object.ProcessorSummary.Count
            $ht_system_info["TotalSystemMemoryGiB"] = $converted_object.MemorySummary.TotalSystemMemoryGiB
            $ht_system_info["BiosVersion"] = $converted_object.BiosVersion

            # Get System EtherNetInterfaces resources
            $nics_url = "https://$ip" + $converted_object.EthernetInterfaces."@odata.id"
            $nics_response = Invoke-WebRequest -Uri $nics_url -Headers $JsonHeader -Method Get -UseBasicParsing
            $converted_nics = $nics_response.Content | ConvertFrom-Json
            $nics_count = $converted_nics."Members@odata.count"
            $list_ethernetinterface = @()
            # Loop nic resource in EtherNetInterfaces resource
            for($num = 0;$num -lt $nics_count;$num ++)
            {
                $ht_ethernetinterface = @{}

                # Get nic_x info
                $nic_x_url = "https://$ip" + $converted_nics.Members[$num]."@odata.id"
                $nic_x_response = Invoke-WebRequest -Uri $nic_x_url -Headers $JsonHeader -Method Get -UseBasicParsing
                $convert_nic_x = $nic_x_response.Content | ConvertFrom-Json

                # Psobject
                $ht_ethernetinterface["PermanentMACAddress"] = $convert_nic_x.PermanentMACAddress
                $object = [pscustomobject]$ht_ethernetinterface
                $list_ethernetinterface += $object.PSObject.ToString()
            }
            $ht_system_info["EtherNetInterfaces"] = $list_ethernetinterface
           
            # Return result
            $ht_system_info
            Write-Host ""  
        }
    }
    catch
    {
        # Handle http exception response
        if($_.Exception.Response)
        {
            Write-Host "Error occured, error code:" $_.Exception.Response.StatusCode.Value__
            if ($_.Exception.Response.StatusCode.Value__ -eq 401)
            {
                Write-Host "Error message: You are required to log on Web Server with valid credentials first."
            }
            elseif ($_.ErrorDetails.Message)
            {
                $response_j = $_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -Expand error
                $response_j = $response_j | Select-Object -Expand '@Message.ExtendedInfo'
                Write-Host "Error message:" $response_j.Resolution
            }
            else
            {
                Write-Host "Error message:" $_.Exception.Message
                Write-Host "Please check arguments or server status."        
            }
        }
        # Handle system exception response
        elseif($_.Exception)
        {
            Write-Host "Error message:" $_.Exception.Message
            Write-Host "Please check arguments or server status."
        }
        return $False
    }
    # Delete existing session whether script exit successfully or not
    finally
    {
        if ($session_key -ne "")
        {
            delete_session -ip $ip -session $session
        }
    }
}
