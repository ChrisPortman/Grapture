Ext.define('Grapture.store.alarmsStore', {
    extend: 'Ext.data.Store',
    alias:  'widget.alarmsStore',
    model:  'Grapture.model.alarmsModel',
    
    proxy: {
        type: 'ajax',
        url : 'rest/alarms',
        reader: {
            type: 'json',
            root: 'data',
        }
    },
    autoload: true,
});
