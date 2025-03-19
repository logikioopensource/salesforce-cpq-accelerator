/**
 * @date 2025
 * @description RFQ v2. Changes from v1:
 *      - New request parameters: minimumLineCount, forceAsync
 *      - Replaces the "async retry" method in v1 with a "pause and resume" approach detailed in LGK-13862
 *      - Removes support for quote Id in URL path for PATCH
 */
@SuppressWarnings('PMD.AvoidDebugStatements')
@RestResource(urlMapping='/v2/request-quote')
global with sharing class RequestForQuoteV2Controller {
    public static LGK__ConfigurationTenant__c customSettings = LGK__ConfigurationTenant__c.getInstance();
    private static Integer returnStatusCode = 200;
    private static String errorMessage = '';
    private static String originalRequest;

    /**
     * @description Accepts a JSON request and passes it into processRequest()
     */
    @HttpPost
    global static void createQuote() {
        // Process request and call method
        String responseBodyString = processRequest(
            'POST',
            (Map<String, Object>)JSON.deserializeUntyped(
                RestContext.request.requestBody.toString()
            )
        );

        // Set response
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        response.statusCode = returnStatusCode;
        response.responseBody = Blob.valueOf(responseBodyString);
    }

    /**
     * @description Accepts a JSON request and passes it into processRequest()
     */
    @HttpPatch
    global static void addToQuote() {
        // Process request
        RestRequest request = RestContext.request;
        Map<String, Object> requestBody = (Map<String, Object>)JSON.deserializeUntyped(
            request.requestBody.toString()
        );

        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        
        // Set response
        String responseBodyString = processRequest('PATCH', requestBody);
        response.statusCode = returnStatusCode;
        response.responseBody = Blob.valueOf(responseBodyString);
    }

    /**
     * @description Creates a quote and adds config lines as quote lines
     * @param httpMethod String, only 'POST' or 'PATCH' currently supported
     * @param requestBody JSON request, deserialized as an untyped map
     * @return Response body string. If successful, quote data. If the request has to be paused, the quoting request data. Otherwise, an error message
     */
    global static String processRequest(String httpMethod, Map<String, Object> requestBody) {
        // Parse request
        String configurableProductId = String.valueOf(requestBody.get('configurableProductId')),
            configurationId = String.valueOf(requestBody.get('configurationId')),
            pricebookId = String.valueOf(requestBody.get('pricebookId')),
            accountId = String.valueOf(requestBody.get('accountId')),
            opportunityId = String.valueOf(requestBody.get('opportunityId')),
            quoteId = String.valueOf(requestBody.get('quoteId')),
            quoteLineGroupId = String.valueOf(requestBody.get('quoteLineGroupId')),
            quotingRequestId = String.valueOf(requestBody.get('quotingRequestId'));
        Boolean forceAsync = requestBody.containsKey('forceAsync') ? 
            Boolean.valueOf(requestBody.get('forceAsync')) : false;
        Integer minimumLineCount = requestBody.containsKey('minimumLineCount') ? 
            Integer.valueOf(requestBody.get('minimumLineCount')) : 1;

        // Exit with an error if required fields are missing
        if (!requestHasAllRequiredField(configurableProductId, configurationId, httpMethod, quoteId)) {
            return errorMessage;
        }

        // Check current count of matching Config Line Items to see if we should proceed
        // Create QuotingRequest record if needed, or retrieve it if there is one already
        QuotingRequest__c quotingRequest;
        if (String.isNotBlank(quotingRequestId)) {
            try {
                quotingRequest = [
                    SELECT Status__c, CompletedDate__c, QuoteId__c, ErrorResponse__c
                    FROM QuotingRequest__c
                    WHERE Id = :quotingRequestId
                    WITH USER_MODE
                    LIMIT 1
                ];
            } catch (QueryException qe) {
                quotingRequest = null;
            }
        }
        else {
            try {
                Integer matchingSalesConfigLineCount = [
                    SELECT count()
                    FROM LGK__ConfigurationLineItem__c
                    WHERE (LGK__ConfigurationId__c = :configurationId AND LGK__Type__c = 'Sales')
                    WITH USER_MODE
                ];

                if (forceAsync && matchingSalesConfigLineCount >= minimumLineCount) {
                    quotingRequest = createQuotingRequest(requestBody, matchingSalesConfigLineCount, true);
                    // Update request so jobs aren't continually created
                    requestBody.put('forceAsync', false);
                    quotingRequest.AsyncJobId__c = System.enqueueJob(new RequestForQuoteV2Async(httpMethod, requestBody));
                    Database.insert(quotingRequest, true, AccessLevel.USER_MODE);
                    return pendingStatusResponse(quotingRequest);
                }
                else if (matchingSalesConfigLineCount < minimumLineCount) { // When not defined, minimumLineCount defaults to 1
                    quotingRequest = createQuotingRequest(requestBody, matchingSalesConfigLineCount, forceAsync);
                    Database.insert(quotingRequest, true, AccessLevel.USER_MODE);
                    return pendingStatusResponse(quotingRequest);
                }
            } catch (QueryException qe) {
                handleException(
                    qe.getStackTraceString() + ': ' + qe.getMessage(),
                    'QUERY_EXCEPTION',
                    quotingRequest
                );
                return errorMessage;
            } catch (NullPointerException npe) {
                handleException(
                    npe.getStackTraceString() + ': ' + npe.getMessage(),
                    'NULL_POINTER_EXCEPTION',
                    quotingRequest
                );
                return errorMessage;
            } catch (DmlException de) {
                handleException(
                    de.getStackTraceString() + ': ' + de.getMessage() + ' | Error on Fields: ' + de.getDmlFieldNames(0),
                    'DML_EXCEPTION',
                    quotingRequest
                );
                return errorMessage;
            }
        }

        // Create new quote
        if (httpMethod.equalsIgnoreCase('POST')) {
            quoteId = createNewQuote(pricebookId, accountId, opportunityId, quotingRequest);
            if (!(quoteId instanceof Id)) {
                return errorMessage;
            }
            else {
                requestBody.put('quoteId', quoteId);
            }
        }

        // Get custom field data from request
        Map<String, Object> requestQuoteFields = (Map<String, Object>)requestBody.get('quote'),
            requestConfigurableQuoteLineFields = (Map<String, Object>)requestBody.get('configurableQuoteLine');

        // Build productsJsonArray, sales BOM list, childParentMap, BomData field
        Map<String, String> childParentMap = new Map<String, String>{}; // Do we still need this?
        LGK__ConfigurationLineItem__c[] salesConfigLineItemsList = new LGK__ConfigurationLineItem__c[]{};   // To update Quote Lines with later
        
        Map<String, JSONGenerator> jsonReturn = constructBoms(
            configurationId, configurableProductId, salesConfigLineItemsList, childParentMap, quotingRequest
        );
        JSONGenerator bomDataFieldJson = jsonReturn.get('bomDataFieldJson'),
            productsJsonArray = jsonReturn.get('productsJsonArray');

        if (returnStatusCode == 400) {  // In case JSON builder encountered an NPE
            return errorMessage;
        }

        // Get Feature and Group Info
        Id featureId;
        Boolean isGrouped;
        try {
            featureId = [
                SELECT Id
                FROM SBQQ__ProductFeature__c
                WHERE (Name = 'Dynamic' AND SBQQ__ConfiguredSKU__c = :configurableProductId)
                WITH USER_MODE
                LIMIT 1
            ].Id;
            // In case user didn't specify whether quote is grouped or, check the quote
            isGrouped = [
                SELECT SBQQ__LineItemsGrouped__c
                FROM SBQQ__Quote__c
                WHERE Id = :quoteId
                WITH USER_MODE
                LIMIT 1
            ].SBQQ__LineItemsGrouped__c;
            quoteLineGroupId = createQuoteLineGroup(isGrouped, quoteLineGroupId, quoteId);
        } catch (QueryException qe) {
            handleException(
                qe.getStackTraceString() + ': ' + qe.getMessage(),
                'QUERY_EXCEPTION',
                quotingRequest
            );
            return errorMessage;
        }

        // Call CPQ APIs, set custom fields from request, return parts of response we need later
        Map<String, Object> sbqqResponse = addProductsToQuote(quoteId, requestQuoteFields, isGrouped, quoteLineGroupId, productsJsonArray);
        Map<String, Object> quoteMap = (Map<String, Object>)sbqqResponse.get('quoteMap');
        Integer rootNumber = Integer.valueOf(
            String.valueOf(
                sbqqResponse.get('rootNumber')
            )
        ),
        nextKey = Integer.valueOf(
            String.valueOf(
                sbqqResponse.get('nextKey')
            )
        ),
        nextNumber = Integer.valueOf(
            String.valueOf(
                sbqqResponse.get('nextNumber')
            )
        );

        Object[] quoteLinesList = (Object[])quoteMap.get('lineItems');
            Map<String, Object> quoteLine = (Map<String, Object>)quoteLinesList[nextKey - 1];
            Integer rootKey = Integer.valueOf(quoteLine.get('key'));

        // Set Feature, Quantity, Price for child line(s)
        Integer configLineItemIndex = 0;
        Map<String, Integer> parentKeyMap = new Map<String, Integer>{};
        Map<Integer, Integer> missingParentIndexMap = new Map<Integer, Integer>{}; // <Quote Line Index, Config Line Index>
        
        for (Integer index = nextKey; index < quoteLinesList.size(); index++) {
            quoteLine = (Map<String, Object>)quoteLinesList[index];
            Map<String, Object> quoteLineMap = (Map<String, Object>)quoteLine.get('record');
            String quoteLineProductId = String.valueOf(
                quoteLineMap.get('SBQQ__Product__c')
            );
            LGK__ConfigurationLineItem__c configLineItem = salesConfigLineItemsList[configLineItemIndex];
            
            quoteLine.put('parentItemKey', rootKey);
            // If parent line, save key
            if (String.isNotEmpty(configLineItem.LGK__UniqueId__c) && childParentMap.values().contains(configLineItem.LGK__UniqueId__c)) {
                parentKeyMap.put(configLineItem.LGK__UniqueId__c, (Integer)quoteLine.get('key'));
            }
            // If child, see if parent key has been saved. Otherwise, parent line may not have been processed yet so save to list for later
            if (String.isNotEmpty(configLineItem.LGK__ParentProductId__c)) {
                if (parentKeyMap.containsKey(childParentMap.get(configLineItem.LGK__UniqueId__c))) {
                    quoteLine.put('parentItemKey', parentKeyMap.get(configLineItem.LGK__ParentProductId__c));
                }
                else {
                    missingParentIndexMap.put(index, configLineItemIndex);
                }
            }
            quoteLineMap.put('SBQQ__DynamicOptionId__c', featureId + ':' + quoteLineProductId);
            quoteLineMap.put('SBQQ__Quantity__c', configLineItem.LGK__Quantity__c);
            quoteLineMap.put('SBQQ__ListPrice__c', configLineItem.LGK__Price__c);
            quoteLineMap.put('SBQQ__OptionLevel__c', Integer.valueOf(configLineItem.LGK__Level__c) + 1);
            quoteLineMap.put('SBQQ__Number__c', nextNumber);
            if (String.isNotEmpty(configLineItem.LGK__UniqueId__c)) {
                quoteLineMap.put('LGK__UniqueId__c', String.valueOf(configLineItem.LGK__UniqueId__c));
            }
            nextNumber++;
            if (isGrouped) {
                quoteLineMap.put('SBQQ__Group__c', quoteLineGroupId);
            }
            
            quoteLine.put('record', quoteLineMap);
            quoteLinesList[index] = (Object)quoteLine;
            configLineItemIndex++;
        }

        // Go over lines that haven't had parent keys updated yet
        for (Integer each : missingParentIndexMap.keySet()) {
            quoteLine = (Map<String, Object>)quoteLinesList[each];
            LGK__ConfigurationLineItem__c configLineItem = salesConfigLineItemsList[missingParentIndexMap.get(each)];

            if (parentKeyMap.containsKey(configLineItem.LGK__ParentProductId__c)) {
                quoteLine.put('parentItemKey', parentKeyMap.get(configLineItem.LGK__ParentProductId__c));
            }
            else {  // If parent still can't be found, bundle under configurable product
                quoteLine.put('parentItemKey', rootKey);
            }
            
            quoteLinesList[each] = (Object)quoteLine;
        }
        
        // Set config Id, BOM on root line
        quoteLine = (Map<String, Object>)quoteLinesList[nextKey - 1];
        Map<String, Object> configurableQuoteLineFieldsMap = new Map<String, Object>{
            'configurationId' => configurationId,
            'bomData' => bomDataFieldJson.getAsString(),
            'rootNumber' => rootNumber,
            'isGrouped' => isGrouped,
            'quoteLineGroupId' => quoteLineGroupId
        };

        Map<String, Object> configurableQuoteLineMap = updateConfigurableQuoteLine(quoteLine, configurableQuoteLineFieldsMap);
        updateConfigurableQuoteLineCustomFields(configurableQuoteLineMap, requestConfigurableQuoteLineFields);
        quoteLine.put('record', configurableQuoteLineMap);
        quoteLinesList[nextKey - 1] = (Object)quoteLine;

        // If a quote line size limit has been set, reduce data to fit limit
        if (customSettings.LGK__RfqQuoteLineLimit__c != null && customSettings.LGK__RfqQuoteLineLimit__c > 0) {
            Integer originalQuoteLineSize = quoteLinesList.size();
            while (quoteLinesList.size() > (customSettings.LGK__RfqQuoteLineLimit__c + 1) && !quoteLinesList.isEmpty()) {
                quoteLinesList.remove(quoteLinesList.size() - 1);
            }

            // If quote lines were removed, send an e-mail notification, but not during tests
            if (quoteLinesList.size() < originalQuoteLineSize && 
                !customSettings.LGK__DisableCpqRfqEmails__c && 
                !Test.isRunningTest()
            ) {
                Integer quoteLinesRemoved = originalQuoteLineSize - quoteLinesList.size();
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                String[] recipientsList = String.isBlank(customSettings.LGK__CpqEmailRecipientOverride__c) ? 
                    new String[]{UserInfo.getUserEmail()} : 
                    customSettings.LGK__CpqEmailRecipientOverride__c.split(',');
                mail.setToAddresses(recipientsList);
                mail.setSubject('Request For Quote Size Warning');
                mail.setHtmlBody(
                    'Call to: /services/apexrest/v2/request-quote'
                    + '<br/>Configuration Id ' + configurationId + ' had more child lines than allowed by the Logik.ai Custom Setting in Salesforce. '
                    + String.valueOf(quoteLinesRemoved) + ' Quote Lines were excluded from Quote ' + quoteId
                    + ' in order to prevent a size limit error.'
                    + '<br/>Organization: ' + UserInfo.getOrganizationName() + ' (Id ' + UserInfo.getOrganizationId() + ')'
                );
                Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
            }
        }

        quoteMap.put('lineItems', quoteLinesList);

        // Manual triggering of price calculation not supported yet

        if (quotingRequest != null) {
            quotingRequest.Status__c = 'Completed';
            quotingRequest.CompletedDate__c = Datetime.now();
            quotingRequest.QuoteId__c = quoteId;
            Database.update(quotingRequest, true, AccessLevel.USER_MODE);
        }

        // Save and return quote, end of RFQ
        return SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', JSON.serialize(quoteMap));
    }

    /**
     * @description Checks if the request is missing any required info
     * @param configurableProductId
     * @param configurationId
     * @param httpMethod If PATCH, performs additional check against quoteId
     * @param quoteId Ignored if request is POST
     * @return true if all required fields are present, otherwise false
     */
    public static Boolean requestHasAllRequiredField(
        String configurableProductId, String configurationId,
        String httpMethod, String quoteId
    ) {
        if ((String.isBlank(configurableProductId) || String.isBlank(configurationId)) ||
            (httpMethod.equalsIgnoreCase('PATCH') && String.isBlank(quoteId))
        ) {
            handleException(
                'One or more required fields are missing: quoteId, configurableProductId, configurationId',
                'MISSING_FIELD(S)',
                null
            );
            return false;
        }
        
        return true;
    }

    /**
     * @description Creates a QuotingRequest record with details about the current request, and sets the return status to 202
     * @param requestBody Parameters from user for current request. Other request details can be extracted from this map.
     * @param matchingSalesConfigLineCount The current number of Config Line Items returned by an initial search
     * @param forceAsync
     * @return Saved QuotingRequest record
     */
    public static QuotingRequest__c createQuotingRequest(
        Map<String, Object> requestBody, Integer matchingSalesConfigLineCount, Boolean forceAsync
    ) {
        QuotingRequest__c quotingRequest = new QuotingRequest__c(
            RequestPayload__c = JSON.serialize(requestBody),
            ConfigurationId__c = String.valueOf(requestBody.get('configurationId')),
            ConfigurableProduct2Id__c = String.valueOf(requestBody.get('configurableProductId')),
            MinimumConfigurationLineItemSize__c = Integer.valueOf(requestBody.get('minimumLineCount')),
            Status__c = 'Pending',
            MatchingConfigurationLineItemSize__c = matchingSalesConfigLineCount,
            RunAsynchronousApex__c = forceAsync
        );

        if (requestBody.containsKey('quoteId')) {
            quotingRequest.QuoteId__c = String.valueOf(requestBody.get('quoteId'));
        }

        returnStatusCode = 202;
        return quotingRequest;
    }

    /**
     * @description Creates new quote based on input parameters
     * @param pricebookId Required. If null, defaults to Standard Price Book
     * @param accountId Can be null
     * @param opportunityId Can be null
     * @param quotingRequest Can be null
     * @return quoteId, as String. If there was an exception during price book query, returns an error message instead
     * 
     */
    public static string createNewQuote(
        String pricebookId, String accountId,
        String opportunityId, QuotingRequest__c quotingRequest
    ) {
        // Default to standard price book if one is not defined
        try {
            if (String.isEmpty(pricebookId)) {
                pricebookId = [
                    SELECT Id
                    FROM Pricebook2
                    WHERE IsStandard = true
                    WITH USER_MODE
                    LIMIT 1
                ].Id;
            }
        } catch (QueryException qe) {
            handleException(
                qe.getStackTraceString() + ': ' + qe.getMessage(),
                'QUERY_EXCEPTION',
                quotingRequest
            );
            return errorMessage;
        }
        SBQQ__Quote__c newQuote = new SBQQ__Quote__c();
        // To handle both empty and null values passed in
        if (String.isNotBlank(pricebookId)) {
            newQuote.SBQQ__PriceBookId__c = pricebookId;
        }
        if (String.isNotBlank(accountId)) {
            newQuote.SBQQ__Account__c = accountId;
        }
        if (String.isNotBlank(opportunityId)) {
            newQuote.SBQQ__Opportunity2__c = opportunityId;
        }
        Database.insert(newQuote, true, AccessLevel.USER_MODE);
        return newQuote.Id;
    }

    /**
     *  @description Forms pending response with a reference to the quoting request record
     *  @param quotingRequest
     *  @return JSONString to respond with in the user-submitted call
     */
    public static String pendingStatusResponse(QuotingRequest__c quotingRequest) {
        JSONGenerator statusJson = JSON.createGenerator(true);
        statusJson.writeStartObject();
        statusJson.writeStringField('status', 'Pending');
        statusJson.writeStringField('message', 'Request is pending.');
        statusJson.writeObjectField('quotingRequest', quotingRequest);
        statusJson.writeEndObject();
        
        return statusJson.getAsString();
    }

    /**
     * @description Build the BomData field, productsJsonArray, and salesConfigLineItemsList
     * @param configurationId Used as query criteria
     * @param configurationProductId Used as query criteria
     * @param salesConfigLineItemsList To update quote lines fields with later
     * @param childParentMap To build proper hierarchy on quote lines
     * @param quotingRequest Can be null
     * @return Map of bomDataFieldJson and productsJsonArray
     */
    public static Map<String, JSONGenerator> constructBoms(
        String configurationId, String configurableProductId,
        LGK__ConfigurationLineItem__c[] salesConfigLineItemsList,
        Map<String, String> childParentMap, QuotingRequest__c quotingRequest
    ) {
        JSONGenerator bomDataFieldJson = JSON.createGenerator(true);    // For LGK__BomData__c
        JSONGenerator productsJsonArray = JSON.createGenerator(false);  // For QuoteApi.QuoteProductAdder
        productsJsonArray.writeStartArray();

        // Configurable product
        productsJsonArray.writeStartObject();
        productsJsonArray.writeObjectField('record',
            JSON.deserializeUntyped(
                '{ "attributes": { "type": "Product2" }, "Id": "' + configurableProductId +'", "SBQQ__Incomplete__c": true }'
            )
        );
        productsJsonArray.writeEndObject();
        
        // Get only the Line Item types we need
        String[] bomDataFieldTypes = (customSettings.LGK__CpqApiBomDataTypes__c != null) ?
            customSettings.LGK__CpqApiBomDataTypes__c.split(',') :
            new String[]{};
        String configLineQueryString = 'SELECT LGK__ConfigurationId__c, LGK__ExtendedInformation__c, LGK__Level__c, LGK__ParentProductId__c,' +
            ' LGK__Price__c, LGK__PricingInformation__c, LGK__ProductId__c, LGK__Quantity__c,' +
            ' LGK__RollupPrice__c, LGK__Type__c, LGK__UniqueId__c, LGK__UOM__c' + 
            ' FROM LGK__ConfigurationLineItem__c' +
            ' WHERE LGK__ConfigurationId__c = \'' + String.escapeSingleQuotes(configurationId) + '\'',
        typeClause;
        if (bomDataFieldTypes.isEmpty()) {
            typeClause = ' AND LGK__Type__c != null';
        }
        else {
            typeClause = ' AND (LGK__Type__c IN :bomDataFieldTypes OR LGK__Type__c = \'Sales\')';
        }
        configLineQueryString += typeClause + ' AND LGK__ProductId__c != null WITH USER_MODE';
        LGK__ConfigurationLineItem__c[] originalConfigLineItemsList = Database.query(configLineQueryString);

        Id[] productIdList = new Id[]{};
        for (LGK__ConfigurationLineItem__c each : originalConfigLineItemsList) {
            if (each.LGK__Type__c.equalsIgnoreCase('Sales') && (each.LGK__ProductId__c instanceof Id)) {
                try {
                    Id productId = Id.valueOf(each.LGK__ProductId__c);
                    if (productId.getSObjectType() == Product2.SObjectType) {
                        salesConfigLineItemsList.add(each);             // Instead of assigning the whole query to the list, we only want to add records that have valid ProductId
                        productIdList.add(productId);                   // Add to lists used to query products later
    
                        // Child products JSON for QuoteApi.QuoteProductAdder
                        productsJsonArray.writeStartObject();
                        productsJsonArray.writeObjectField('record',
                            JSON.deserializeUntyped(
                                '{ "attributes": { "type": "Product2" }, "Id": "' + productId +'", "SBQQ__Incomplete__c": true }'
                            )
                        );
                        productsJsonArray.writeEndObject();
    
                        // Save map of parent Ids
                        if (String.isNotEmpty(each.LGK__ParentProductId__c)) {
                            childParentMap.put(each.LGK__UniqueId__c, each.LGK__ParentProductId__c);
                        }
                    }
                } catch (StringException se) {
                    // ProductId value didn't match Id format
                    se.setMessage(se.getMessage() + ' | ' + se.getStackTraceString() + ' | buildProductAndConfigLinesList()');
                    throw se;
                }
            }
        }

        // BomData needs to be built in separate list since we need a finished productIdList
        bomDataFieldJson = constructBomDataFieldJson(originalConfigLineItemsList, productIdList, bomDataFieldTypes, quotingRequest);

        return new Map<String, JSONGenerator>{
            'bomDataFieldJson' => bomDataFieldJson,
            'productsJsonArray' => productsJsonArray
        };
    }

    /**
     * @description Builds the LGK__BomData__c field JSON to be saved on Configurable Quote Line. Used by constructBoms()
     * @param configLineItemsList Config Line Item list of all the eligible types for this configuration (automatically includes Sales, so we need to compare to bomDataTypes)
     * @param productIdList List of product Ids
     * @param bomDataFieldTypes Original list of types set by the custom setting LGK__CpqApiBomDataTypes__c (may not include Sales)
     * @param quotingRequest Can be null
     * @return BomData JSON
     */
    public static JSONGenerator constructBomDataFieldJson(
        LGK__ConfigurationLineItem__c[] configLineItemsList, Id[] productIdList,
        String[] bomDataFieldTypes, QuotingRequest__c quotingRequest
    ) {
        // Get related product info that isn't part of the Config Line Item record
        Map<Id, Product2> configProductsMap = new Map<Id, Product2>([
            SELECT Id, Name, ProductCode, Description, Family, ExternalId
            FROM Product2
            WHERE Id
            IN :productIdList
            WITH USER_MODE
        ]);

        Decimal bomTotal = 0;
        JSONGenerator bomDataFieldJson = JSON.createGenerator(true);
        bomDataFieldJson.writeStartObject();
        bomDataFieldJson.writeFieldName('items');
        bomDataFieldJson.writeStartArray();

        // Build BomData string for types defined by LGK__CpqApiBomDataTypes__c (or all types, if empty)
        Boolean addAllTypes = bomDataFieldTypes.isEmpty();
        for (LGK__ConfigurationLineItem__c each : configLineItemsList) {
            // This should only exclude Sales type if LGK__CpqApiBomDataTypes__c didn't explicitly include it
            try {
                if (addAllTypes || bomDataFieldTypes.contains(each.LGK__Type__c)) {
                    bomDataFieldJson.writeStartObject();
                    // Can't determine which productId (partner, code, external) is being used without calling Logik. For now, id is always LGK__ProductId__c
                    bomDataFieldJson.writeStringField('id', each.LGK__ProductId__c);
                    bomDataFieldJson.writeNumberfield('quantity', each.LGK__Quantity__c);
                    // Also, type (not bomType) isn't in Line Items, so those are also excluded
                    bomDataFieldJson.writeStringField('bomType', each.LGK__Type__c);
                    bomDataFieldJson.writeNumberfield('price', each.LGK__Price__c);
                    if (String.isNotEmpty(each.LGK__ExtendedInformation__c)) {
                        bomDataFieldJson.writeStringField('extended', each.LGK__ExtendedInformation__c);
                    }
                    else {
                        bomDataFieldJson.writeStringField('extended', '');
                    }
                    if (String.isNotEmpty(each.LGK__PricingInformation__c)) {
                        bomDataFieldJson.writeStringField('pricing', each.LGK__PricingInformation__c);
                    }
                    if (String.isNotEmpty(each.LGK__ParentProductId__c)) {
                        bomDataFieldJson.writeStringField('parentProduct', each.LGK__ParentProductId__c);
                        bomDataFieldJson.writeStringField('effectiveParent', each.LGK__ParentProductId__c);
                    }
                    if (String.isNotEmpty(each.LGK__UniqueId__c)) {
                        bomDataFieldJson.writeStringField('uniqueIdentifier', each.LGK__UniqueId__c);
                    }
                    // Product info (only UOM is in our custom object, the rest are from SF directly)
                    if ((each.LGK__ProductId__c instanceof Id) && configProductsMap.containsKey(each.LGK__ProductId__c)) {
                        Product2 productInfo = configProductsMap.get(each.LGK__ProductId__c);
                        bomDataFieldJson.writeStringField('name', productInfo.Name);
                        bomDataFieldJson.writeStringField('partnerId', productInfo.Id);
                        if (String.isNotBlank(productInfo.ProductCode)) {
                            bomDataFieldJson.writeStringField('productCode', productInfo.ProductCode);
                        }
                        else {
                            bomDataFieldJson.writeStringField('productCode', '');
                        }
                        if (String.isNotBlank(productInfo.ExternalId)) {
                            bomDataFieldJson.writeStringField('externalId', productInfo.ExternalId);
                        }
                        else {
                            bomDataFieldJson.writeStringField('externalId', '');
                        }
                        if (String.isNotBlank(productInfo.Family)) {
                            bomDataFieldJson.writeStringField('productFamily', productInfo.Family);
                        }
                        else {
                            bomDataFieldJson.writeStringField('productFamily', '');
                        }
                        if (String.isNotBlank(productInfo.Description)) {
                            bomDataFieldJson.writeStringField('description', productInfo.Description);
                        }
                        else {
                            bomDataFieldJson.writeStringField('description', '');
                        }
                        if (String.isNotBlank(each.LGK__UOM__c)) {
                            bomDataFieldJson.writeStringField('uom', each.LGK__UOM__c);
                        }
                        else {
                            bomDataFieldJson.writeStringField('uom', '');
                        }
                    }

                    bomDataFieldJson.writeNumberfield('extPrice', each.LGK__Price__c);
                    bomDataFieldJson.writeNumberfield('level', Integer.valueOf(each.LGK__Level__c));
                    bomDataFieldJson.writeNumberfield('rollUpPrice', each.LGK__RollupPrice__c);
                    bomDataFieldJson.writeEndObject();

                    // Add to total
                    bomTotal += each.LGK__Price__c;
                }   
            } catch (NullPointerException npe) {
                handleException(
                    npe.getStackTraceString() + ': ' + npe.getMessage(),
                    'NULL_POINTER_EXCEPTION',
                    quotingRequest
                );
            }
        }

        // Finish JSON with total
        bomDataFieldJson.writeEndArray();
        bomDataFieldJson.writeNumberfield('total', bomTotal);
        bomDataFieldJson.writeEndObject();

        return bomDataFieldJson;
    }

    /**
     * @description In case the Quote has grouping enabled but a Quote Line Group Id was not specified, create a new group.
     * @param isGrouped The value of SBQQ__LineItemsGrouped__c on the parent quote
     * @param quoteLineGroupId The group Id from the request, (or empty string, if it was not specified)
     * @param quoteId Quote to associate the new group with
     * @return Id of either the original Quote Line Group if one was in the request, otherwise the newly created group Id
     */
    public static String createQuoteLineGroup(Boolean isGrouped, String quoteLineGroupId, String quoteId) {
        if (isGrouped && String.isBlank(quoteLineGroupId)) {
            SBQQ__QuoteLineGroup__c quoteLineGroup = new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = quoteId);
            Database.insert(quoteLineGroup, true, AccessLevel.USER_MODE);
            quoteLineGroupId = quoteLineGroup.Id;
        }

        return quoteLineGroupId;
    }

    /**
     * @description Get Quote Data from QuoteReader and convert to map. Add custom quote fields from RFQ request, then add products
     * @param quoteId
     * @param requestQuoteFields
     * @param isGrouped
     * @param quoteLineGroupId
     * @param productsJsonArray
     * @return Map of variables we'll need later: quoteMap, nextKey, nextNumber
     */
    public static Map<String, Object> addProductsToQuote(
        String quoteId, Map<String, Object> requestQuoteFields,
        Boolean isGrouped, String quoteLineGroupId, JSONGenerator productsJsonArray
    ) {
        Map<String, Object> quoteMap = (Map<String, Object>)JSON.deserializeUntyped(
            SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId)
        );
        
        Map<String, Object> recordData = (Map<String, Object>)quoteMap.get('record');
        // Update record with fields from API request, if present
        if (requestQuoteFields != null) {
            recordData.putAll(requestQuoteFields);
        }
        quoteMap.put('record', recordData);

        // Get the next available line item key (derived from existing lines/groups on the quote already)
        Integer nextKey = Integer.valueOf(quoteMap.get('nextKey')),
        numberOfGroups = quoteMap.containsKey('lineItemGroups') ? ((Object[])quoteMap.get('lineItemGroups')).size() : 0,
        rootNumber = quoteMap.containsKey('lineItems') ? ((Object[])quoteMap.get('lineItems')).size() + 1 : 0;

        // Not sure why, but nextKey is shared with lines and line groups, so the expected value shifts with the number of line groups
        if (isGrouped) {
            nextKey = nextKey - numberOfGroups;
            rootNumber = [
                SELECT count() FROM SBQQ__QuoteLine__c
                WHERE SBQQ__Group__c = :quoteLineGroupId
                WITH USER_MODE
            ] + 1;
        }
        Integer nextNumber = rootNumber + 1;

        // Add products to quote
        quoteMap = (Map<String, Object>)JSON.deserializeUntyped(
            SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteProductAdder', null, '{"quote" : ' + JSON.serialize(quoteMap) + ', "products" : ' + productsJsonArray.getAsString() + ', "ignoreCalculate" : true}')
        );

        return new Map<String, Object>{
            'quoteMap' => quoteMap,
            'rootNumber' => rootNumber,
            'nextKey' => nextKey,
            'nextNumber' => nextNumber
        };
    }

    /**
     * @description Set fields on the Configurable Quote Line, such as configId, bomData, etc.
     * @param configurableQuoteLine Configurable quote line, as an untyped map
     * @param quoteLineFieldsMap Map of fields and values to set
     * @return The "record" value of the configurableQuoteLine, after updates
     */
    public static Map<String, Object> updateConfigurableQuoteLine(
        Map<String, Object> configurableQuoteLine,
        Map<String, Object> quoteLineFieldsMap
    ) {
        Map<String, Object> result = (Map<String, Object>)configurableQuoteLine.get('record');

        result.put('LGK__ConfigurationId__c', String.valueOf(quoteLineFieldsMap.get('configurationId')));
        result.put('LGK__BomData__c', String.valueOf(quoteLineFieldsMap.get('bomData')));
        result.put('SBQQ__Number__c', Integer.valueOf(quoteLineFieldsMap.get('rootNumber')));

        if (Boolean.valueOf(quoteLineFieldsMap.get('isGrouped'))) {
            result.put('SBQQ__Group__c', quoteLineFieldsMap.get('quoteLineGroupId'));
        }

        return result;
    }

    /**
     * @description Sets configurable quote line fields from the intiial RFQ request.
     * @param configurableQuoteLineDeserializedRecord Record to be updated
     * @param configurableQuoteLine Map of fields and values from the RFQ request
     */
    public static void updateConfigurableQuoteLineCustomFields(
        Map<String, Object> configurableQuoteLineDeserializedRecord,
        Map<String, Object> configurableQuoteLine
    ) {
        if (configurableQuoteLine != null) {
            for (String each : configurableQuoteLine.keySet()) {
			    configurableQuoteLineDeserializedRecord.put(each, configurableQuoteLine.get(each));
            }
        }
    }

    /**
     * @description Sets the reponse message and status code in the case that the webhook should not respond with success.
     * @param errorString Message to be included in the webhook reponse
     * @param errorCode A text value of the type of error being encountered, such as "DML_EXCEPTION", "QUERY_EXCEPTION", etc.
     */
    public static void handleException(String errorString, String errorCode, QuotingRequest__c quotingRequest) {
        returnStatusCode = 400;
        errorMessage = '{ "message": "' + errorString.replace('\n','. ') + '", "errorCode": "' + errorCode + '" }';
        if (quotingRequest != null) {
            quotingRequest.ErrorResponse__c = errorMessage;
            quotingRequest.Status__c = 'Failed';
            quotingRequest.CompletedDate__c = Datetime.now();
            Database.update(quotingRequest, true, AccessLevel.USER_MODE);
        }
        System.debug(LoggingLevel.ERROR, errorMessage);
    }

    /**
     * @date 2025
     * @description Queuable class to give users the option to have more CPU/memory from async apex transaction
     */
    public with sharing class RequestForQuoteV2Async implements Queueable {
        Map<String, Object> requestBody;
        String httpMethod,
            quoteId,
            configurableProductId,
            configurationId,
            quoteLineGroupId;

        /**
         * @description Constructor
         * @param requestBody JSON request, deserialized as an untyped map
         */
        public RequestForQuoteV2Async(String httpMethod, Map<String, Object> requestBody) {
            this.httpMethod = httpMethod;
            this.requestBody = requestBody;
            this.quoteId = String.valueOf(requestBody.get('quoteId'));
            this.configurationId = String.valueOf(requestBody.get('configurationId'));
        }

        /**
         * @description Runs RFQ in async context after all Config Lines are present, either using forceAsync, or from a Config Line Item trigger
         * @param context Used to call and return job Id
         */
        public void execute(QueueableContext context) {
            QuotingRequest__c[] currentRequest = [
                SELECT Id
                FROM QuotingRequest__c
                WHERE AsyncJobId__c = :context.getJobId()
                WITH USER_MODE
            ];
            if (!currentRequest.isEmpty() && !requestBody.containsKey('quotingRequestId')) {
                requestBody.put('quotingRequestId', currentRequest[0].Id);
            }
            
            RequestForQuoteV2Controller.processRequest(httpMethod, requestBody);
        }
    }
}