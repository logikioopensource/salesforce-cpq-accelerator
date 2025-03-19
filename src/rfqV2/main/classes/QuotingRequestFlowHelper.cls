global with sharing class QuotingRequestFlowHelper {
    global class FlowInput {
        @InvocableVariable(label='Quoting Request' required=true)
        global QuotingRequest__c pendingRequest;

        @InvocableVariable(label='Configuration Line Item List' required=true)
        global LGK__ConfigurationLineItem__c[] configurationLineItemList;
    }

    /**
     */
    @InvocableMethod(category='Logik.ai Open Source' label='Logik.ai RFQ Helper' description='Attempts to resume RFQ for the QuotingRequest records passed in.')
    global static void resumeRFQ(FlowInput[] flowInputList) {
        Set<String> processedRequestSet = new Set<String>{};    // Mostly needed if running asynchronously
        for (FlowInput each : flowInputList) {
            each.pendingRequest = [
                SELECT Status__c, RequestPayload__c, RunAsynchronousApex__c 
                FROM QuotingRequest__c
                WHERE Id = :each.pendingRequest.Id
                WITH USER_MODE LIMIT 1
            ];
            if (
                (
                    each.pendingRequest.Status__c.equalsIgnoreCase('Pending') ||
                    each.pendingRequest.Status__c.equalsIgnoreCase('Queued')
                ) &&
                !processedRequestSet.contains(each.pendingRequest.Id)
            ) {
                Map<String, Object> requestBody = (Map<String, Object>)JSON.deserializeUntyped(
                    each.pendingRequest.RequestPayload__c   
                );
                String methodType = requestBody.containsKey('quoteId') ? 'PATCH' : 'POST';
                requestBody.put('quotingRequestId', each.pendingRequest.Id);
                if (
                    requestBody.containsKey('forceAsync') &&
                    (Boolean.valueOf(requestBody.get('forceAsync')) ||
                    each.pendingRequest.RunAsynchronousApex__c)
                ) {
                    requestBody.remove('forceAsync');
                    processedRequestSet.add(each.pendingRequest.Id);
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(new RequestForQuoteV2Controller.RequestForQuoteV2Async(methodType, requestBody));
                    }
                    else {
                        RequestForQuoteV2Controller.processRequest(methodType, requestBody);
                    }
                }
                else {
                    processedRequestSet.add(each.pendingRequest.Id);
                    RequestForQuoteV2Controller.processRequest(methodType, requestBody);
                }
            }
        }
    }
}