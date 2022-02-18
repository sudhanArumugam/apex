public with sharing class MaintenanceRequestHelper {

    public static void handleAfterUpdate(List<Case> newCases) {
        List<Case> closedCases = new List<Case>();
        for(Case caseObj : newCases) {
            if(caseObj.Status == 'Closed' && (caseObj.Type == 'Repair' || caseObj.Type == 'Routine Maintenance')) {
                closedCases.add(caseObj);
            }
            
        }

        if(closedCases.size() > 0) {
            MaintenanceRequestHelper.updateWorkOrder(closedCases);
        }
    }

    public static void updateWorkOrder(List<Case> caseList) {
        List<Case> caseListToInsert = new List<Case>();
        List<Equipment_Maintenance_Item__c> itemListToInsert = new List<Equipment_Maintenance_Item__c>();
        Map<Id, Integer> dueDateMap = MaintenanceRequestHelper.getDueDates(caseList);
        Map<Id, List<Equipment_Maintenance_Item__c>> maintenanceItemMap = MaintenanceRequestHelper.getMaintenanceItems(caseList);

        for(Case caseObj : caseList) {
            Case newCase = new Case();
            newCase.Vehicle__c = caseObj.Vehicle__c;
            newCase.Subject = 'Routine Maintenance';
            newCase.Type = 'Routine Maintenance';
            newCase.Date_Reported__c = Date.today();
            newCase.ParentId = caseObj.Id;
            
            newCase.Date_Due__c = Date.today();
            if(dueDateMap.get(caseObj.Id) != null) {
                newCase.Date_Due__c = newCase.Date_Due__c.addDays(dueDateMap.get(caseObj.Id));
            }

            caseListToInsert.add(newCase);
        }

        if(caseListToInsert.size() > 0) {
            insert caseListToInsert;

            for(Case insertedCase : caseListToInsert) {
                List<Equipment_Maintenance_Item__c> itemList = maintenanceItemMap.get(insertedCase.ParentId);
                if(itemList != null && itemList.size() > 0) {
                    for(Equipment_Maintenance_Item__c itemObj : itemList) {
                        Equipment_Maintenance_Item__c newItem = new Equipment_Maintenance_Item__c();
                        newItem.Maintenance_Request__c = insertedCase.Id;
                        newItem.Equipment__c = itemObj.Equipment__c;
                        newItem.Quantity__c = itemObj.Quantity__c;

                        itemListToInsert.add(newItem);
                    }
                }
            }

            if(itemListToInsert.size() > 0) {
                insert itemListToInsert;
            }
        }
    }

    private static Map<Id, Integer> getDueDates(List<Case> caseList) {
        Map<Id, Integer> results = new Map<Id, Integer>();
        Map<Id, Case> caseMap = new Map<Id, Case>(CaseList);
        
        List<AggregateResult> aggResults = [
            SELECT 
                Maintenance_Request__c cId, // Case Id
                MIN(Equipment__r.Maintenance_Cycle__c) cycle
            FROM Equipment_Maintenance_Item__c
            WHERE
                Maintenance_Request__c IN :caseMap.keySet() 
                AND Equipment__r.Maintenance_Cycle__c != null
            GROUP BY Maintenance_Request__c
        ];

        for(AggregateResult res : aggResults) {
            results.put(String.valueOf(res.get('cId')), Integer.valueOf(res.get('cycle')));
        }

        return results;
    }

    private static Map<Id, List<Equipment_Maintenance_Item__c>> getMaintenanceItems(List<Case> caseList) {
        Map<Id, List<Equipment_Maintenance_Item__c>> results = new Map<Id, List<Equipment_Maintenance_Item__c>>();
        Map<Id, Case> caseMap = new Map<Id, Case>(caseList);
        
        List<Equipment_Maintenance_Item__c> itemList = [
            SELECT 
                Id,
                Maintenance_Request__c,
                Equipment__c,
                Quantity__c
            FROM Equipment_Maintenance_Item__c
            WHERE Maintenance_Request__c IN :caseMap.keySet()
        ];

        for(Equipment_Maintenance_Item__c item : itemList) {

            List<Equipment_Maintenance_Item__c> requestItemList = results.get(item.Maintenance_Request__c);
            if(requestItemList == null) {
                requestItemList = new List<Equipment_Maintenance_Item__c>();
                results.put(item.Maintenance_Request__c, requestItemList);
            }
            requestItemList.add(item);
        }

        return results;
    }

}
_____________________________
@isTest
public with sharing class MaintenanceRequestHelperTest {

    @TestSetup 
    static void makeData() {
        List<Product2> equipList = new List<Product2>();
        List<Case> testCaseList = new List<Case>();
        List<Equipment_Maintenance_Item__c> itemsList = new List<Equipment_Maintenance_Item__c>();
        Vehicle__c veh = new Vehicle__c();
        veh.Name = 'Debin RV';
        veh.Awning__c = 'Manual';
        veh.Bathrooms__c = 2.0;
        veh.Bedrooms__c = 2.0;
        insert veh;

        Product2 equipment1 = new Product2();
        Product2 equipment2 = new Product2();
        equipment1.Name = 'Rotor W1000';
        equipment1.ProductCode = 'RW1001';
        equipment1.Warehouse_SKU__c = 'SK1001';
        equipment1.Maintenance_Cycle__c = 10.0;
        equipment1.Replacement_Part__c = true;
        equipment2.Name = 'Motor W1000';
        equipment2.ProductCode = 'MW1001';
        equipment2.Warehouse_SKU__c = 'SK1002';
        equipment2.Maintenance_Cycle__c = 10.0;
        equipment2.Replacement_Part__c = true;
        equipList.add(equipment1);
        equipList.add(equipment2);
        insert equipList;

        for (Integer i = 0; i < 300; i++) {
            Case testCase = new Case();
            testCase.Subject = 'Test Case '+i;
            testCase.Vehicle__c = veh.Id;
            testCase.Status = 'New';
            testCase.Priority = 'Medium';
            testCase.Origin = 'Phone';
            testCase.Type = 'Repair';
            testCaseList.add(testCase);
        }
        insert testCaseList;

        for (Case caseRec : testCaseList) {
            Equipment_Maintenance_Item__c item1 = new Equipment_Maintenance_Item__c();
            Equipment_Maintenance_Item__c item2 = new Equipment_Maintenance_Item__c();
            item1.Maintenance_Request__c = caseRec.Id;
            item1.Equipment__c = equipList[0].Id;
            item1.Quantity__c = 2;
            item2.Maintenance_Request__c = caseRec.Id;
            item2.Equipment__c = equipList[1].Id;
            item2.Quantity__c = 2;
            itemsList.add(item1);
            itemsList.add(item2);
        }
        insert itemsList;
    }

    @IsTest
    static void positiveTest1(){
        Case testCase = [Select ID, Status from Case limit 1];
        testCase.Status = 'Closed';
        Test.startTest();
        update testCase;
        Test.stopTest();
        
        Case newFollowUpCase = [SELECT ID, ParentId, Status, Type FROM Case WHERE ParentId =: testCase.Id];
        System.assertEquals('Routine Maintenance', newFollowUpCase.Type);
    }

    @IsTest
    static void positiveTest2(){
        Vehicle__c veh = new Vehicle__c();
        veh.Name = 'Debin RV Negative';
        veh.Awning__c = 'Manual';
        veh.Bathrooms__c = 2.0;
        veh.Bedrooms__c = 2.0;
        insert veh;

        Product2 equipment = new Product2();
        equipment.Name = 'Rotor W1001';
        equipment.ProductCode = 'RW1002';
        equipment.Warehouse_SKU__c = 'SK1002';
        equipment.Replacement_Part__c = true;
        insert equipment;

        Case testCase = new Case();
        testCase.Subject = 'Test Case';
        testCase.Vehicle__c = veh.Id;
        testCase.Status = 'New';
        testCase.Priority = 'Medium';
        testCase.Origin = 'Phone';
        testCase.Type = 'Repair';
        insert testCase;

        Equipment_Maintenance_Item__c item = new Equipment_Maintenance_Item__c();
        item.Maintenance_Request__c = testCase.Id;
        item.Equipment__c = equipment.Id;
        item.Quantity__c = 2;
        insert item;

        testCase.Status = 'Closed';
        Test.startTest();
        update testCase;
        Test.stopTest();
        
    }
    
    @IsTest
    static void negativeTest(){
        Case testCase = [Select ID, Status from Case limit 1];
        testCase.Status = 'Pending';
        Test.startTest();
        update testCase;
        Test.stopTest();
        
    }

    @IsTest
    static void bulkTest(){
        List<Case> bulkUpdateList = new List<Case>();
        List<Case> bulkCaseList = [Select ID, Status from Case];
        for (Case caseRec : bulkCaseList) {
            caseRec.Status = 'Closed';
            bulkUpdateList.add(caseRec);
        }
        Test.startTest();
        update bulkUpdateList;
        Test.stopTest();
        
    }
}
