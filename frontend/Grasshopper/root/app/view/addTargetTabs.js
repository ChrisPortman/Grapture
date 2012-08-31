Ext.define('GH.view.addTargetTabs', {
    extend: 'Ext.tab.Panel',
    alias : 'widget.addTargetTabs',
    
    activeTab: 0,
    tabPossition: 'top',
    
    items: [
        {
		    title: 'Single Host',
		    bodyPadding: 5,
			items: [
				{
					xtype  : 'form',
					itemId : 'singleHostForm',
					url: '/rest/addhost',
					header: false,
					bodyPadding: 5,
					layout : 'anchor',
					width  : 350,
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
							itemId    : 'hostname',
							name      : 'hostname',
							fieldLabel: 'Hostname',
						},
						{
							xtype     : 'numberfield',
							itemId    : 'snmpversion',
							name      : 'snmpversion',
							fieldLabel: 'SNMP Version',
							value      : 2,
							minValue   : 1,
							maxValue   : 3,
						},
						{
							itemId    : 'snmpcommunity',
							name      : 'snmpcommunity',
							fieldLabel: 'SNMP Community',
						},
						{
							itemId    : 'group',
							name      : 'group',
							fieldLabel: 'Group',
						},
				    ],
					buttons: [
		    			{
							text: 'Reset',
							handler: function() {
								this.up('#singleHostForm').getForm().reset();
							}
						}, 
						{
							text: 'Submit',
							formBind: true, //only enabled once the form is valid
							disabled: true,
							handler: function() {
								var form = this.up('#singleHostForm').getForm();
								if (form.isValid()) {
									form.submit({
										success: function(form, action) {
										   Ext.Msg.alert('Success', action.result.msg);
										   form.reset();
										},
										failure: function(form, action) {
											Ext.Msg.alert('Failed', action.result.msg);
										}
									});
								}
							},
						},
					],
				},
			],
		},
		{
		    title: 'Multiple Hosts',
		    bodyPadding: 10,
			items: [
				{
					xtype  : 'form',
					itemId : 'multiHostForm',
					url: '/rest/addhost',
					header: false,
					bodyPadding: 5,
					layout : 'anchor',
					width  : 350,
					defaults: {
						anchor: '100%',
						allowBlank: false,
					},
					fieldDefaults: {
    					labelWidth: 100,
						labelSeparator: ' ',
						labelAlign: 'top',
					},
					defaultType: 'textarea',
					
					items: [
					    {
							itemId    : 'hostDetails',
							name      : 'hostDetails',
							fieldLabel: 'Host Details',
							grow      : true,
							growMax   : 300,
							autoScroll: true,
							// match one or more host definitions
							regex: /^[\w\.]+\s?,\s?[123]\s?,\s?[^\s]+\s?,\s?.+(\n[\w\.]+\s?,\s?[123]\s?,\s?[^\s]+\s?,\s?.+)*$/,
							regexText: "Specify one host per line in the following form:\nhostname,version (1|2|3),SNMP Community,Group",

						}
					
					],
					buttons: [
		    			{
							text: 'Reset',
							handler: function() {
								this.up('#multiHostForm').getForm().reset();
							}
						}, 
						{
							text: 'Submit',
							formBind: true, //only enabled once the form is valid
							disabled: true,
							handler: function() {
								var form = this.up('#multiHostForm').getForm();
								if (form.isValid()) {
									form.submit({
										success: function(form, action) {
										   Ext.Msg.alert('Success', action.result.msg);
										   form.reset();
										},
										failure: function(form, action) {
											Ext.Msg.alert('Failed', action.result.msg);
										}
									});
								}
							},
						},
					],

				},
			],	
		},
		{
		    title: 'Add Group',
		    bodyPadding: 5,
			items: [
				{
					xtype  : 'form',
					itemId : 'addGroupForm',
					url: '/rest/addgroup',
					header: false,
					bodyPadding: 5,
					layout : 'anchor',
					width  : 350,
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
							itemId    : 'groupname',
							name      : 'groupname',
							fieldLabel: 'Group Name',
						},
						{
							xtype       : 'combobox',
							itemId      : 'parentgroup',
							name        : 'parentgroup',
							fieldLabel  : 'Parent Group',
							store       : Ext.create('Ext.data.Store', {
	                                          fields: ['name', 'path'],
	                                          data  : [],
										  }),
							queryMode   : 'local',
							valueField  : 'name',
							displayField: 'path',
							forceSelection: true,
						},
				    ],
					buttons: [
		    			{
							text: 'Reset',
							handler: function() {
								this.up('#addGroupForm').getForm().reset();
							}
						}, 
						{
							text: 'Submit',
							itemId: 'addGroupSubmit',
							formBind: true, //only enabled once the form is valid
							disabled: true,
							//~ handler: function() {
								//~ var form = this.up('#addGroupForm').getForm();
								//~ if (form.isValid()) {
									//~ form.submit({
										//~ success: function(form, action) {
										   //~ Ext.Msg.alert('Success', action.result.msg);
										   //~ form.reset();
										//~ },
										//~ failure: function(form, action) {
											//~ Ext.Msg.alert('Failed', action.result.msg);
										//~ }
									//~ });
								//~ }
							//~ },
						},
					],
				},
			],
		},
    ],
    
});
    
