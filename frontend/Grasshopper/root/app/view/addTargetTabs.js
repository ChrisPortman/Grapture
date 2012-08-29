Ext.define('GH.view.addTargetTabs', {
    extend: 'Ext.tab.Panel',
    alias : 'widget.addTargetTabs',
    
    activeTab: 0,
    tabPossition: 'top',
    
    items: [
        {
		    title: 'Single Host',
		    bodyPadding: 10,
		},
		{
		    title: 'Multiple Hosts',
		    bodyPadding: 10,
		}
    ],
    
});
    
