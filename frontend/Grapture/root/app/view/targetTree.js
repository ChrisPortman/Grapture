Ext.define('Grapture.view.targetTree', {
    extend: 'Ext.tree.Panel',
    alias : 'widget.targetTree',
    itemId: 'targetTree',
    
    overflowY: 'auto',
    
    store: 'targetStore',


    dockedItems: [{
	    xtype: 'toolbar',
	    dock: 'bottom',
	    items: [
	        { 
				xtype: 'button', 
				itemId: 'showLoginButton',
	            text: 'Login',
	        }
	    ]
	}]
         
});
    
