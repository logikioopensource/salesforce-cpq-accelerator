# RFQv2 API
## Introduction
Custom, open-source variant of the RFQ API that is included in the Logik.ai Extension for Salesforce CPQ

### Changes in v2
- Option to force the request to run through Asynchronous Apex
- New method of pausing and resuming RFQ until Configuration Line Items for the Configuration Id can be found
  - Replaces the `retryInterval` and `retryCount` parameters, and no longer automatically fails if a certain amount of time has elapsed without finding the requisite Configuration Line Items
  - Option to specify a minimum number of Configuration Line Items that are required before RFQ should resume
- When paused, does not create a Quote until there are line items to be added to it
- More efficient memory management
- New custom object to track paused requests
- **Triggering price calculation automatically is currently not supported**

### Preconditions
This guide assumes the following in Salesforce:
- Users have access to the Configuration Line Item object from the Logik.ai Managed Package
- Users have access to the Salesforce CPQ related objects (such as Quotes, Quote Lines, etc)
- Files in this repo were deployed to your Salesforce org (see README.md at the top directory for more info)
   
## Setup
### Endpoint
/services/apexrest/v2/request-quote
- This can be modified in the Apex class `RequestForQuoteV2Controller`

### Methods
Receives and returns `application/json`

#### POST
For creating a new quote. Required parameters:
- configurableProductId
- configurationId
Optional parameters:
- accountId
- opportunityId
- pricebookId
- quote
- configurableQuoteLine
- forceAsync
- minimumLineCount

> If Account or Opportunity are not specified, Quote has no associated Account or Opportunity
> If Price Book is not specified, Quote is created with a Standard Price Book
> `configurableProductId` and `configurationId` must correspond to the same configurable Product
> `quote` and `configurableQuoteLine` are objects for setting additional fields on the Quote and Configurable Quote Line respectively.
> If `minimumLineCount` is not specified, it defaults to 1. If `forceAsync` is not specified, it defaults to false.

#### PATCH
For adding lines to an existing Quote. Required parameters:
- quoteId
- configurableProductId
- configurationId
Optional parameters:
- quoteLineGroupId
- quote
- configurableQuoteLine
- forceAsync
- minimumLineCount

#### Direct Apex
POST and PATCH requests can be made through Apex directly through the method `processRequest()`. The argument for both is a String defining the method type (POST or PATCH), and a Map<String, Object> with the same fields used in the REST API. All parameters supported by the REST APIs are supported in Apex as well. 

Sample:
```
Map<String, Object> requestBody = new Map<String, Object>{
  'configurableProductId' => '01t8a000005hldvAAA',
  'configurationId' => '79a3ffdd-7dd0-41f6-8700-4bd7506407c7'    
};
String result = RequestForQuoteV2Controller.processRequest('POST', requestBody);
```
The response is a JSON formatted string representing the Quote object, similar to the response in the REST APIs.

### Response
If RFQ is run synchronously (`forceAsync` either false or not specified) and does not pause due to a lack of Configuration Line Items, the response will contain a Quote (`SBQQ__Quote__c`) record
> If a configuration is being added (either through a new or existing quote), it will also include all basic info for each line item, as well as the total count of line items on the quote.
> The Quote info returned will include info on all Quote Lines, not just the ones being added by the request. For example, if the configuration with three line items gets added to a quote that already had two lines on it, the quote info returned will included all five lines.
> For quotes with Line Item Groups enabled:
> - If quoteLineGroupId is specified, quote lines are added to the group with that Id
> - If quoteLineGroupId is not specified, a new quote line group is created and line items are added to the new group

#### Asynchronous Processing
If RFQ is run with `forceAsync` as true, or the request is paused due to a lack of Configuration Line Items, initial request will return a status code 202 (Accepted) with a reference to a Quoting Request (`QuotingRequest__c`) record. This record will initially store details about the request that was sent. If the request is resumed, this record will also be updated with details such as the status of the request, how many Configuration Line Items were found/used, etc.

##### Resuming RFQ
In the original version of RFQ, the API would spend CPU cycles waiting for a specified amount of time, with a set number of retry attempts, as well as the number of seconds between each retry. With v2, there is a Record-Triggered Flow on the Configuration Line Item object. Upon creation of Configuration Line Items, the flow will evaluate if there is a pending request for that Configuration Id, and decide whether RFQ should resume. The conditions and logic of this Flow can be modified in the flow “Logik.ai Configuration Line Item for RFQ” (`ConfigurationLineItemForRFQ`).

### Logik.ai Managed Package Settings
> These settings and their behavior are unchanged from the original RFQ API.

#### Heap Size Limits
In some cases the heap size of the request of the request sent to CPQ may be too large. This can occur if there are a large number of quote lines being created, or if the size of each individual quote line record is very large (for example, if there are a very large number of custom fields). Thus, there isn’t a specific number of quote lines that can be created as a general policy, but rather this can vary by Salesforce environment and configuration.

The main way to allocate more memory is to run with `forceAsync` as true. However, if that alone is not enough there are two settings that may help address heap size issues, `Child Line Size Limit for Request Quote API` and `BOM Data Types for API Services`.

##### Child Line Size Limit for Request Quote API
This will limit the number of config lines that can be converted to Quote Lines. If some lines are removed from the bundle as a result of this limit, an e-mail will be sent to the user with the subject “Request For Quote Size Warning”. A value of 0 (default) will have no size limits.

##### BOM Data Types for API Services
Despite the label, this also affects Request for Quote. This will limit the kinds of BOM items that are written to the quote line field `LGK__BomData__c`. Multiple values can be entered, separated by comma (case-insensitive). A blank value (default) will include all BOM types.

