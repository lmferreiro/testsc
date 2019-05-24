public with sharing class AdvanceContentController extends ComponentManager{
    
    @auraEnabled
    public static ComponentWrapper getComponentWrapper(String componentExternalId, String clusterId, String device, String navigationUrl){
        AdvanceContentController ctrl = new AdvanceContentController();
        ComponentWrapper cw = new ComponentWrapper();
        ctrl.customPermissionEdit = 'AdvanceContentEditFrame';
        ctrl.customPermissionView = 'AdvanceContentViewFrame';
        ctrl.componentFieldSet = new Set<String>();        
        ctrl.componentExternalId = componentExternalId;
        ctrl.clusterId = clusterId;
        ctrl.device = device;
        ctrl.navigationUrl = navigationUrl;
        ctrl.sObjectType = '[CMS]Content__c';
        cw = ctrl.getCW();
        ContentManager.CMSContent dw = (ContentManager.CMSContent) cw.data;

        if(!dw.contentWrapper.isEmpty()){
            cw.permissions.isEnabledEditFrame = false;
        }
        return cw;
    }

    public override DataWrapper getData() {
        
        Set<String> contentSetFields = new Set<String>{
            '[CMS]HTMLContent__c',
            'Name'
        };
        
        return ContentManager.getCMSContent(clusterId, cw.meta.component, contentSetFields, device);
    }

}