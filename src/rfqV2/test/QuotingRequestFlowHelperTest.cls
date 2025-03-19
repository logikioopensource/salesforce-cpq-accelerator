@isTest private class QuotingRequestFlowHelperTest {
    @testSetup
    static void setupData() {
        Product2[] productsList = new Product2[]{
            new Product2(Name='ConfigurableProduct', LGK__IsConfigurable__c=true, SBQQ__ExternallyConfigurable__c=false)
        };
        LGK__ConfigurationLineItem__c[] configLineItemsList = new LGK__ConfigurationLineItem__c[]{};
        PricebookEntry[] pbeList = new PricebookEntry[]{};
        
        for (Integer i = 1; i < 20; i++) {
            productsList.add(new Product2(Name='ChildProduct' + i));
        }
        insert productsList;
        
        for (Product2 each : productsList) {
            pbeList.add(
                new PricebookEntry(
                    Product2Id = each.Id,
                    Pricebook2Id = Test.getStandardPricebookId(),
                    UnitPrice = 1
                )
            );

            // Skip Configurable Product
            if(each.Name != 'ConfigurableProduct') {
                LGK__ConfigurationLineItem__c tmpConfigLine = new LGK__ConfigurationLineItem__c(
                    LGK__ProductId__c = each.Id,
                    LGK__UniqueId__c = each.Name,
                    LGK__ConfigurationId__c = 'a12345',
                    LGK__Price__c = 1,
                    LGK__Quantity__c = 1,
                    LGK__ParentProductId__c = '',
                    LGK__Level__c = '0',
                    LGK__Type__c = 'Sales',
                    LGK__RollupPrice__c = 1, 
                    LGK__UOM__c = ''
                );

                configLineItemsList.add(tmpConfigLine);
            }
        }

        insert configLineItemsList;
        insert pbeList;
    }

    @isTest
    static void testResumeRFQ() {
        // Getting trigger to run to make product Logik.ai configurable
        Test.startTest();
        Product2[] productsList = [
            SELECT Id
            FROM Product2
        ];
        LGK__ConfigurationLineItem__c[] configLineItemsList = [
            SELECT Id, LGK__ProductId__c, LGK__UniqueId__c, LGK__ConfigurationId__c, LGK__Price__c, LGK__Quantity__c,
                LGK__ParentProductId__c, LGK__Level__c, LGK__Type__c, LGK__RollupPrice__c, LGK__UOM__c
            FROM LGK__ConfigurationLineItem__c
        ];
        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        insert quote;
        Map<String,Object> requestBody = new Map<String,Object>{
            'configurableProductId' => productsList[0].Id,
            'configurationId' => 'a12345',
            'quoteId' => quote.Id
        };

        QuotingRequest__c pendingRequest = new QuotingRequest__c(
            RequestPayload__c = JSON.serialize(requestBody),
            Status__c = 'Pending'
        );
        insert pendingRequest;

        QuotingRequestFlowHelper.FlowInput[] flowInputList = new QuotingRequestFlowHelper.FlowInput[]{
            new QuotingRequestFlowHelper.FlowInput()
        };
        flowInputList[0].pendingRequest = pendingRequest;
        flowInputList[0].configurationLineItemList = configLineItemsList;
        QuotingRequestFlowHelper.resumeRFQ(flowInputList);

        SBQQ__QuoteLine__c[] quoteLinesList = [
            SELECT Id, LGK__ConfigurationId__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quote.Id
            ORDER BY Id ASC
        ];
        System.assertEquals(
            productsList.size(), quoteLinesList.size(),
            'Expected number of quote lines were not added to the quote'
        );
        System.assertEquals(
            'a12345', quoteLinesList[0].LGK__ConfigurationId__c,
            'Configurable quote line did not have the expected Configuration Id'
        );
        Test.stopTest();
    }

    @isTest
    static void testResumeAsync() {
        Test.startTest();
        Product2[] productsList = [
            SELECT Id
            FROM Product2
        ];
        LGK__ConfigurationLineItem__c[] configLineItemsList = [
            SELECT Id, LGK__ProductId__c, LGK__UniqueId__c, LGK__ConfigurationId__c, LGK__Price__c, LGK__Quantity__c,
                LGK__ParentProductId__c, LGK__Level__c, LGK__Type__c, LGK__RollupPrice__c, LGK__UOM__c
            FROM LGK__ConfigurationLineItem__c
        ];
        Map<String,Object> requestBody = new Map<String,Object>{
            'configurableProductId' => productsList[0].Id,
            'configurationId' => 'a12345',
            'pricebookId' => Test.getStandardPricebookId(),
            'forceAsync' => true
        };
        QuotingRequest__c quotingRequest = new QuotingRequest__c(
            RequestPayload__c = JSON.serialize(requestBody),
            Status__c = 'Pending',
            RunAsynchronousApex__c = true
        );
        insert quotingRequest;
        requestBody.put('quotingRequestId', quotingRequest.Id);

        QuotingRequestFlowHelper.FlowInput[] flowInputList = new QuotingRequestFlowHelper.FlowInput[]{
            new QuotingRequestFlowHelper.FlowInput()
        };
        flowInputList[0].pendingRequest = quotingRequest;
        flowInputList[0].configurationLineItemList = configLineItemsList;
        QuotingRequestFlowHelper.resumeRFQ(flowInputList);
        
        quotingRequest = [
            SELECT QuoteId__c
            FROM QuotingRequest__c
            WHERE Id = :quotingRequest.Id
            LIMIT 1
        ];
        System.assert(
            quotingRequest.QuoteId__c != null,
            'Quoting Request was not updated with a Quote Id'
        );
        SBQQ__QuoteLine__c[] quoteLinesList = [
            SELECT Id, LGK__ConfigurationId__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quotingRequest.QuoteId__c
            ORDER BY Id ASC
        ];

        System.assertEquals(
            productsList.size(), quoteLinesList.size(),
            'Expected number of quote lines were not added to the quote'
        );
        System.assertEquals(
            'a12345', quoteLinesList[0].LGK__ConfigurationId__c,
            'Configurable quote line did not have the expected Configuration Id'
        );
        Test.stopTest();
    }
}