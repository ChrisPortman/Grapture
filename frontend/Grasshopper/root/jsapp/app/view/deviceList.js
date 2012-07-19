Ext.define('GH.view.deviceList', {
    extend: 'Ext.grid.Panel',
    alias : 'widget.deviceList',
    
    autoScroll: true,
    
    store: 'devicesStore',
    columns: [{ header: 'Devices', dataIndex: 'title', flex: 1 }],
});
