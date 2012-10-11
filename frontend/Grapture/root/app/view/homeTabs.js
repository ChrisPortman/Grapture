Ext.define('Grapture.view.homeTabs', {
    extend: 'Ext.tab.Panel',
    alias : 'widget.homeTabs',
    
    title       : 'Grapture Monitoring System',
    tabPossition: 'top',
    
    items: [
        {
            title: 'System',
            layout: 'fit',
        },
        {
            title: 'Alarms',
            layout: 'fit',
        },
        {
            title: 'Log',
            layout: 'fit',
        },
    ],
});
