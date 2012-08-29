Ext.define('GH.view.addTarget', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.addTarget',

	title         : 'Add Target',
	layout        : 'fit',
	height        : 75,
	width         : 200,
	floating      : true,
	focusOnToFront: true,
	draggable     : true,
	closable      : true,
	items         : [
	    {
			xtype  : 'addTargetTabs',
		},
	],
	
	renderTo      : Ext.getBody(),
		
});
