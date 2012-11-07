Ext.define('Grapture.model.alarmsModel', {
	extend: 'Ext.data.Model',
	alias:  'widget.alarmsModel',
	
	fields: [ 
        {name: 'timestamp', type: 'string'},
        {name: 'target',    type: 'string'},
        {name: 'device',    type: 'string'},
        {name: 'metric',    type: 'string'},
        {name: 'value',     type: 'string'},
        {name: 'severity',  type: 'string'},
        {name: 'active',    type: 'string'},
    ],
});
