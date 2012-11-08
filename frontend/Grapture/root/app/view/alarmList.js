Ext.define('Grapture.view.alarmList', {
    extend: 'Ext.grid.Panel',
    alias : 'widget.alarmList',
    itemId: 'alarmList',
    store:  'alarmsStore',
    
    viewConfig: {
        getRowClass: function(rec, idx, rowPrms, ds) {
            console.log(rec);
            var cssClass = '';
            
            if (rec.raw.active === 1) {
                if (rec.raw.severity === 2) {
                    cssClass = 'warningRow';
                }
                else if (rec.raw.severity === 3) {
                    cssClass = 'criticalRow';
                }
            }
            
            return cssClass;
        },
    },
    
    columns: [
        { text: 'Time',     dataIndex: 'timestamp', flex: 2, },
        { text: 'Host',     dataIndex: 'target', flex: 3, },
        { text: 'Device',   dataIndex: 'device', flex: 3, },
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
