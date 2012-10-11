Ext.define('Grapture.view.catTabs', {
    extend: 'Ext.tab.Panel',
    alias : 'widget.catTabs',
    
    activeTab   : 0,
    tabPossition: 'top',
    
    store: 'catTabStore',
    
    tools: [
        {
			type: 'gear',
			itemId: 'editHostTool',
			tooltip: 'Edit Host Configuration',
			hidden: true,
		}
    ]
});
    
