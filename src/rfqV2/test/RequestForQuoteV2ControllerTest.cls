@isTest private class RequestForQuoteV2ControllerTest { 
    final static Id STANDARD_PRICE_BOOK_ID = Test.getStandardPricebookId();

    @testSetup
    static void setupData() {
        insert new Account(Name='Test Account');
        insert new Opportunity(Name='Test Opportunity', StageName='Prospecting', CloseDate=Date.today());

        Product2[] productsList = new Product2[]{
            new Product2(Name='ConfigurableProduct', LGK__IsConfigurable__c=true, SBQQ__ExternallyConfigurable__c=false)
        };
        Integer count = 20;
        for (Integer i = 1; i < 20; i++) {
            productsList.add(new Product2(Name='ChildProduct' + i));
        }
        insert productsList;

        LGK__ConfigurationLineItem__c[] configLineItemsList = new LGK__ConfigurationLineItem__c[]{};
        for (Product2 each : productsList) {
            // Skip Configurable Product
            if(each.Name != 'ConfigurableProduct') {
                Decimal randomPrice = Decimal.valueOf(Math.random() * 100).setScale(2);
                Decimal randomQuantity = Decimal.valueOf(1 + (Math.random() * 10)).setScale(1);

                LGK__ConfigurationLineItem__c tmpConfigLine = new LGK__ConfigurationLineItem__c(
                    LGK__ProductId__c=each.Id,
                    LGK__UniqueId__c=each.Name,
                    LGK__ConfigurationId__c='a12345',
                    LGK__Price__c=randomPrice,
                    LGK__Quantity__c=randomQuantity,
                    LGK__ParentProductId__c='',
                    LGK__Level__c='0',
                    LGK__Type__c='Sales',
                    LGK__RollupPrice__c=randomPrice, 
                    LGK__UOM__c=''
                );

                // Add parent reference for child line
                if (each.Name.contains('19')) {
                    tmpConfigLine.LGK__ParentProductId__c = configLineItemsList[10].LGK__UniqueId__c;
                }

                configLineItemsList.add(tmpConfigLine);
            }
        }

        // Add parent reference for child line that will be processed before the parent
        configLineItemsList[5].LGK__ParentProductId__c = configLineItemsList[10].LGK__UniqueId__c;
        insert configLineItemsList;
    }

    /*--------------- HTTP Method Tests -----------------*/
    @isTest
    static void testCreateQuoteApi(){
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"configurableProductId":"' + configurableProductId + '","configurationId":"a12345","accountId":"","pricebookId":"' + STANDARD_PRICE_BOOK_ID + '"}');

        RequestForQuoteV2Controller.createQuote();

        System.assertEquals(200, RestContext.response.statusCode,
            'RFQ POST did not respond with status code 200.');
        System.assertEquals('application/json', RestContext.response.headers.get('Content-Type'),
            'RFQ POST did not respond with Content-Type "application/json".'
        );
        Test.stopTest();
    }

    @isTest
    static void testAddToQuoteApi() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        insert quote;
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"quoteId":"' + quote.Id + '", "configurableProductId":"' + configurableProductId + '","configurationId":"a12345"}');
        
        RequestForQuoteV2Controller.addToQuote();

        System.assertEquals(200, RestContext.response.statusCode,
            'RFQ PATCH did not respond with status code 200.');
        System.assertEquals('application/json', RestContext.response.headers.get('Content-Type'),
            'RFQ PATCH did not respond with Content-Type "application/json".');
        Test.stopTest();
    }

    @isTest
    static void testAddToQuoteApiError() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestURI = '/request-quote/';
        RestContext.request.requestBody = Blob.valueOf('{"quoteId":"", "configurableProductId":"' + configurableProductId + '","configurationId":"a12345"}');
        
        RequestForQuoteV2Controller.addToQuote();

        System.assertEquals(400, RestContext.response.statusCode,
            'Failed RFQ PATCH did not respond with status code 400.');
        System.assertEquals('application/json', RestContext.response.headers.get('Content-Type'),
            'Failed RFQ PATCH did not respond with Content-Type "application/json".');
        System.assertEquals(
            '{ "message": "One or more required fields are missing: quoteId, configurableProductId, configurationId", "errorCode": "MISSING_FIELD(S)" }',
            RestContext.response.responseBody.toString(),
            'Failed RFQ PATCH did not respond with an error message including missing fields.'
        );
        Test.stopTest();
    }

    @isTest
    static void testAddQuoteWithoutLineGroupIdField() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__LineItemsGrouped__c = true
        );
        insert quote;
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"quoteId":"' + quote.Id + '", "configurableProductId":"' + configurableProductId + '","configurationId":"a12345"}');

        RequestForQuoteV2Controller.addToQuote();

        System.assertEquals(200, RestContext.response.statusCode,
            'RFQ PATCH on a grouped quote did not respond with status code 200.');
        System.assertEquals('application/json', RestContext.response.headers.get('Content-Type'),
            'RFQ PATCH on a grouped quote did not respond with Content-Type "application/json".');
        Test.stopTest();
    }

    @isTest
    static void testCreateQuoteApiAsyncResponse() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"configurableProductId":"' + configurableProductId + '","configurationId":"a54321","accountId":"","pricebookId":"","forceAsync":true}');

        RequestForQuoteV2Controller.createQuote();
        assertAsyncResponse(RestContext.response);
        Test.stopTest();
    }

    @isTest
    static void testAddToQuoteApiAsyncResponse() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        insert quote;
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"quoteId":"' + quote.Id + '", "configurableProductId":"' + configurableProductId + '","configurationId":"a54321","forceAsync":true}');
        
        RequestForQuoteV2Controller.addToQuote();
        assertAsyncResponse(RestContext.response);
        Test.stopTest();
    }

    /*--------------- Non-HTTP Method Tests -----------------*/
    @isTest
    static void testCreateQuoteMethodWithOnlyLineItems() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        Map<String, Object> requestBody = new Map<String, Object>{
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'pricebookId' => STANDARD_PRICE_BOOK_ID
        };
        Map<String, Object> recordMap = (Map<String, Object>)(
            (Map<String, Object>)JSON.deserializeUntyped(
                RequestForQuoteV2Controller.processRequest('POST', requestBody)
            )
        ).get('record');
        String quoteId = String.valueOf(recordMap.get('Id'));

        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quoteId, expectedValuesMap, false),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        Test.stopTest();
    }

    @isTest
    static void testCreateQuoteMethodWithAllParameters() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id,
        testAccountId = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ].Id,
        testOpportunityId = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Opportunity'
            LIMIT 1
        ].Id;

        Map<String, Object> requestBody = new Map<String, Object>{
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'pricebookId' => STANDARD_PRICE_BOOK_ID,
            'accountId' => testAccountId,
            'opportunityId' => testOpportunityId,
            'forceAsync' => false,
            'minimumLineCount' => 10
        };
        Map<String, Object> recordMap = (Map<String, Object>)(
            (Map<String, Object>)JSON.deserializeUntyped(
                RequestForQuoteV2Controller.processRequest('POST', requestBody)
            )
        ).get('record');
        String quoteId = String.valueOf(recordMap.get('Id'));
        
        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'expectedAccountId' => testAccountId,
            'expectedOpportunityId' => testOpportunityId,
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quoteId, expectedValuesMap, false),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        Test.stopTest();
    }

    @isTest
    static void testCreateQuoteFieldPassThrough() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id,
        testOpportunityId = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Opportunity'
            LIMIT 1
        ].Id;

        Map<String, Object> quoteData = new Map<String, Object>{
            'SBQQ__Primary__c' => true,
            'SBQQ__Status__c' => 'Denied',
            'SBQQ__Opportunity2__c' => testOpportunityId
        };
        Map<String, Object> configurableQuoteLine = new Map<String, Object>{
            'SBQQ__Taxable__c' => true,
            'SBQQ__StartDate__c' => Date.today()
        };
        Map<String, Object> requestBody = new Map<String, Object>{
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'quote' => quoteData,
            'configurableQuoteLine' => configurableQuoteLine,
            'pricebookId' => STANDARD_PRICE_BOOK_ID
        };
		Map<String, Object> recordMap = (Map<String, Object>)(
            (Map<String, Object>)JSON.deserializeUntyped(
                RequestForQuoteV2Controller.processRequest('POST', requestBody)
            )
        ).get('record');
        String quoteId = String.valueOf(recordMap.get('Id'));
        
        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'expectedOpportunityId' => testOpportunityId,
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quoteId, expectedValuesMap, false),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        SBQQ__Quote__c quote = [
            SELECT SBQQ__Primary__c, SBQQ__Status__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];
        System.assert(quote.SBQQ__Primary__c,
            'Quote did not set the value for "SBQQ__Primary__c" to match the value in the request.');
        System.assertEquals('Denied', quote.SBQQ__Status__c,
            'Quote did not set the value for "SBQQ__Status__c" to match the value in the request.');
        SBQQ__QuoteLine__c rootQuoteLine = [SELECT SBQQ__Taxable__c, SBQQ__StartDate__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Product__c = :configurableProductId LIMIT 1];
        System.assert(rootQuoteLine.SBQQ__Taxable__c,
            'Quote Line did not set the value for "SBQQ__Taxable__c" to match the value in the request.');
        System.assertEquals(Date.today(), rootQuoteLine.SBQQ__StartDate__c,
            'Quote Line did not set the value for "SBQQ__StartDate__c" to match the value in the request.');
        Test.stopTest();
    }

    @isTest
    static void testAddToQuoteMethod() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__PricebookId__c = STANDARD_PRICE_BOOK_ID
        );
        insert quote;

        Map<String, Object> requestBody = new Map<String, Object>{
            'quoteId' => quote.Id,
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345'
        };
        RequestForQuoteV2Controller.processRequest('PATCH', requestBody);
        
        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quote.Id, expectedValuesMap, false),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        Test.stopTest();
    }

    @isTest
    static void testFieldValuesAndDuplicates() {
        Test.startTest();
        Product2[] productsList = [
            SELECT Id, Name
            FROM Product2
            ORDER BY Id ASC
        ];
        Product2 duplicateProduct = productsList[5];
        LGK__ConfigurationLineItem__c duplicateConfigLine = new LGK__ConfigurationLineItem__c(
            LGK__ProductId__c = duplicateProduct.Id,
            LGK__UniqueId__c = duplicateProduct.Name + '-1',
            LGK__ConfigurationId__c = 'a12345',
            LGK__Price__c = 55.55,
            LGK__Quantity__c = 5,
            LGK__ParentProductId__c = '',
            LGK__Level__c = '0',
            LGK__Type__c = 'Sales',
            LGK__RollupPrice__c = 55.55,
            LGK__UOM__c = ''
        );
        insert duplicateConfigLine;

        // Need to convert to use maps since quote lines aren't created in the order they're sent in the request
        Map<String, LGK__ConfigurationLineItem__c> configLineItemsMap = new Map<String, LGK__ConfigurationLineItem__c>{};
        LGK__ConfigurationLineItem__c[] configLineItemsList = [
            SELECT Id, LGK__ProductId__c, LGK__UniqueId__c, LGK__ConfigurationId__c, LGK__Price__c, LGK__Quantity__c,
                LGK__ParentProductId__c, LGK__Level__c, LGK__Type__c, LGK__RollupPrice__c, LGK__UOM__c
            FROM LGK__ConfigurationLineItem__c
        ];
        for (LGK__ConfigurationLineItem__c each : configLineItemsList) {
            configLineItemsMap.put(each.LGK__UniqueId__c, each);
        }
        configLineItemsMap.put(duplicateConfigLine.LGK__UniqueId__c, duplicateConfigLine);
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__PricebookId__c = STANDARD_PRICE_BOOK_ID
        );
        insert quote;
        Map<String, Object> requestBody = new Map<String, Object>{
            'quoteId' => quote.Id,
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'pricebookId' => STANDARD_PRICE_BOOK_ID
        };
        
        RequestForQuoteV2Controller.processRequest('PATCH', requestBody);
        
        Map<String, SBQQ__QuoteLine__c> quoteLinesMap = new Map<String, SBQQ__QuoteLine__c>{};
        for (SBQQ__QuoteLine__c each : [
            SELECT SBQQ__Product__c, SBQQ__Quantity__c, SBQQ__ListPrice__c, LGK__UniqueId__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quote.Id
            AND LGK__ConfigurationId__c = ''    // Skip the configurable product
        ]) {
            quoteLinesMap.put(each.LGK__UniqueId__c, each);
        }

        for (String each : quoteLinesMap.keySet()) {
            System.assertEquals(configLineItemsMap.get(each).LGK__ProductId__c, quoteLinesMap.get(each).SBQQ__Product__c,
                'Quote Line and Config Line did not have matching Product Id values.');
            System.assertEquals(configLineItemsMap.get(each).LGK__Quantity__c, quoteLinesMap.get(each).SBQQ__Quantity__c,
                'Quote Line and Config Line did not have matching Quantity values.');
            System.assertEquals(configLineItemsMap.get(each).LGK__Price__c, quoteLinesMap.get(each).SBQQ__ListPrice__c,
                'Quote Line and Config Line did not have matching Price values.');
        }
        Test.stopTest();
    }

    @isTest
    static void testAddToGroupedQuoteMethodWithoutGroupId() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__PricebookId__c = STANDARD_PRICE_BOOK_ID,
            SBQQ__LineItemsGrouped__c = true
        );
        insert quote;
        Map<String, Object> requestBody = new Map<String, Object>{
            'quoteId' => quote.Id,
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'pricebookId' => STANDARD_PRICE_BOOK_ID
        };
        
        RequestForQuoteV2Controller.processRequest('PATCH', requestBody);
        
        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quote.Id, expectedValuesMap, true),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        Test.stopTest();
    }

    @isTest
    static void testAddToGroupedQuoteMethodWithGroupId() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__PricebookId__c = STANDARD_PRICE_BOOK_ID,
            SBQQ__LineItemsGrouped__c = true
        );
        insert quote;
        SBQQ__QuoteLineGroup__c lineGroup = new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = quote.Id);
        insert lineGroup;
        Map<String, Object> requestBody = new Map<String, Object>{
            'quoteId' => quote.Id,
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'quoteLineGroupId' => lineGroup.Id,
            'pricebookId' => STANDARD_PRICE_BOOK_ID
        };

        RequestForQuoteV2Controller.processRequest('PATCH', requestBody);
        
        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quote.Id, expectedValuesMap, true),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        Test.stopTest();
    }

    @isTest
    static void testAddToGroupedQuoteWithExistingLines() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__PricebookId__c = STANDARD_PRICE_BOOK_ID,
            SBQQ__LineItemsGrouped__c = true
        );
        insert quote;
        SBQQ__QuoteLineGroup__c lineGroup = new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = quote.Id);
        insert lineGroup;
        Map<String, Object> requestBody = new Map<String, Object>{
            'quoteId' => quote.Id,
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'quoteLineGroupId' => lineGroup.Id,
            'pricebookId' => STANDARD_PRICE_BOOK_ID
        };
        
        RequestForQuoteV2Controller.processRequest('PATCH', requestBody);
        
        Map<String, Object> expectedValuesMap = new Map<String, Object>{
            'numberOfLines' => 20
        };
        System.assert(assertQuoteData(quote.Id, expectedValuesMap, true),
            'Not all assertions in assertQuoteData() evaluated correctly.');

        requestBody.remove('quoteLineGroupId');
        RequestForQuoteV2Controller.processRequest('PATCH', requestBody);
        
        expectedValuesMap.put('numberOfLines', 40);
        System.assert(assertQuoteData(quote.Id, expectedValuesMap, true),
            'Not all assertions in assertQuoteData() evaluated correctly.');
        Test.stopTest();
    }
    
    @isTest
    static void testAddToQuoteMethodExceptions() {
        Test.startTest();
        Boolean exceptionOccurred = false;
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;

        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        insert quote;
        Map<String, Object> requestBody = new Map<String, Object>{
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345'
        };

        // Missing quoteId
        try {
            quote = (SBQQ__Quote__c)JSON.deserialize(RequestForQuoteV2Controller.processRequest('PATCH', requestBody), SObject.class);
        } catch (Exception e) {
            exceptionOccurred = true;
        }

        System.assert(exceptionOccurred,
            'Exception was not thrown for a missing Quote Id.');
        exceptionOccurred = false;
        
        // Missing product/configuration
        try {
            requestBody.put('quoteId', quote.Id);
            requestBody.remove('configurableProductId');
            requestBody.remove('configurationId');
            quote = (SBQQ__Quote__c)JSON.deserialize(RequestForQuoteV2Controller.processRequest('PATCH', requestBody), SObject.class);
        } catch (Exception e) {
            exceptionOccurred = true;
        }

        System.assert(exceptionOccurred,
            'Exception was not thrown for missing Configuration and Product Ids.');
        Test.stopTest();
    }

    @isTest
    static void testForceAsync() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;
        Map<String, Object> requestBody = new Map<String, Object>{
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'forceAsync' => true
        };

        Map<String, Object> responseBodyMap = (Map<String, Object>)JSON.deserializeUntyped(
            RequestForQuoteV2Controller.processRequest('POST', requestBody)
        );
        assertAsyncResponse(responseBodyMap);
        Test.stopTest();
    }

    @isTest
    static void testQuotingRequest() {
        Test.startTest();
        String configurableProductId = [
            SELECT Id
            FROM Product2
            WHERE LGK__IsConfigurable__c = true
            LIMIT 1
        ].Id;
        Map<String, Object> requestBody = new Map<String, Object>{
            'configurableProductId' => configurableProductId,
            'configurationId' => 'a12345',
            'minimumLineCount' => 21
        };

        Map<String, Object> responseBodyMap = (Map<String, Object>)JSON.deserializeUntyped(
            RequestForQuoteV2Controller.processRequest('POST', requestBody)
        );
        assertAsyncResponse(responseBodyMap);
        Test.stopTest();
    }

    /**
     * @description Asserts quote data matches expected results from request.
     * If the Standard Price Book is not Active, the assertion for PRice Book comparison will fail
     * @param quoteId The quote data from the RFQ response
     * @param expectedValuesMap Map of expected values for: Account Id, Opportunity Id, Number of quote lines
     * @param isGrouped Whether the quote is expected to have quote line groups enabled
     * @return true if all assertions passed (otherwise, an exception is thrown on the failed assertion)
     */
    static Boolean assertQuoteData(String quoteId, Map<String, Object> expectedValuesMap, Boolean isGrouped) {
        SBQQ__Quote__c quote = [
            SELECT Id, SBQQ__PricebookId__c, SBQQ__Account__c, SBQQ__Opportunity2__c, SBQQ__LineItemsGrouped__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];
        SBQQ__QuoteLine__c[] quoteLinesList = [
            SELECT Id, SBQQ__Product__c, LGK__ConfigurationId__c, LGK__BomData__c, SBQQ__Group__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quote.Id
        ];

        System.assertEquals(STANDARD_PRICE_BOOK_ID, quote.SBQQ__PricebookId__c,
            'Price Book for the Quote did not match the Id sent in the request.');
        System.assertEquals(expectedValuesMap.get('expectedAccountId'), quote.SBQQ__Account__c,
            'Account for the Quote did not match the Id sent in the request.');
        System.assertEquals(expectedValuesMap.get('expectedOpportunityId'), quote.SBQQ__Opportunity2__c,
            'Opportunity for the Quote did not match the Id sent in the request.');
        Integer numberOfLines = Integer.valueOf(expectedValuesMap.get('numberOfLines'));
        if (numberOfLines > 0) {
            System.assertEquals('a12345', quoteLinesList[0].LGK__ConfigurationId__c,
                'Configurable Quote Line did not have the expected Configuration Id.');
            System.assert(String.isNotEmpty(quoteLinesList[0].LGK__BomData__c),
                'Configurable Quote Line did not have Bom Data populated.');
            System.assertEquals(expectedValuesMap.get('numberOfLines'), quoteLinesList.size(),
                'Quote did not have the expected number of Quote Lines.');
        }
        else {
            System.assertEquals(0, quoteLinesList.size(),
                'Quote Lines were incorrectly created.');
        }
        if (isGrouped) {
            System.assertEquals(true, quote.SBQQ__LineItemsGrouped__c,
                'Quote did not have line grouping enabled.');
            for (SBQQ__QuoteLine__c each : quoteLinesList) {
                System.assert(String.isNotEmpty(each.SBQQ__Group__c),
                    'Quote Line on a grouped Quote did not have a group assigned to it.');
            }
        }
        else {
            for (SBQQ__QuoteLine__c each : quoteLinesList) {
                System.assert(String.isEmpty(each.SBQQ__Group__c),
                    'Quote Line on a non-grouped Quote had a group assigned to it.');
            }
        }

        return true;
    }

    /**
     * @description Asserts format of a request with an async response, which is not in the format of a SBQQ__Quote__c object.
     * @param responseMap Map of the JSON response
     * @return true if all assertions passed (otherwise, an exception is thrown on the failed assertion)
     */
    static Boolean assertAsyncResponse(System.RestResponse response) {
        Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(response.responseBody.toString());

        System.assertEquals(202, response.statusCode,
            'RFQ POST running asynchronously did not respond with status 202.');
        System.assertEquals('application/json', response.headers.get('Content-Type'),
            'RFQ POST running asynchronously did not respond with Content-Type "application/json".');
        System.assertEquals('Pending', responseMap.get('status'),
            'Async response did not include the correct "status".');
        System.assertEquals('Request is pending.', responseMap.get('message'),
            'Async response did not include the correct "message".');
        System.assert(responseMap.containsKey('quotingRequest'),
            'Async response did not include pending request record.');

        return true;
    }

    static Boolean assertAsyncResponse(Map<String, Object> responseBodyMap) {
        System.assertEquals('Pending', responseBodyMap.get('status'),
            'Async response did not include the correct "status".');
        System.assertEquals('Request is pending.', responseBodyMap.get('message'),
            'Async response did not include the correct "message".');
        System.assert(responseBodyMap.containsKey('quotingRequest'),
            'Async response did not include pending request record.');
        
        String quotingRequestId = String.valueOf(
            ((Map<String, Object>)responseBodyMap.get('quotingRequest')).get('Id')
        );
        System.assert(quotingRequestId instanceof Id,
            'quotingRequestId did not correspond to an Id value.');
        System.assertEquals(QuotingRequest__c.SObjectType, Id.valueOf(quotingRequestId).getSObjectType(),
            'quotingRequestId did not correspond to a QuotingRequest record.');

        return true;
    }
}