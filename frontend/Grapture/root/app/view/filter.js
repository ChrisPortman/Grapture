Ext.define('Grapture.view.filter', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.filter',
    itemId: 'filterPanel',
    
    title: 'Filter Alarms',
    
	collapsible      : true,
    collapsed        : true,
    collapseDirection: 'top',

    layout: 'fit',    
    
	items: [
        {
            xtype : 'container',
            layout: 'hbox',
            margin: '5 0 5 0',
            
            items: [
                {
                    xtype     : 'textfield',
                    itemId    : 'dateFilter',
                    name      : 'dateFilter',
                    //~ fieldLabel: 'Date',
                    //~ labelAlign: 'top',
                    flex      : 2,
                },
                {
                    xtype     : 'textfield',
                    itemId    : 'hostFilter',
                    name      : 'hostFilter',
                    //~ fieldLabel: 'Host',
                    //~ labelAlign: 'top',
                    flex      : 3,
                },
                {
                    xtype     : 'textfield',
                    itemId    : 'deviceFilter',
                    name      : 'deviceFilter',
                    //~ fieldLabel: 'Host',
                    //~ labelAlign: 'top',
                    flex      : 3,
                },
                {
                    xtype     : 'textfield',
                    itemId    : 'metricFilter',
                    name      : 'metricFilter',
                    //~ fieldLabel: 'Host',
                    //~ labelAlign: 'top',
                    flex      : 1,
                },
                {
                    xtype     : 'textfield',
                    itemId    : 'sevFilter',
                    name      : 'sevFilter',
                    //~ fieldLabel: 'Host',
                    //~ labelAlign: 'top',
                    flex      : 1,
                },
                {
                    xtype     : 'textfield',
                    itemId    : 'valueFilter',
                    name      : 'valueFilter',
                    //~ fieldLabel: 'Host',
                    //~ labelAlign: 'top',
                    flex      : 1,
                },
            ],
        },
	],
});
