Ext.define('Grapture.view.alarmList', {
    extend: 'Ext.grid.Panel',
    alias : 'widget.alarmList',
    itemId: 'alarmList',
    store:  'alarmsStore',
    
    //width    : 500,
    overflowY: 'auto',
    
    viewConfig: {
        getRowClass: function(rec, idx, rowPrms, ds) {
            console.log(rec);
            return rec.raw.severity === 2 ? 'ph-bold-row' : '';
        },
    },
    
    columns: [
        { text: 'Time',     dataIndex: 'timestamp', flex: 1, },
        { text: 'Host',     dataIndex: 'target', flex: 1, },
        { text: 'Device',   dataIndex: 'device', flex: 1, },
        { text: 'Metric',   dataIndex: 'metric', flex: 1, },
        { 
            text     : 'Severity', 
            dataIndex: 'severity', 
            flex     : 1,
            renderer : function(value){
                var sevs = {
                    1: 'OK',
                    2: 'WARNING',
                    3: 'CRITICAL',
                };
                
                if ( sevs[value] ) {
                    return sevs[value];
                }
                
                return 'UNKNOWN';
            },
        },
        { text: 'Value',    dataIndex: 'value', flex: 1, },
    ],
});
