
global class TEST_MemberService implements TESTMRF.MemberCreation{
    // Getting necessary record types
    private static Map<String, Id> recTypeIdMap = TEST_SObjectUtil.GetRecordTypeIdMap();
    private static Id recordTypeIdMemberAccountRetailer = recTypeIdMap.get('TESTPLT__Member__c-TEST_AccountRetailer');
    private static Id recordTypeIdMemberContactRetailer = recTypeIdMap.get('TESTPLT__Member__c-TEST_ContactRetailer');
    private static Id recordTypeIdMemberContactConsumer = recTypeIdMap.get('TESTPLT__Member__c-TEST_Consumer');
    private static Id recordTypeIdMemberIqosCoach = recTypeIdMap.get('TESTPLT__Member__c-TEST_IqosCoach');
    private static Id recordTypeIdMemberLeadGenerator = recTypeIdMap.get('TESTPLT__Member__c-TEST_LeadGenerator');

    // Final variables
    public static final Integer MEMBER_CREATION_LIMIT = 400; 
    public static final String ERROR_PREFIX = 'error: ';
    public static final String SUCESS_PREFIX = 'success: ';
    public static final String ACTIVE_STATUS = 'Active';
    public static final String BLOCKED_STATUS = 'Blocked';
    public static final String ANONYMIZE_EMAIL = 'anonymize@pmi.com';
    public static final String RESPONDENT_RECORDTYPE = 'Respondent';

    /*
    *@Name : processUpdateResults
    *@description This method will process the result of an Update query
    *@param List<Database.SaveResult> listResult, Map<String, String> message, Map<Id, Id> mapMemberId
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> processUpdateResults(List<Database.SaveResult> listResult, Map<String, String> message, Map<Id, Id> mapMemberId){
        for (Integer i = 0; i < listResult.size(); i++){
            Database.SaveResult sr = listResult.get(i);
            if (sr.isSuccess()){
                message.put(mapMemberId.get(sr.getId()), SUCESS_PREFIX + sr.getId());
            }
            else {
                message.put(mapMemberId.get(sr.getId()), ERROR_PREFIX + sr.getErrors()[0].getMessage());      
            }
        }
        return message;
    }

    /*
    *@Name : anonymizeProviderOrders
    *@description This method will anonymize addresses related to Provider Orders
    *@param Set<Id> setMemberIds
    *@return void
    *@throws NA
    */
    public static void anonymizeProviderOrders(Set<Id> setMemberIds){
		// In order to update these member's related provider orders we need to find their redemptions first
        Map<Id, TESTPLT__Redemption__c> mapRedemptions = new Map<Id, TESTPLT__Redemption__c>([SELECT Id FROM TESTPLT__Redemption__c WHERE TESTPLT__Member__c IN : setMemberIds]);
        if (!mapRedemptions.isEmpty()){
            // If they have redemptions then we update their provider orders with related shipping values with null
            List<TESTPLT__ProviderOrder__c> listProviderOrder = [SELECT Id FROM TESTPLT__ProviderOrder__c WHERE TESTPLT__Redemption__c IN : mapRedemptions.KeySet()];

            if (!listProviderOrder.isEmpty()){
                for (TESTPLT__ProviderOrder__c providerOrder : listProviderOrder){
                    providerOrder.TEST_ShipToAddress1__c = null;
                    providerOrder.TEST_ShipToAddress2__c = null;
                    providerOrder.TEST_ShipToCity__c = null;
                    providerOrder.TEST_ShipToCompany__c = null;
                    providerOrder.TEST_ShipToCountry__c = null;
                    providerOrder.TEST_ShipToName__c = null;
                    providerOrder.TEST_ShipToState__c = null;
                    providerOrder.TEST_ShipToZipCode__c = null;
                    providerOrder.TEST_ShippingEmail__c = null;
                    providerOrder.TEST_ShippingTelephone__c = null;
                }

                // If there are any errors while updating the provider orders, this method will save the error
                TEST_SObjectUtil.processDatabaseResults(Database.update(listProviderOrder, false));               
            }
    	}
    }

    /*
    *@Name : createMemberAccount
    *@description This method will create member(s) for Account(s)
    *@param Set<Id> setAccountIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> createMemberAccount (Set<Id> setAccountIds){
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Account> mapAccountsEligible = new Map<Id, Account>();        

        if (setAccountIds == null){
            accountMessage.put(null, error_prefix + Label.test_accountnoids);
            // Please enter valid Contact Ids.
            return accountMessage;
        }

        if (setAccountIds.size() > MEMBER_CREATION_LIMIT){
            accountMessage.put(null, error_prefix + Label.TEST_AccountIdsLimit);
            return accountMessage;
        }

        // Validations
        for (Account acc : [SELECT Id, Name, RecordType.DeveloperName, DTE_Market__r.DTE_RelatedCountries__c, TEST_MemberId__c, TEST_EligibleForLoyalty__c FROM Account WHERE Id IN : setAccountIds]){
            if (acc.TEST_MemberId__c == null){
                if (acc.TEST_EligibleForLoyalty__c){
                    if (acc.RecordType.DeveloperName == 'Touchpoint'){
                        if (acc.DTE_Market__r.DTE_RelatedCountries__c == null){
                            accountMessage.put(acc.Id, error_prefix + Label.TEST_AccountMarketCountryError);
                            // Account Market related country is empty.
                        }
                        else{
                            mapAccountsEligible.put(acc.Id, acc);
                        }
                    }
                    else{
                        accountMessage.put(acc.Id, error_prefix +  Label.TEST_AccountMustBeTouchpoint);
                        // Account member creation method is only available for Touchpoints.
                    }      
                }
                else{
                    accountMessage.put(acc.Id, error_prefix +  Label.TEST_AccountNotAvailableForLoyalty);
                    // Account is not eligible for loyalty.                    
                }                        
            }
            else{
                accountMessage.put(acc.Id, error_prefix +  Label.TEST_AccountAlreadyHasAMember);
                // Account already has a member.
            }
        }  

        // Proceed only if there are any accounts to create members for
        if (!mapAccountsEligible.values().isEmpty()){ 
            Map<Id, TESTPLT__Member__c> accountMembers = new Map<Id, TESTPLT__Member__c>();

            for (Account acc : mapAccountsEligible.values()){
                TESTPLT__Member__c member = new TESTPLT__Member__c();
                TESTPLT__Program__c program = new TESTPLT__Program__c(TEST_ExternalId__c = 'Retailer-'+ acc.DTE_Market__r.DTE_RelatedCountries__c.substring(0, 2));
                member.Name = acc.Name;
                member.TESTPLT__Account__c = acc.Id;
                member.TESTPLT__Program__r = program;
                member.TESTPLT__Type__c = 'Organization Account';
                member.TESTPLT__Status__c = ACTIVE_STATUS;
                member.RecordTypeId = recordTypeIdMemberAccountRetailer;

                accountMembers.put(acc.Id, member);
            }           
            
            // Proceed only if there are any Members to insert
            if (!accountMembers.values().isEmpty()){
                List<Database.SaveResult> listResult = Database.insert(accountMembers.values(), false);

                for (Integer i = 0; i < listResult.size(); i++){
                    Database.SaveResult sr = listResult.get(i);
                    Id accountId = accountMembers.values().get(i).TESTPLT__Account__c;

                    // On a successful Member insertion, we return a success message with the created member id, and also update the Account Member field with the new Id
                    if (sr.isSuccess()){
                       accountMessage.put(accountId, SUCESS_PREFIX +  sr.getId());
                       mapAccountsEligible.get(accountId).TEST_MemberId__c = sr.getId();
                    }
                    // On a Member insertion failure, we get the error message from the DML result and return it with the related Account
                    else {
                        accountMessage.put(accountId, error_prefix +  sr.getErrors()[0].getMessage());
                        mapAccountsEligible.remove(accountId);
                    }
                }
                
                update mapAccountsEligible.values();
            }
        
        }    
        
        return accountMessage;
    }     
    
    /*
    *@Name : createMemberContact
    *@description This method will create member(s) for Contact(s)
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> createMemberContact(Set<Id> setContactIds){    
        TriggerHandler.bypass('DTE_ContactTriggerHandler');    
        List<TESTPLT__ErrorLog__c> errorsToSave = new List<TESTPLT__ErrorLog__c>();
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Contact> mapContactsEligible = new Map<Id, Contact>();
        Set<Id> setContactsCommunityActivator = new Set<Id>();

        if (setContactIds == null){
            contactMessage.put(null, error_prefix + Label.TEST_ContactNoIds);
            // Please enter valid Contact Ids.
            return contactMessage;
        }

        if (setContactIds.size() > MEMBER_CREATION_LIMIT){
            contactMessage.put(null, ERROR_PREFIX + Label.TEST_ContactIdsLimit);
            return contactMessage;
        }

        // Validations
        for (Contact cs :[SELECT Id, FirstName, LastName, Account.DTE_Market__r.DTE_RelatedCountries__c, CCR_CountryID__c, RecordType.DeveloperName, Account.Id, Account.TEST_MemberId__c, TEST_EligibleForLoyalty__c, TEST_MemberId__c, Email, DTE_isLoyaltyManager__c, TEST_ManagePointBalance__c, CCR_RegistrationConsumerID__r.TEST_MemberId__c, CAA_RegistrationFieldMarketerID__r.Contact.TEST_MemberId__c, OwnerId FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){ 
                if (cs.TEST_EligibleForLoyalty__c){                    
                    if (cs.RecordType.DeveloperName == RESPONDENT_RECORDTYPE || cs.RecordType.DeveloperName == 'CCR_Contact' || cs.RecordType.DeveloperName == 'TEST_CommunityActivator'){
                        // Case Respondent Contact.
                        if (cs.RecordType.DeveloperName == RESPONDENT_RECORDTYPE){
                            if (cs.Account.DTE_Market__r.DTE_RelatedCountries__c == null){
                                contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactAccountMarketCountryError);
                                // Contact Account Market related country is empty.
                            }
                            else{
                                if (cs.Account.TEST_MemberId__c == null){
                                    contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactAccountNotConvertedYet);
                                    // In order to convert a respondent contact into loyalty, the related account must be converted first.        
                                }
                                else{
                                    mapContactsEligible.put(cs.Id, cs);
                                }
                            }
                        }
                        else {
                            // Case Community Activator, it's not necessary to use the field CCR_Country__Id, we use CountryCode on the related User                       
                            if (cs.RecordType.DeveloperName == 'TEST_CommunityActivator'){
                                // A community activator record type can either create a Lead Generator Member or an Iqos Coach one.
                                setContactsCommunityActivator.add(cs.Id);                                   
                                mapContactsEligible.put(cs.Id, cs);                                                      
                            }
                            // Case CCR_Contact.
                            if (cs.RecordType.DeveloperName == 'CCR_Contact'){
                                if (cs.CCR_CountryID__c == null){
                                    contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactCountryIDError);
                                    // CCRCountryID value is empty.
                                }
                                else{
                                    mapContactsEligible.put(cs.Id, cs);
                                }
                            }                                                                               
                        }                   
                    }
                    else{
                        contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactRecordTypeInvalid);
                        // Contact member creation method is only available for Respondent, Contact, Consumer or Iqos Coach.
                    }                   
                }
                else{
                    contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactNotAvailableForLoyalty);
                    // Contact is not eligible for loyalty.
                }
            }          
            else{
                contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactAlreadyHasAMember);
                // Contact already has a member.                
            }            
        }  

        // Proceed only if there are any Contacts that pass the previous criteria
        if (!mapContactsEligible.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> contactMembers = new Map<Id, TESTPLT__Member__c>();
            Map<Id, Id> mapContactUser = new Map<Id, Id>();
            Map<Id, User> mapUsersCommunityActivators;

            // Query some User data necessary to create a Member for a Community Activator (Iqos Coach and Lead Generator)
            if (!setContactsCommunityActivator.isEmpty()){
                mapUsersCommunityActivators = new Map<Id, User>([SELECT Id, Contact.Id, CountryCode, CAA_Role__c FROM User WHERE Contact.Id IN : setContactsCommunityActivator AND CountryCode != null]);

                if (!mapUsersCommunityActivators.isEmpty()){
                    for (User u : mapUsersCommunityActivators.values()){
                        mapContactUser.put(u.Contact.Id, u.Id);                       
                    }
                }
            }

            for (Contact cs : mapContactsEligible.values()){                                
                TESTPLT__Member__c member = new TESTPLT__Member__c();

                // Case Respondent Contacts
                if (cs.RecordType.DeveloperName == RESPONDENT_RECORDTYPE){
                    TESTPLT__Program__c program = new TESTPLT__Program__c(TEST_ExternalId__c = 'Retailer-' + cs.Account.DTE_Market__r.DTE_RelatedCountries__c.substring(0, 2));
                    member.TESTPLT__Program__r = program;
                    member.TESTPLT__Type__c = (cs.TEST_ManagePointBalance__c) ? 'Individual Account' : 'Organization Contributor';
                    member.recordTypeId = recordTypeIdMemberContactRetailer;
                    member.TESTPLT__OrganizationAccount__c = cs.Account.TEST_MemberId__c;
                    member.TESTPLT__Account__c = cs.AccountId;
                    member.TESTPLT__Contact__c = cs.Id;
                    member.Name = ((cs.FirstName + ' ' + cs.LastName).length() > 80) ? cs.LastName : cs.FirstName + ' ' + cs.LastName;                
                    member.TESTPLT__Email__c = cs.Email;
                    member.TESTPLT__IsManager__c = cs.DTE_isLoyaltyManager__c;              
                    member.TESTPLT__Status__c = ACTIVE_STATUS;
                    contactMembers.put(cs.Id, member);
                }
                else {
                    //  Case Community Activator, Iqos Coach and Lead Generator
                    if (cs.RecordType.DeveloperName == 'TEST_CommunityActivator'){
                        if (mapContactUser.containsKey(cs.Id)){
                            // Lead Generator
                            if (mapUsersCommunityActivators.get(mapContactUser.get(cs.Id)).CAA_Role__c == 'Lead Generator'){
                                TESTPLT__Program__c program = new TESTPLT__Program__c(TEST_ExternalId__c = 'Lead Generator-' + mapUsersCommunityActivators.get(mapContactUser.get(cs.Id)).CountryCode.substring(0, 2));
                                member.recordTypeId = recordTypeIdMemberLeadGenerator;
                                member.TESTPLT__Program__r = program;                              
                            }
                            // Iqos Coach, if CAA_Role__c is either null or different than Lead Generator
                            else {
                                TESTPLT__Program__c program = new TESTPLT__Program__c(TEST_ExternalId__c = 'Iqos Coach-' + mapUsersCommunityActivators.get(mapContactUser.get(cs.Id)).CountryCode.substring(0, 2));
                                member.recordTypeId = recordTypeIdMemberIqosCoach;
                                member.TESTPLT__Program__r = program;                              
                            }  

                            member.TESTPLT__Contact__c = cs.Id;
                            member.Name = ((cs.FirstName + ' ' + cs.LastName).length() > 80) ? cs.LastName : cs.FirstName + ' ' + cs.LastName;                
                            member.TESTPLT__Email__c = cs.Email;
                            member.TESTPLT__Status__c = ACTIVE_STATUS; 
                            member.TESTPLT__Type__c = 'Individual Account';   
                            member.TESTPLT__IsManager__c = true;
                            member.OwnerId = mapContactUser.get(cs.Id);
                            member.TESTPLT__User__c = mapContactUser.get(cs.Id);
                          
                            contactMembers.put(cs.Id, member);                        
                        }
                        else {
                            contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactDoesNotHaveUser);
                            // Contact does not have a related User, or the User does not have 'CountryCode' field filled.
                            mapContactsEligible.remove(cs.Id); 
                        }
                        
                    }
                    // Case CCR_Contact
                    else if (cs.RecordType.DeveloperName == 'CCR_Contact') {
                        TESTPLT__Program__c program = new TESTPLT__Program__c(TEST_ExternalId__c = 'Consumer-' + cs.CCR_CountryID__c.substring(0, 2));
                        member.TESTPLT__Program__r = program;
                        member.TESTPLT__Contact__c = cs.Id;
                        member.Name = ((cs.FirstName + ' ' + cs.LastName).length() > 80) ? cs.LastName : cs.FirstName + ' ' + cs.LastName;                
                        member.TESTPLT__Email__c = cs.Email;
                        member.TESTPLT__Status__c = ACTIVE_STATUS; 
                        member.TESTPLT__Type__c = 'Individual Account';   
                        member.TESTPLT__IsManager__c = true;
                        member.recordTypeId = recordTypeIdMemberContactConsumer;
                        member.TEST_ReferredBy__c = cs.CCR_RegistrationConsumerID__r.TEST_MemberId__c;
                        member.TEST_RegisteredBy__c = cs.CAA_RegistrationFieldMarketerID__r.Contact.TEST_MemberId__c;
                        member.TEST_CountryIsoCode__c = cs.CCR_CountryID__c;

                        // Checking if this custom setting exists and has a value
                        // If it doesn't, then we don't change the owner, and save the exception
                        try {
                            if (CTIConstants__c.getAll().get('IREFER_KafkaUserId').CTI_Value__c InstanceOf Id){
                                member.OwnerId = CTIConstants__c.getAll().get('IREFER_KafkaUserId').CTI_Value__c;
                            }
                        }
                        catch (System.NullPointerException ex) {                            
                              TESTPLT__ErrorLog__c errorToAdd = new TESTPLT__ErrorLog__c(TESTPLT__LineNumber__c = ex.getLineNumber(), TESTPLT__Message__c = ex.getMessage(), TESTPLT__StackTrace__c = ex.getStackTraceString(), TESTPLT__Type__c = ex.getTypeName());
                              errorsToSave.add(errorToAdd);
                        }
                       
                        contactMembers.put(cs.Id, member);
                    }                   
                }                            
            }

            if (!errorsToSave.isEmpty()){
                Database.insert(errorsToSave, false);
            }

            // Proceed only if there are any Members to insert
            if (!contactMembers.isEmpty()){
                List<Database.SaveResult> listResult = Database.insert(contactMembers.values(), false);

                for (Integer i = 0; i < listResult.size(); i++){
                    Database.SaveResult sr = listResult.get(i);
                    Id contactId = contactMembers.values().get(i).TESTPLT__Contact__c;

                    // On a successful Member insertion, we return a success message with the created member id, and also update the Contact Member field with the new Id
                    if (sr.isSuccess()){
                       contactMessage.put(contactId, SUCESS_PREFIX +  sr.getId());
                       mapContactsEligible.get(contactId).TEST_MemberId__c = sr.getId();
                    }
                    // On a Member insertion failure, we get the error message from the DML result and return it with the related Contact
                    else {
                        contactMessage.put(contactId, ERROR_PREFIX +  sr.getErrors()[0].getMessage());
                        mapContactsEligible.remove(contactId);
                    }
                }
                
                update mapContactsEligible.values();
            }

        }

        return contactMessage;
    }

    /*
    *@Name : suspendMember
    *@description This method will suspend Members based on their Contact status
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> suspendMember(Set<Id> setContactIds){  
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c, TEST_EligibleForLoyalty__c, DTE_Suspended__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){ 
                contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactDoesNotHaveAMember);
                // Contact does not have a related member.
            }
            else {               
                if (cs.DTE_Suspended__c){
                    if (cs.TEST_EligibleForLoyalty__c){
                        contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactLoyaltyFalse);
                        // If you want to suspend a member the value of the field "Eligible For Loyalty" must be false.
                    }
                    else {
                        mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
                    }
                }
                else {
                    contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactSuspendedFalse);
                    // If you want to suspend a member the value of the field "DTE_Suspended_c" must be true.
                }
            }
        }

        // Proceed only if there any valid Contact(s) to suspend their Member
        if (!mapMemberContact.values().isEmpty()){
            List<TESTPLT__Member__c> membersToSuspend = new List<TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Contact__c FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
            
            // Now we set the related members to suspended and status blocked
            if (!membersToSuspend.isEmpty()){
                for (TESTPLT__Member__c m : membersToSuspend){                       
                        m.TEST_Suspended__c = true;  
                        m.TESTPLT__Status__c = BLOCKED_STATUS;
                }

                if (Test.isRunningTest()){   
                    membersToSuspend[0].Id = null;
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersToSuspend, false);
                contactMessage = processUpdateResults(listResult, contactMessage, mapMemberContact);
            }
        }

        return contactMessage;
    }

    /*
    *@Name : unBlockMember
    *@description This method will Members based on their Contact status
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> unBlockMember(Set<Id> setContactIds){  
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c, TEST_EligibleForLoyalty__c, DTE_Suspended__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){ 
                contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactDoesNotHaveAMember);               
            }
            else {
                // Contact does not have a related member.
                if (cs.DTE_Suspended__c){
                    contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactUnBlockSuspendedTrue);  
                }
                else {
                    // If you want to reactivate a member the value of the field "DTE_Suspended_c" on Contact must be false.
                    if (cs.TEST_EligibleForLoyalty__c){
                        mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
                    }
                    else {
                        contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactUnBlockLoyaltyFalse);
                        // If you want to reactivate a member the value of the field "Eligible For Loyalty" must be true.
                    }
                }
            }
        }

        // Proceed only if there any valid Contact(s) to suspend their Member
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToActivate = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Contact__c FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
            
            // Now we set the related members to not suspended and status active
            if (!membersToActivate.values().isEmpty()){
                for (TESTPLT__Member__c m : membersToActivate.values()){  
                    if (m.TESTPLT__Status__c == ACTIVE_STATUS){
                       contactMessage.put(mapMemberContact.get(m.Id), ERROR_PREFIX + Label.TEST_ContactUnBlockMemberActive);
                       // Member is already active.
                       membersToActivate.remove(m.Id);
                    }
                    else {                       
                        m.TEST_Suspended__c = false;  
                        m.TESTPLT__Status__c = ACTIVE_STATUS;
                    }
                }

                if (Test.isRunningTest()){   
                    membersToActivate.values()[0].Id = null;
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersToActivate.values(), false);
                contactMessage = processUpdateResults(listResult, contactMessage, mapMemberContact);
            }
        }

        return contactMessage;
    }

    /*
    *@Name : blockMember
    *@description This method will only block Members based on their Contact status, but will not suspend them
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> blockMember(Set<Id> setContactIds){  
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c, TEST_EligibleForLoyalty__c, DTE_Suspended__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){ 
                contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactDoesNotHaveAMember);
            }
            else {
                // Contact does not have a related member.
                if (cs.DTE_Suspended__c){
                    contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactBlockSuspendedTrue);
                }
                else {
                    // If you want to block a member the value of the field "DTE_Suspended_c" must be false.
                    if (cs.TEST_EligibleForLoyalty__c){
                        contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactBlockLoyaltyTrue);
                        // If you want to block a member the value of the field "Eligible For Loyalty" must be false.
                    }
                    else {
                        mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
                    }
                }
            }
        }

        // Proceed only if there any valid Contact(s) to suspend their Member
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToBlock = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Contact__c FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
         
            // Now we set the related members to suspended and status blocked
            if (!membersToBlock.values().isEmpty()){
                for (TESTPLT__Member__c m : membersToBlock.values()){  
                    if (m.TESTPLT__Status__c == BLOCKED_STATUS){
                        contactMessage.put(mapMemberContact.get(m.Id), ERROR_PREFIX + Label.TEST_ContactBlockMemberBlocked);
                        // Member is already blocked.
                        membersToBlock.remove(m.Id);
                    }
                    else {                       
                        m.TEST_Suspended__c = false;  
                        m.TESTPLT__Status__c = BLOCKED_STATUS;
                    }          
                      
                }

                if (Test.isRunningTest()){   
                    membersToBlock.values()[0].Id = null;
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersToBlock.values(), false);
                contactMessage = processUpdateResults(listResult, contactMessage, mapMemberContact);
            }
        }

        return contactMessage;
    }

    /*
    *@Name : blockOrganizationAccMember
    *@description This method will block Account Members
    *@param Set<Id> setAccountIds, Boolean blockMemberContacts
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> blockOrganizationAccMember(Set<Id> setAccountIds, Boolean blockMemberContacts){    
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Id> mapMemberAccount = new Map<Id, Id>();

        // Validations
        for (Account acc : [SELECT Id, TEST_MemberId__c, TEST_EligibleForLoyalty__c FROM Account WHERE Id IN : setAccountIds]){
            if (acc.TEST_MemberId__c == null){
                accountMessage.put(acc.Id, ERROR_PREFIX +  Label.TEST_AccountDoesNotHaveMember);        
            }
            else{
                // Account does not have a related member.
                if (acc.TEST_EligibleForLoyalty__c){
                    accountMessage.put(acc.Id, ERROR_PREFIX + Label.TEST_AccountMemberOrgMustBeLoyal);
                    // If you want to block a member the value of the field "Eligible for Loyalty" must be false.
                }
                else{                  
                    mapMemberAccount.put(acc.TEST_MemberId__c, acc.Id);
                }           
            }
        }

        // Proceed only if there are any accounts to create members for
        if (!mapMemberAccount.values().isEmpty()){ 
            Set<Id> setContactMemberIds = new Set<Id>();           
            Map<Id, TESTPLT__Member__c> membersRelatedToAccounts = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Account__c, TESTPLT__Contact__c  FROM TESTPLT__Member__c WHERE TESTPLT__Account__c IN : mapMemberAccount.values()]);

            // Now we set the related members to suspended and status blocked
            if (!membersRelatedToAccounts.values().isEmpty()){
                for (TESTPLT__Member__c m : membersRelatedToAccounts.values()){

                    if (mapMemberAccount.get(m.Id) == null){
                        mapMemberAccount.put(m.Id, m.TESTPLT__Account__c);
                        setContactMemberIds.add(m.Id);
                    }

                    if (m.TESTPLT__Status__c == BLOCKED_STATUS){
                        accountMessage.put(mapMemberAccount.get(m.Id), ERROR_PREFIX + Label.TEST_AccountMemberAlreadyBlocked);                     
                        // Member is already blocked.
                        membersRelatedToAccounts.remove(m.Id);                        
                    }
                    else{
                        // Related contacts members
                        if (setContactMemberIds.contains(m.Id) && blockMemberContacts){
                            m.TESTPLT__Status__c = BLOCKED_STATUS;
                            m.TEST_Suspended__c = false;
                        }
                        else if (mapMemberAccount.containsKey(m.Id)) {
                            // Organization account member
                            m.TESTPLT__Status__c = BLOCKED_STATUS;
                        }                      
                    }
                }              

                if (Test.isRunningTest() && !membersRelatedToAccounts.isEmpty()){   
                        membersRelatedToAccounts.values()[1].Id = null;
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersRelatedToAccounts.values(), false);
                accountMessage = processUpdateResults(listResult, accountMessage, mapMemberAccount);              
            }

        }

        return accountMessage;
    }

    /*
    *@Name : unBlockOrganizationAccMember
    *@description This method will unblock Account Members
    *@param Set<Id> setAccountIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> unBlockOrganizationAccMember(Set<Id> setAccountIds){    
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Id> mapMemberAccount = new Map<Id, Id>();

        // Validations
        for (Account acc : [SELECT Id, TEST_MemberId__c, TEST_EligibleForLoyalty__c FROM Account WHERE Id IN : setAccountIds]){
            if (acc.TEST_MemberId__c == null){
                accountMessage.put(acc.Id, ERROR_PREFIX +  Label.TEST_AccountMemberDoesNotExist);
                // Account does not have a related member.  
            }
            else{
                if (acc.TEST_EligibleForLoyalty__c){
                    mapMemberAccount.put(acc.TEST_MemberId__c, acc.Id);
                }
                else{
                    accountMessage.put(acc.Id, ERROR_PREFIX +  Label.TEST_AccountMemberOrgLoyalUnblock);
                    // If you want to unblock a member the value of the field "Eligible for Loyalty" must be true.
                }               
            }
        }

        // Proceed only if there are any accounts to create members for
        if (!mapMemberAccount.values().isEmpty()){            
            Map<Id, TESTPLT__Member__c> membersRelatedToAccounts = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Account__c FROM TESTPLT__Member__c WHERE TESTPLT__Account__c IN : mapMemberAccount.values() AND TESTPLT__Type__c = 'Organization Account']);
            // Now we set the related members to suspended and status blocked
            if (!membersRelatedToAccounts.values().isEmpty()){
                for (TESTPLT__Member__c m : membersRelatedToAccounts.values()){  
                    if (m.TESTPLT__Status__c == ACTIVE_STATUS){     
                        accountMessage.put(mapMemberAccount.get(m.Id), ERROR_PREFIX + Label.TEST_AccountMemberOrgIsActive);
                        // Member is already Active.
                        membersRelatedToAccounts.remove(m.Id);                   
                    }
                    else{                       
                        m.TESTPLT__Status__c = ACTIVE_STATUS;                       
                    }
                }   

                if (Test.isRunningTest() && !membersRelatedToAccounts.isEmpty()){   
                    membersRelatedToAccounts.values()[1].Id = null;
                }
                
                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersRelatedToAccounts.values(), false);
                accountMessage = processUpdateResults(listResult, accountMessage, mapMemberAccount);
            }

        }

        return accountMessage;
    }

    /*
    *@Name : updateMemberContact
    *@description This method will update member(s) for Contact(s)
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> updateMemberContact(Set<Id> setContactIds){
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        // Validations
        for (Contact cs : [SELECT Id, TEST_MemberId__c, TEST_EligibleForLoyalty__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){ 
               contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactDoesNotHaveAMember);
               // Contact does not have a member.   
            }          
            else{                     
                if (cs.TEST_EligibleForLoyalty__c){
                    mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
                }
                else{
                    contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactNotAvailableForLoyalty);
                    // Contact is not eligible for loyalty.
                }       
            }            
        }   

        // Proceed only if there any valid Contact(s) to update their Member
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToUpdate = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Contact__c, TESTPLT__Contact__r.FirstName, TESTPLT__Contact__r.LastName, TESTPLT__Contact__r.AccountId, TESTPLT__Contact__r.Account.TEST_MemberId__c, TESTPLT__Contact__r.Email, TESTPLT__Contact__r.RecordType.DeveloperName FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
            
            // Now we update the available members
            if (!membersToUpdate.values().isEmpty()){
                for (TESTPLT__Member__c member : membersToUpdate.values()){  
                    if (member.TESTPLT__Contact__r.RecordType.DeveloperName == RESPONDENT_RECORDTYPE){
                        member.TESTPLT__OrganizationAccount__c = member.TESTPLT__Contact__r.Account.TEST_MemberId__c;
                    }
                    member.Name = ((member.TESTPLT__Contact__r.FirstName + ' ' + member.TESTPLT__Contact__r.LastName).length() > 80) ? member.TESTPLT__Contact__r.LastName : member.TESTPLT__Contact__r.FirstName + ' ' + member.TESTPLT__Contact__r.LastName;
                    member.TESTPLT__Account__c = member.TESTPLT__Contact__r.AccountId;
                    member.TESTPLT__Email__c = member.TESTPLT__Contact__r.Email;
                }

                if (Test.isRunningTest() && !membersToUpdate.isEmpty()){   
                    membersToUpdate.values()[1].Id = null;
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersToUpdate.values(), false);
                contactMessage = processUpdateResults(listResult, contactMessage, mapMemberContact);
            }
        }

        return contactMessage;
    }       
    
    /*
    *@Name : changeManager
    *@description This method will update manager field on members based on Contacts
    *@param Set<Id> setAccountIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> changeManager(Set<Id> setContactIds){    
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){                
                contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactDoesNotHaveAMember);
                // Contact does not have a related member.
            }                  
            else {
                mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
            }
        }

        // Proceed only if there any valid Contact(s) to change their Manager status
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToChangeManager = new Map<Id, TESTPLT__Member__c>([SELECT Id, TESTPLT__IsManager__c, TESTPLT__Contact__c, TESTPLT__Contact__r.DTE_isLoyaltyManager__c FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
            
            // Now we set the related members to suspended and status blocked
            if (!membersToChangeManager.values().isEmpty()){
                for (TESTPLT__Member__c m : membersToChangeManager.values()){                       
                     m.TESTPLT__IsManager__c = m.TESTPLT__Contact__r.DTE_isLoyaltyManager__c;
                }          

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersToChangeManager.values(), false);
                contactMessage = processUpdateResults(listResult, contactMessage, mapMemberContact);
            }
        }

        return contactMessage;  
    }

    /*
    *@Name : anonymizeMember
    *@description This method anonymise members based on Contacts
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> anonymizeMember(Set<Id> setContactIds){    
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){     
                contactMessage.put(cs.Id, ERROR_PREFIX +  Label.TEST_ContactDoesNotHaveAMember);
                // Contact does not have a related member.            
            }         
            else {              
                mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);  
            }
        }

        // Proceed only if there any valid Contact(s) to anonymize
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToBeAnonymized = new Map<Id, TESTPLT__Member__c>([SELECT Id, TESTPLT__Contact__r.Name FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);

            // Now we update the members with their anonymous values
            if (!membersToBeAnonymized.values().isEmpty()){
                for (TESTPLT__Member__c member : membersToBeAnonymized.values()){      
                    member.TESTPLT__Email__c = ANONYMIZE_EMAIL;                 
                    member.TEST_ReferredBy__c = null;
                    member.Name = member.TESTPLT__Contact__r.Name;
                    member.TEST_Suspended__c = true;  
                    member.TESTPLT__Status__c = BLOCKED_STATUS;
                }       

                // Anonymizing addresses, if any, on provider orders
                anonymizeProviderOrders(membersToBeAnonymized.keySet());
                
                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersToBeAnonymized.values(), false);
                contactMessage = processUpdateResults(listResult, contactMessage, mapMemberContact);
            }
        }

        return contactMessage;  
    }
 
    /*
    *@Name : optOutMember
    *@description This method will block and suspend Members related to Contacts
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> optOutMember(Set<Id> setContactIds){  
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Contact> mapContactsToUpdate = new Map<Id, Contact>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c, TEST_LoyaltyOptOut__c, DTE_Suspended__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_MemberId__c == null){ 
                contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactDoesNotHaveAMember);
                // Contact does not have a related member.
            }
            else {
                if (cs.DTE_Suspended__c || cs.TEST_LoyaltyOptOut__c){                  
                    mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
                    mapContactsToUpdate.put(cs.Id, cs);
                }
                else {
                    contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_OptOutContactNotSuspended);
                    // In order to Opt out a Member, "Loyalty Opt Out" or "Suspended" fields on Contact have to be true.
                }              
            }
        }

        // Proceed only if there any valid Contact(s) to opt out their Member
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> mapContactMembers = new Map<Id, TESTPLT__Member__c>();

            Map<Id, TESTPLT__Member__c> membersToOptOut = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Contact__c FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
         
            // Now we set the related members to suspended and status blocked
            if (!membersToOptOut.values().isEmpty()){
                for (TESTPLT__Member__c member : membersToOptOut.values()){
                    member.TEST_Suspended__c = true;  
                    member.TESTPLT__Status__c = BLOCKED_STATUS;
                    mapContactMembers.put(member.TESTPLT__Contact__c, member);
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(mapContactMembers.values(), false);

                for (Integer i = 0; i < listResult.size(); i++){
                    Database.SaveResult sr = listResult.get(i);
                    Id contactId = mapContactMembers.values().get(i).TESTPLT__Contact__c;

                    // On a successful Member update we update some values on Contact
                    if (sr.isSuccess()){
                       contactMessage.put(contactId, SUCESS_PREFIX + sr.getId());
                       mapContactsToUpdate.get(contactId).TEST_EligibleForLoyalty__c = false;
                       mapContactsToUpdate.get(contactId).TEST_LoyaltyOptOut__c = true;
                       mapContactsToUpdate.get(contactId).DTE_Suspended__c = true;
                    }
                    // On a Member update failure we return the message
                    else {
                        contactMessage.put(contactId, ERROR_PREFIX +  sr.getErrors()[0].getMessage());
                        mapContactsToUpdate.remove(contactId);
                    }
                }
                
                update mapContactsToUpdate.values();
            }
        }

        return contactMessage;
    }

    /*
    *@Name : optInMember
    *@description This method will activate and revert the suspension of Members and Contacts
    *@param Set<Id> setContactIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> optInMember(Set<Id> setContactIds){  
        Map<String, String> contactMessage = new Map<String, String>();
        Map<Id, Contact> mapContactsToUpdate = new Map<Id, Contact>();
        Map<Id, Id> mapMemberContact = new Map<Id, Id>();

        for (Contact cs : [SELECT Id, TEST_MemberId__c, TEST_LoyaltyOptOut__c, DTE_Suspended__c, TEST_EligibleForLoyalty__c FROM Contact WHERE Id IN : setContactIds]){ 
            if (cs.TEST_EligibleForLoyalty__c){
                if (cs.TEST_MemberId__c == null){ 
                    contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_ContactDoesNotHaveAMember);
                    // Contact does not have a related member.
                }
                else {                   
                    if (cs.TEST_LoyaltyOptOut__c){           
                        contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_OptInContactNotFalse);
                        // In order to Opt in a Member, "Loyalty Opt Out" field on Contact must be false.      
                    }
                    else {
                        mapMemberContact.put(cs.TEST_MemberId__c, cs.Id);
                        mapContactsToUpdate.put(cs.Id, cs);
                    }
                }
            }
            else{
                contactMessage.put(cs.Id, ERROR_PREFIX + Label.TEST_OptInEligibleNotFalse);
                // In order to Opt in a Member, "Eligible for Loyalty" field on Contact must be true.
            }
        }

        // Proceed only if there any valid Contact(s) to opt in their Member
        if (!mapMemberContact.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> mapContactMembers = new Map<Id, TESTPLT__Member__c>();

            Map<Id, TESTPLT__Member__c> membersToOptOut = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Contact__c FROM TESTPLT__Member__c WHERE TESTPLT__Contact__c IN : mapMemberContact.values()]);
         
            // Now we set the related members to suspended false and status active
            if (!membersToOptOut.values().isEmpty()){
                for (TESTPLT__Member__c member : membersToOptOut.values()){
                    member.TEST_Suspended__c = false;  
                    member.TESTPLT__Status__c = ACTIVE_STATUS;
                    mapContactMembers.put(member.TESTPLT__Contact__c, member);
                }

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(mapContactMembers.values(), false);

                for (Integer i = 0; i < listResult.size(); i++){
                    Database.SaveResult sr = listResult.get(i);
                    Id contactId = mapContactMembers.values().get(i).TESTPLT__Contact__c;

                    // On a successful Member update we update some values on Contact
                    if (sr.isSuccess()){
                       contactMessage.put(contactId, SUCESS_PREFIX + sr.getId());
                       mapContactsToUpdate.get(contactId).TEST_LoyaltyOptOut__c = false;
                       mapContactsToUpdate.get(contactId).DTE_Suspended__c = false;
                       mapContactsToUpdate.get(contactId).TEST_EligibleForLoyalty__c = true;
                    }
                    // On a Member update failure we return the message
                    else {
                        contactMessage.put(contactId, ERROR_PREFIX +  sr.getErrors()[0].getMessage());
                        mapContactsToUpdate.remove(contactId);
                    }
                }
                
                update mapContactsToUpdate.values();
            }
        }

        return contactMessage;
    }

    /*
    *@Name : optOutOrgAccMember
    *@description This method will opt out Members related to Accounts, and if it's the case also related to Contacts
    *@param Set<Id> setAccountIds, Boolean blockMemberContacts
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> optOutOrgAccMember(Set<Id> setAccountIds, Boolean blockMemberContacts){    
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Id> mapMemberAccount = new Map<Id, Id>();
        Set<Id> setMemberAccount = new Set<Id>();

        // Validations
        for (Account acc : [SELECT Id, TEST_MemberId__c, TEST_LoyaltyOptOut__c FROM Account WHERE Id IN : setAccountIds]){
            if (acc.TEST_MemberId__c == null){
                accountMessage.put(acc.Id, ERROR_PREFIX +  Label.TEST_AccountDoesNotHaveMember);
                // Account does not have a related member.
            }
            else {
                if (acc.TEST_LoyaltyOptOut__c){
                    mapMemberAccount.put(acc.TEST_MemberId__c, acc.Id);
                    setMemberAccount.add(acc.TEST_MemberId__c);
                }
                else{
                    accountMessage.put(acc.Id, ERROR_PREFIX + Label.TEST_OptOutAccountNotTrue);
                    // In order to Opt out a Member, "Loyalty Opt Out" field on Account must be true.
                }                        
            }
        }

        // Proceeding if any of the received Accounts pass the validations
        if (!mapMemberAccount.values().isEmpty()){
            Set<Id> setContactIdsToUpdate = new Set<Id>();
            Set<Id> setContactMemberIds = new Set<Id>();

            Map<Id, TESTPLT__Member__c> membersRelatedToAccounts = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Account__c, TESTPLT__Contact__c  FROM TESTPLT__Member__c WHERE TESTPLT__Account__c IN : mapMemberAccount.values()]);

            if (!membersRelatedToAccounts.values().isEmpty()){
                for (TESTPLT__Member__c member : membersRelatedToAccounts.values()){
                    if (mapMemberAccount.get(member.Id) == null){
                        mapMemberAccount.put(member.Id, member.TESTPLT__Account__c);
                        setContactMemberIds.add(member.Id);
                    } 

                    if (member.TESTPLT__Status__c == BLOCKED_STATUS){
                        accountMessage.put(mapMemberAccount.get(member.Id), ERROR_PREFIX + Label.TEST_AccountMemberAlreadyBlocked);                     
                        // Member is already blocked.
                        membersRelatedToAccounts.remove(member.Id);
                    }
                    else {                                      
                        // If it's in this set and the blockMemberContacts is true then we know
                        // it's a member related to the account contact and we have to block it as well
                        if (setContactMemberIds.contains(member.Id) && blockMemberContacts){
                            setContactIdsToUpdate.add(member.TESTPLT__Contact__c);  
                            member.TESTPLT__Status__c = BLOCKED_STATUS;
                            member.TEST_Suspended__c = true;                            
                        }
                        else if (setMemberAccount.contains(member.Id)) {
                            // Suspending and blocking Account member
                            member.TESTPLT__Status__c = BLOCKED_STATUS;
                            member.TEST_Suspended__c = true;       
                        }
                    }
                }              

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersRelatedToAccounts.values(), false);
                accountMessage = processUpdateResults(listResult, accountMessage, mapMemberAccount);

                // Updating a few contacts fields, if there are any
                if (!setContactIdsToUpdate.isEmpty()){
                    List<Contact> listContactsToUpdate = [SELECT Id, TEST_LoyaltyOptOut__c, DTE_Suspended__c, TEST_EligibleForLoyalty__c FROM Contact WHERE Id IN : setContactIdsToUpdate];
                    
                    for (Contact contact : listContactsToUpdate){
                        contact.TEST_LoyaltyOptOut__c = true;
                        contact.DTE_Suspended__c = true;
                        contact.TEST_EligibleForLoyalty__c = false;
                    }

                    // If there are any errors while updating contacts, this method will save the error
                    TEST_SObjectUtil.processDatabaseResults(Database.update(listContactsToUpdate, false));    
                }              
            }
        }

        return accountMessage;
    }

    /*
    *@Name : optInOrgAccMember
    *@description This method will opt in Members related to Accounts, and if it's the case also related to Contacts
    *@param Set<Id> setAccountIds, Boolean activateMemberContacts
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> optInOrgAccMember(Set<Id> setAccountIds, Boolean activateMemberContacts){    
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Id> mapMemberAccount = new Map<Id, Id>();
        Set<Id> setMemberAccount = new Set<Id>();

        // Validations
        for (Account acc : [SELECT Id, TEST_MemberId__c, TEST_LoyaltyOptOut__c FROM Account WHERE Id IN : setAccountIds]){
            if (acc.TEST_MemberId__c == null){
                accountMessage.put(acc.Id, ERROR_PREFIX +  Label.TEST_AccountDoesNotHaveMember);
                // Account does not have a related member.             
            }
            else {
                if (acc.TEST_LoyaltyOptOut__c){
                    accountMessage.put(acc.Id, ERROR_PREFIX + Label.TEST_OptInAccountNotFalse);
                    // In order to Opt in a Member, "Loyalty Opt Out" field on Account must be false.                   
                }
                else{
                    mapMemberAccount.put(acc.TEST_MemberId__c, acc.Id);
                    setMemberAccount.add(acc.TEST_MemberId__c);
                }
            }
        }
 
        // Proceeding if any of the received Accounts pass the validations
        if (!mapMemberAccount.values().isEmpty()){
            Set<Id> setContactIdsToUpdate = new Set<Id>(); 
            Set<Id> setContactMemberIds = new Set<Id>(); 
 
            Map<Id, TESTPLT__Member__c> membersRelatedToAccounts = new Map<Id, TESTPLT__Member__c>([SELECT Id, TEST_Suspended__c, TESTPLT__Status__c, TESTPLT__Account__c, TESTPLT__Contact__c  FROM TESTPLT__Member__c WHERE TESTPLT__Account__c IN : mapMemberAccount.values()]);
 
            if (!membersRelatedToAccounts.values().isEmpty()){ 
                for (TESTPLT__Member__c member : membersRelatedToAccounts.values()){ 
                    if (mapMemberAccount.get(member.Id) == null){ 
                        mapMemberAccount.put(member.Id, member.TESTPLT__Account__c); 
                        setContactMemberIds.add(member.Id); 
                    } 

                    if (member.TESTPLT__Status__c == ACTIVE_STATUS){
                        accountMessage.put(mapMemberAccount.get(member.Id), ERROR_PREFIX + Label.TEST_ContactUnBlockMemberActive);                     
                        // Member is already active.
                        membersRelatedToAccounts.remove(member.Id);
                    }
                    else {                                      
                        // If it's in this set and the activateMemberContacts is true then we know
                        // it's a member related to the account contact and we have to activate it as well
                        if (setContactMemberIds.contains(member.Id) && activateMemberContacts){
                            setContactIdsToUpdate.add(member.TESTPLT__Contact__c);  
                            member.TESTPLT__Status__c = ACTIVE_STATUS;
                            member.TEST_Suspended__c = false;                            
                        }
                        else if (setMemberAccount.contains(member.Id)) {
                            // Suspending and blocking Account member
                            member.TESTPLT__Status__c = ACTIVE_STATUS;
                            member.TEST_Suspended__c = false;                            
                        }
                    }
                }              

                // Updating member(s) status
                List<Database.SaveResult> listResult = Database.update(membersRelatedToAccounts.values(), false);
                accountMessage = processUpdateResults(listResult, accountMessage, mapMemberAccount);

                // Updating a few contacts fields, if there are any
                if (!setContactIdsToUpdate.isEmpty()){
                    List<Contact> listContactsToUpdate = [SELECT Id, TEST_LoyaltyOptOut__c, DTE_Suspended__c, TEST_EligibleForLoyalty__c FROM Contact WHERE Id IN : setContactIdsToUpdate];
                    
                    for (Contact contact : listContactsToUpdate){
                        contact.TEST_LoyaltyOptOut__c = false;
                        contact.DTE_Suspended__c = false;
                        contact.TEST_EligibleForLoyalty__c = true;
                    }

                    // If there are any errors while updating contacts, this method will save the error
                    TEST_SObjectUtil.processDatabaseResults(Database.update(listContactsToUpdate, false));    
                }              
            }
        }

        return accountMessage;
    }

    /*
    *@Name : anonymizeOrgAccMember
    *@description This method will anonymize member(s) for Account(s)
    *@param Set<Id> setAccountIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> anonymizeOrgAccMember(Set<Id> setAccountIds){
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Id> mapMemberAccount = new Map<Id, Id>();

        // Validations
        for (Account account : [SELECT Id, TEST_MemberId__c FROM Account WHERE Id IN : setAccountIds]){ 
            if (account.TEST_MemberId__c == null){ 
                accountMessage.put(account.Id, ERROR_PREFIX + Label.TEST_AccountDoesNotHaveMember);
                // Account does not have a member.                        
            }          
            else{
                mapMemberAccount.put(account.TEST_MemberId__c, account.Id);  
            }            
        }   

        // Proceed only if there any valid Account(s) to anonymize their Member
        if (!mapMemberAccount.values().isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToBeAnonymized = new Map<Id, TESTPLT__Member__c>([SELECT Id, TESTPLT__Account__r.Name FROM TESTPLT__Member__c WHERE TESTPLT__Account__c IN : mapMemberAccount.values()]);
            
            // Now we update available members
            if (!membersToBeAnonymized.values().isEmpty()){
                for (TESTPLT__Member__c member : membersToBeAnonymized.values()){   
                    member.Name = member.TESTPLT__Account__r.Name;
                    member.TESTPLT__Email__c = ANONYMIZE_EMAIL;
                    member.TESTPLT__Status__c = BLOCKED_STATUS;
                    member.TEST_Suspended__c = true;       
                } 

                // Anonymizing addresses, if any, on provider orders
                anonymizeProviderOrders(membersToBeAnonymized.keySet());

                // Updating member(s) status                     
                List<Database.SaveResult> listResult = Database.update(membersToBeAnonymized.values(), false);
                accountMessage = processUpdateResults(listResult, accountMessage, mapMemberAccount);
       		}
       	}

        return accountMessage;
    }

    /*
    *@Name : updateOrgAccMember
    *@description This method will update member(s) for Account(s)
    *@param Set<Id> setAccountIds
    *@return Map<String, String>
    *@throws NA
    */
    public static Map<String, String> updateOrgAccMember(Set<Id> setAccountIds){
        Map<String, String> accountMessage = new Map<String, String>();
        Map<Id, Id> mapMemberAccount = new Map<Id, Id>();

        // Validations
        for (Account account : [SELECT Id, TEST_MemberId__c FROM Account WHERE Id IN : setAccountIds]){ 
            if (account.TEST_MemberId__c == null){ 
                accountMessage.put(account.Id, ERROR_PREFIX + Label.TEST_AccountDoesNotHaveMember); 
                // Account does not have a member.                  
            }         
            else{
                mapMemberAccount.put(account.TEST_MemberId__c, account.Id);  
            }           
        }   

        // Proceed only if there any valid Account(s) to update their Member
        if (!mapMemberAccount.isEmpty()){
            Map<Id, TESTPLT__Member__c> membersToBeAnonymized = new Map<Id, TESTPLT__Member__c>([SELECT Id, TESTPLT__Account__r.Name, TESTPLT__Email__c FROM TESTPLT__Member__c WHERE TESTPLT__Account__c IN : mapMemberAccount.values()]);
            
            // Now we update available members
            if (!membersToBeAnonymized.values().isEmpty()){
                for (TESTPLT__Member__c member : membersToBeAnonymized.values()){   
                    member.Name = member.TESTPLT__Account__r.Name;
                }              

                // Updating member(s) status                     
                List<Database.SaveResult> listResult = Database.update(membersToBeAnonymized.values(), false);
                accountMessage = processUpdateResults(listResult, accountMessage, mapMemberAccount);
       		}
       	}

        return accountMessage;
    }

    /*
    *@Name : createContactMember
    *@description This method will create a Member for a single Contact.
    *@param String
    *@return Id contactId
    *@throws NA
    */
    public static String createContactMember(Id contactId){ 
        Set<Id> setContactIds = new Set<Id>();
        setContactIds.add(contactId);
        Map<String, String> memberResponse = createMemberContact(setContactIds);
        List<String> listTemp = new List<String>();
        listTemp.addAll(memberResponse.keySet());
        return memberResponse.get(contactId);        
    }
    
    /*
    *@Name : createMembers
    *@description This method will create a Member for a Contact, if it's valid.
    *@param Map<String, String>
    *@return Set<Id> setContactIds, Id programId
    *@throws NA
    */
    public static Map<String, String> createMembers(Set<Id> setContactIds, Id programId){
        if (setContactIds.isEmpty()){
            return new Map<String, String>{null => Label.TEST_ContactNotAvailableForLoyalty};        
        }
        else{
            Map<String, String> memberResponse = createMemberContact(setContactIds);
            List<String> listTemp = new List<String>();
            listTemp.addAll(memberResponse.keySet());
            String contactId = listTemp[0];
            Integer responseLength = memberResponse.get(contactId).length();
            
            if (memberResponse.get(contactId).startsWith(SUCESS_PREFIX)){
                return new Map<String, String>{contactId => memberResponse.get(contactId).substring(SUCESS_PREFIX.length(), responseLength)}; 
            }
            else {
                return new Map<String, String>{contactId => memberResponse.get(contactId).substring(ERROR_PREFIX.length(), responseLength)};
            }
        }
    }
}