Ext.define('GH.view.editHostGui', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.editHostGui',
    itemId: 'editHostGui',
    
    title: 'Edit Host',
    
   	floating      : true,
	focusOnToFront: true,
	draggable     : true,
	closable      : true,
	hidden        : true,
	renderTo      : Ext.getBody(),
	
	items: [
	    {
			xtype: 'form',
			itemId: 'editHostForm',
			header: false,
			bodyPadding: 5,
			layout : 'anchor',
			width  : 350,

		    url: '/rest/edithost',
				
			defaults: {
				anchor: '100%',
				allowBlank: false,
			},
			
			fieldDefaults: {
				labelWidth: 100,
				labelSeparator: ' ',
				labelAlign: 'right',
			},
		
			defaultType: 'textfield',
		
			items: [
				{
					xtype     : 'numberfield',
					itemId    : 'edit_snmpversion',
					name      : 'snmpversion',
					fieldLabel: 'SNMP Version',
					value      : 2,
					minValue   : 1,
					maxValue   : 3,
				},
				{
					itemId    : 'edit_snmpcommunity',
					name      : 'snmpcommunity',
					fieldLabel: 'SNMP Community',
				},
				{
					xtype       : 'combobox',
					itemId      : 'edit_group',
					name        : 'group',
					fieldLabel  : 'Group',
					store       : Ext.create('Ext.data.Store', {
									  fields: ['name', 'path'],
									  data  : [],
								  }),
					queryMode   : 'local',
					valueField  : 'name',
					displayField: 'path',
					forceSelection: true,
				},
				{
					xtype     : 'checkbox',
					fieldLabel: 'Rediscover',
					itemId    : 'edit_rediscover',
					name      : 'rediscover',
				},
				{
					xtype     : 'hidden',
					itemId    : 'edit_hostname',
					name      : 'hostname',
				},
     			{
					xtype     : 'hidden',
					itemId    : 'edit_origGroup',
					name      : 'origGroup',
				},

				{
					xtype: 'button',
					text: 'Reset',				
					anchor: '25%',
					style: { float: 'right', marginLeft: '5px' },
					handler: function() {
						this.up('#editHostGui').getForm().reset();
					}
				}, 
				{
					xtype: 'button',
					text: 'Submit',
					anchor: '25%',
					itemId: 'editHostSubmit',
					formBind: true, //only enabled once the form is valid
					disabled: true,
					style: { float: 'right', marginLeft: '5px' },
				},
		    ],
		},
	],
});
