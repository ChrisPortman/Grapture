Ext.define('GH.view.searchResults', {
    extend: 'Ext.grid.Panel',
    alias : 'widget.searchResults',
    
    hidden: true,
    autoScroll: true,
    store: 'searchResultsStore',
    columns: [{ header: 'Results', dataIndex: 'results', flex: 1 }],
});