> These two settings work independently of each other. Limiting the child line size will not apply to BOM Data, and the BOM Data filter will not apply to quote line generation.

#### E-mail Notifications
In some cases, RFQ will sometimes result an e-mail notifications if a particular error or warning occurred. These e-mail notifications have two settings, Skip E-mail Notifications for RFQ and E-mail Recipient Override.

##### Skip E-mail Notifications for RFQ
This disables e-mails from RFQ completely.

##### E-mail Recipient Override
As long as `Skip E-mail Notifications for RFQ` is not set to true, the e-mail address(es) provided in this field will be the recipient of all RFQ-generated e-mails. Multiple addresses can be defined, separated by commas. If the field is left blank, e-mails are sent to the original user (most times, the user that initiated the request).

### Examples
#### Request (Create New Quote)
```
{
    "configurableProductId": "01t8a0000061GQPAA2",
    "configurationId": "e5d03bc8-c48b-470f-8bb9-1bbcdce411fa",
    "accountId": "0018a00001nsFoNAAU",
    "pricebookId": "01s8a000000sMP6AAM",
    "quote": {
      "SBQQ__Primary__c": true,
      "SBQQ__LineItemsGrouped__c": true
    },
    "configurableQuoteLine": {
      "SBQQ__Taxable__c": true,
      "SBQQ__PricingMethod__c": "Percent Of Total"
    },
    "forceAsync": true,
    "minimumLineCount": 10
}
```

#### Request (Add to Existing Quote)
```
{
    "quoteId": "a0zR0000003f3GLIAY",
    "configurableProductId": "01tR000000B1RiKIAV",
    "configurationId": "dbd317a9-1d1b-4f2c-8b3b-b7a3e6ee87d4",
    "quoteLineGroupId": "a0t8a00000BQNjD",
    "quote": {
      "SBQQ__StartDate__c": "2023-05-11",
      "SBQQ__EndDate__c": "2028-05-11"
    },
    "configurableQuoteLine": {
      "SBQQ__CostEditable__c": true,
      "SBQQ__PricingMethod__c": "Cost"
    },
    "forceAsync": true,
    "minimumLineCount": 10
}
```

#### Response (Synchronous)
```
{
    "attributes": {
        "type": "SBQQ__Quote__c",
        "url": "/services/data/v56.0/sobjects/SBQQ__Quote__c/a0zR0000003f3GLIAY"
    },
    "Name": "Q-00090",
    "Id": "a0zR0000003f3GLIAY",
    "SBQQ__LineItemCount__c": 4,
    "SBQQ__LineItems__r": {
        "totalSize": 4,
        "done": true,
        "records": [{
                "attributes": {
                    "type": "SBQQ__QuoteLine__c",
                    "url": "/services/data/v56.0/sobjects/SBQQ__QuoteLine__c/a0vR0000005LPRxIAO"
                },
                "SBQQ__Quote__c": "a0zR0000003f3GLIAY",
                "Id": "a0vR0000005LPRxIAO",
                "Name": "QL-0000122",
                "SBQQ__ProductName__c": "LGK Machine"
            }, {
                "attributes": {
                    "type": "SBQQ__QuoteLine__c",
                    "url": "/services/data/v56.0/sobjects/SBQQ__QuoteLine__c/a0vR0000005LPRyIAO"
                },
                "SBQQ__Quote__c": "a0zR0000003f3GLIAY",
                "Id": "a0vR0000005LPRyIAO",
                "Name": "QL-0000123",
                "SBQQ__ProductName__c": "Analytics Software"
            }, {
                "attributes": {
                    "type": "SBQQ__QuoteLine__c",
                    "url": "/services/data/v56.0/sobjects/SBQQ__QuoteLine__c/a0vR0000005LPS2IAO"
                },
                "SBQQ__Quote__c": "a0zR0000003f3GLIAY",
                "Id": "a0vR0000005LPS2IAO",
                "Name": "QL-0000124",
                "SBQQ__ProductName__c": "Extended Warranty"
            }, {
                "attributes": {
                    "type": "SBQQ__QuoteLine__c",
                    "url": "/services/data/v56.0/sobjects/SBQQ__QuoteLine__c/a0vR0000005LPS3IAO"
                },
                "SBQQ__Quote__c": "a0zR0000003f3GLIAY",
                "Id": "a0vR0000005LPS3IAO",
                "Name": "QL-0000125",
                "SBQQ__ProductName__c": "Scanner"
            }
        ]
    },
    "SBQQ__Type__c": "Quote"
}
```

#### Response (Paused/Asynchronous)
```
{
  "status" : "Pending",
  "message" : "Request is pending.",
  "quotingRequest" : {
    "attributes" : {
      "type" : "QuotingRequest__c",
      "url" : "/services/data/v63.0/sobjects/QuotingRequest__c/a1Q8a000009RFstEAG"
    },
    "RequestPayload__c" : "{\"forceAsync\":true,\"configurationId\":\"dbd317a9-1d1b-4f2c-8b3b-b7a3e6ee87d4\",\"configurableProductId\":\"01t8a000009UtbKAAS\"}",
    "ConfigurationId__c" : "dbd317a9-1d1b-4f2c-8b3b-b7a3e6ee87d4",
    "ConfigurableProduct2Id__c" : "01t8a000009UtbKAAS",
    "MinimumConfigurationLineItemSize__c" : null,
    "Status__c" : "Pending",
    "MatchingConfigurationLineItemSize__c" : 0,
    "RunAsynchronousApex__c" : true,
    "Id" : "a1Q8a000009RFstEAG"
  }
}
```