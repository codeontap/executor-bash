[#-- Lambda --]

[#-- Resources --]
[#assign AWS_LAMBDA_RESOURCE_TYPE = "lambda"]
[#assign AWS_LAMBDA_FUNCTION_RESOURCE_TYPE = "lambda"]
[#assign AWS_LAMBDA_PERMISSION_RESOURCE_TYPE = "permission"]

[#function formatLambdaPermissionId occurrence extensions...]
    [#return formatResourceId(
                AWS_LAMBDA_PERMISSION_RESOURCE_TYPE,
                occurrence.Core.Id,
                extensions)]
[/#function]

[#function formatLambdaArn lambdaId account={ "Ref" : "AWS::AccountId" }]
    [#return
        formatRegionalArn(
            "lambda",
            getReference(lambdaId))]
[/#function]

[#-- Components --]
[#assign LAMBDA_COMPONENT_TYPE = "lambda"]
[#assign LAMBDA_FUNCTION_COMPONENT_TYPE = "function"]

[#assign componentConfiguration +=
    {
        LAMBDA_COMPONENT_TYPE : {
            "Attributes" : [],
            "Components" : [
                {
                    "Type" : LAMBDA_FUNCTION_COMPONENT_TYPE,
                    "Component" : "Functions",
                    "Link" : "Function"
                }
            ]
        },
        LAMBDA_FUNCTION_COMPONENT_TYPE : [
            {
                "Name" : ["Fragment", "Container"],
                "Type" : "string",
                "Default" : ""
            },
            {
                "Name" : "Handler",
                "Type" : "string",
                "Mandatory" : true
            },
            {
                "Name" : "Links",
                "Subobjects" : true,
                "Children" : linkChildrenConfiguration
            },
            {
                "Name" : "Metrics",
                "Subobjects" : true,
                "Children" : metricChildrenConfiguration
            },
            {
                "Name" : "Alerts",
                "Subobjects" : true,
                "Children" : alertChildrenConfiguration
            }
            {
                "Name" : ["Memory", "MemorySize"],
                "Type" : "number",
                "Default" : 0
            },
            {
                "Name" : "RunTime",
                "Type" : "string",
                "Values" : ["nodejs", "nodejs4.3", "nodejs6.10", "nodejs8.10", "java8", "python2.7", "python3.6", "dotnetcore1.0", "dotnetcore2.0", "dotnetcore2.1", "nodejs4.3-edge", "go1.x"],
                "Mandatory" : true
            },
            {
                "Name" : "Schedules",
                "Subobjects" : true,
                "Children" : [
                    {
                        "Name" : "Expression",
                        "Type" : "string",
                        "Default" : "rate(6 minutes)"
                    },
                    {
                        "Name" : "InputPath",
                        "Type" : "string",
                        "Default" : "/healthcheck"
                    },
                    {
                        "Name" : "Input",
                        "Type" : "array",
                        "Default" : {}
                    }
                ]
            },
            {
                "Name" : "Timeout",
                "Type" : "number",
                "Default" : 0
            },
            {
                "Name" : "VPCAccess",
                "Type" : "boolean",
                "Default" : true
            },
            {
                "Name" : "UseSegmentKey",
                "Type" : "boolean",
                "Default" : false
            },
            {
                "Name" : "Permissions",
                "Children" : [
                    {
                        "Name" : "Decrypt",
                        "Type" : "boolean",
                        "Default" : true
                    },
                    {
                        "Name" : "AsFile",
                        "Type" : "boolean",
                        "Default" : true
                    },
                    {
                        "Name" : "AppData",
                        "Type" : "boolean",
                        "Default" : true
                    },
                    {
                        "Name" : "AppPublic",
                        "Type" : "boolean",
                        "Default" : true
                    }
                ]
            },
            {
                "Name" : "PredefineLogGroup",
                "Type" : "boolean",
                "Default" : false
            },
            {
                "Name" : "EnvironmentAsFile",
                "Type" : "boolean",
                "Default" : false
            }
        ]
    }
]
    
[#function getLambdaState occurrence]
    [#local core = occurrence.Core]

    [#return
        {
            "Resources" : {
                "lambda" : {
                    "Id" : formatResourceId(AWS_LAMBDA_RESOURCE_TYPE, core.Id),
                    "Name" : core.FullName,
                    "Type" : AWS_LAMBDA_RESOURCE_TYPE
                }
            },
            "Attributes" : {
                "REGION" : regionId
            },
            "Roles" : {
                "Inbound" : {},
                "Outbound" : {}
            }
        }
    ]
[/#function]

[#function getFunctionState occurrence]
    [#local core = occurrence.Core]

    [#assign id = formatResourceId(AWS_LAMBDA_FUNCTION_RESOURCE_TYPE, core.Id)]

    [#return
        {
            "Resources" : {
                "function" : {
                    "Id" : id,
                    "Name" : core.FullName,
                    "Type" : AWS_LAMBDA_FUNCTION_RESOURCE_TYPE
                },
                "lg" : {
                    "Id" : formatLogGroupId(core.Id),
                    "Name" : formatAbsolutePath("aws", "lambda", core.FullName),
                    "Type" : AWS_CLOUDWATCH_LOG_GROUP_RESOURCE_TYPE
                }
            },
            "Attributes" : {
                "REGION" : regionId,
                "ARN" : formatArn(
                            regionObject.Partition,
                            "lambda", 
                            regionId,
                            accountObject.AWSId,
                            "function:" + core.FullName,
                            true),
                "NAME" : core.FullName
            },
            "Roles" : {
                "Inbound" : {},
                "Outbound" : {
                    "invoke" : lambdaInvokePermission(id)
                }
            }
        }
    ]
[/#function]
