Ext.define('GH.view.addTarget', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.addTarget',

	title         : 'Add Target',
	layout        : 'fit',
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