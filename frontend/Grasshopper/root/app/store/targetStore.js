Ext.define('GH.store.targetStore', {
	extend: 'Ext.data.TreeStore',
	alias: 'widget.targetStore',
	
	root: {
		text: 'Targets',
		expanded: true,
	},
	
	proxy: {
		type: 'rest',
		headers: {'Content-type': 'application/json'},
//		url:  '/data/targets.json',
		url:  '/rest/targets',
		reader: {
            type: 'json'
        }
	},
});
