Ext.application({
    requires : [
        'Ext.container.Viewport',
        'Ext.util.Cookies',
    ],
    name     : 'GH',
    
    appFolder: '/app',
    
    controllers: [
        'Browser'
	],		
        
    launch: function() {
        Ext.create('Ext.container.Viewport', {
            layout: { type:'vbox', align: 'stretch' },
            
			items: [
				{
					xtype: 'container',
					layout: { type: 'hbox', align: 'stretch', },
					flex: 1,
					
					items: [
						{
							xtype: 'panel',
     						title: 'Targets',
							flex: 2,
							padding: '10 0 10 10',
							layout: { type: 'vbox', align: 'stretch' },
							
							items: [
								{
									xtype: 'targetSearch',
									width: 120,
									height: 20,
									padding: '10 5 10 5',
									labelAlign: 'right',
									labelWidth: 40,
								},
								{
									xtype: 'searchResults',
									maxheight: 150,
									border: 0,
								},
								{
									xtype: 'targetTree',
									flex: 1,
									border: 0,
								}
							],
							tools: [
							    {
									type   : 'plus',
									tooltip: 'Add hosts',
									itemId : 'addHostTool',
									//~ handler: addTargetGui,
								},
							],
						},
						{
							xtype: 'content',
							flex: 9,
							border: 0,
						    style: {borderColor:'#000000', borderStyle:'solid', borderWidth:'1px'},
						    layout: 'fit',
						    
						    items: [
								{
									margin: 10,
									xtype: 'catTabs',
								},
							],
						},
					],
				},  
			 ],
        });
    }
});
