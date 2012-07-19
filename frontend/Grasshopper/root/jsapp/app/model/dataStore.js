Ext.define('GH.model.dataStore', {
	extend: 'Ext.data.Model',
	alias:  'widget.dataStore',

    fields: [
		{ name: 'name',              type: 'string' },
    	{ name: 'last_ds',           type: 'string' },
    	{ name: 'min',               type: 'string' },
    	{ name: 'value',             type: 'string' },
    	{ name: 'max',               type: 'string' },
    	{ name: 'minimal_heartbeat', type: 'int'    },
    	{ name: 'index',             type: 'index'  },
    	{ name: 'type',              type: 'string' },
    	{ name: 'unknown_sec',       type: 'int'    },
    ],
    
    belongsTo: 'GH.model.graphDetails',
});
