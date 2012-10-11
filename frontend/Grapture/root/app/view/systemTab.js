Ext.define('Grapture.view.systemTab', {
    extend: 'Ext.container.Container',
    alias : 'widget.systemTab',
    padding: 5,
    
    layout: { type: 'hbox', align: 'stretch', },
    
    items: [
        {
            xtype: 'container',
            layout: { type:'vbox', align: 'stretch' },
            flex: 1,
            items: [
                {
                    xtype: 'panel',
                    padding: 5,
                    title: 'Target Stats',
                    flex: 1,
                },
                {
                    xtype: 'panel',
                    padding: 5,
                    title: 'Polling Stats',
                    flex: 1,
                },
                {
                    xtype: 'panel',
                    padding: 5,
                    title: 'Discovery Stats',
                    flex: 1,
                },
            ],
        },
        {
            xtype: 'container',
            layout: { type:'vbox', align: 'stretch' },
            flex: 3,
            items: [
                {
                    xtype: 'container',
                    layout: { type:'hbox', align: 'stretch' },
                    flex: 1,
                    items: [
                        {
                            xtype: 'panel',
                            padding: 5,
                            title: 'Job Distribution by Target',
                            flex: 1,
                        },
                        {
                            xtype: 'panel',
                            padding: 5,
                            title: 'Job Distribution by Metric',
                            flex: 1,
                        },
                    ],
                },
                {
                    xtype: 'container',
                    layout: { type:'vbox', align: 'stretch' },
                    flex: 2,
                    items: [
                        {
                            xtype: 'panel',
                            padding: 5,
                            title: 'Jobs Per Second',
                            flex: 1,
                        },
                    ],
                },
            ],
        },
    ],
   

});
    
