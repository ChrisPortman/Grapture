Ext.define('Grapture.view.login', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.login',
    itemId: 'loginPanel',
    
    title: 'Login',
    
   	floating      : true,
	focusOnToFront: true,
	draggable     : true,
	closable      : true,
	hidden        : true,
	renderTo      : Ext.getBody(),
	
	items: [
	    {
			xtype: 'form',
			itemId: 'loginForm',
			header: false,
			bodyPadding: 5,
			layout : 'anchor',
			width  : 350,

		    url: '/usermgmt/login',
				
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
					itemId    : 'login_username',
					name      : 'username',
					fieldLabel: 'Username',
				},
				{
					itemId    : 'login_password',
					name      : 'password',
					fieldLabel: 'Password',
					inputType : 'password',
				},

				{
					xtype: 'button',
					text: 'Login',
					anchor: '25%',
					itemId: 'loginSubmit',
					formBind: true, //only enabled once the form is valid
					disabled: true,
					style: { float: 'right' },
				},
		    ],
		},
	],
});
