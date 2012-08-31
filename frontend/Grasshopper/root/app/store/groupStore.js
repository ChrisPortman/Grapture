Ext.define('GH.store.groupStore', {
	extend: 'Ext.data.Store',
	alias: 'widget.groupStore',

	fields: ['name', 'path'],
	data  : [],
});
