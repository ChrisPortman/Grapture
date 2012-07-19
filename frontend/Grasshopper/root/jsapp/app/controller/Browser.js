Ext.define('GH.controller.Browser', {
    extend: 'Ext.app.Controller',
    
    
    views: [
        'targetTree',
        'targetSearch',
        'searchResults',
        'content',
        'catTabs',
        'deviceList',
        'graphs',
    ],
    
    stores: [
        'targetStore',
        'searchResultsStore',
        'catTabStore',
        'devicesStore',
    ],
    
    models: [
        'tabsModel',
        'devicesModel',
	],
    
    refs: [
        {
			ref: 'treeref',
			selector: 'targetTree',
		},
		{
			ref: 'searchResultsRef',
			selector: 'searchResults',
		},
		{
			ref: 'catTabsRef',
			selector: 'catTabs',
		},
		{
			ref: 'graphsRef',
			selector: 'graphs',
		},
    ],
    
    init  : function() {
		this.control({
			'targetSearch': {
				change: {fn: searchTargets, buffer: 500},
			},
			'targetTree': {
				itemclick: { fn: loadTarget },
			},
			'searchResults': {
				itemclick: { fn: loadTarget },
			},
			'catTabs': {
				tabchange: {fn: loadCategory },
			},
			'deviceList': {
				itemclick: { fn: loadGraphs },
			}
		});
		
		console.log('Browser controller initialised');
	},
});


function searchTargets(search, event, opts) {
	if ( search ) {
		var curVal = search.getValue();
		
		if (curVal != "") {
			
			var tree = this.getTreeref();
			var treeRoot = tree.getRootNode();
			
			var args = new Array();
			args[0] = curVal;
			
			var results = new Array();
	
			treeRoot.cascadeBy(function(scope){
				if ( scope.isLeaf() ) {
					var leafName = scope.data.text;
					
					var regex = new RegExp(curVal, 'i');
					if ( leafName.match(regex) ){
					    results.push( [ leafName ] );
					}
					else {
						scope.isVisible(false);
					}
				}
			}, this);

            if ( results.length ) {	
		        //build a memory proxy and put it on search results.
		        this.getSearchResultsRef().enable();
			}
			else {
				results.push( [ 'No Matches Found' ] );
				this.getSearchResultsRef().disable();
			}
	        this.getSearchResultsStoreStore().loadData( results );
			this.getSearchResultsRef().show();
	    }
	    else {
			this.getSearchResultsRef().hide();
		}
    }
}

function loadTarget(node, record, item, index, event) {
	//Work out what target we are looking at
	var target;
	if (record.data.results) {
		//target from a search result
	    target = record.data.results;
	}
	else if (typeof record.isLeaf == 'function') {
		//target from the tree
		target = record.data.text;
	}
	
	if (target) {
		//We got a target
		GH.currentTarget = target;
		
        var catTabs = this.getCatTabsRef();
        var catTabsStore = this.getCatTabStoreStore();		

        catTabsStore.setProxy( {
			type: 'rest',		
			headers: {'Content-type': 'application/json'},
			//url:  '/data/tabs.' + target + '.json',
			url:  '/rest/targetcats/' + target,
			reader: {
	            type: 'json',
	        },
		});
		
		catTabsStore.load(function(records, operation, success) {
	        var tabs  = catTabsStore.getRange();
       		
       		//set removingTabs for the remove all, this will stop the
       		//tabchange handler from doing stuff unnecessarily.
       		GH.removingTabs = true;
       		catTabs.removeAll();
       		GH.removingTabs = false;
       		
	        for ( i = 0; i < catTabsStore.count(); i++ ) {
				catTabs.add( { 
					title: tabs[i].data.title,
					layout: 'fit',
				 } );
			}
			
			catTabs.setActiveTab(0);		
	    });
		
	}
}

function loadCategory(tabPanel, newTab, oldTab) {

	if ( GH.removingTabs ) {
		//change due to removing tabs, dont do anything.
		return 1;
	}
	
	var devStore   = this.getDevicesStoreStore();
	var target     = GH.currentTarget;
	var category   = newTab.title;
	var targetDisp = target.substr(0,1).toUpperCase() + target.substr(1)
	GH.currentCat = category; //save the category
	
	console.log(targetDisp);
	
	if (oldTab) {
		oldTab.removeAll();
	}
	
	newTab.add([
	    {
			xtype: 'container',
			layout: {type: 'hbox', align: 'stretch'},
			items: [
				{
					xtype: 'deviceList',
					title: targetDisp + ' Devices',
					flex: 1,
				},
				{
					xtype: 'graphs',
					layout: {type: 'vbox', align: 'center'},
					flex: 5,
				},
			],
		},
	]);
	
	devStore.setProxy({
			type: 'rest',
			headers: {'Content-type': 'application/json'},
			//url:  '/data/devices.' + target + '.' + category + '.json',
			url:  '/rest/targetdevices/' + target + '/' + category,
			reader: {
	            type: 'json',
	        },
    });
    
    devStore.load();	
}

function loadGraphs(node, record, item, index, event) {
	var target      = GH.currentTarget;
	var category    = GH.currentCat;
	var device      = record.data.title;
	
	//remove unfrendly chars from the device
	device = device.replace(/\//,'_');
	
	Ext.Ajax.request({
		url: '/rest/graphdata/'+target+'/'+category+'/'+device,
		scope: this,
		success: function(response) { buildGraphs(response,target,device,this.getGraphsRef()); },
    });
}

function buildGraphs(response,target,device, graphsPanel) {
	var rrdData = response.responseText;
	var panels = [];
	
	resonse = undefined;
	rrdData = Ext.JSON.decode(rrdData)['data'];
	
	for (group in rrdData) {
		var bigGraphPh = group;
		var smlGraphPh = group+'-ov';
		
		console.log('Building Panel defs:');
	    console.log('Big graph container: ' + bigGraphPh);
	    console.log('Sml graph container: ' + smlGraphPh);
        
        panels.push(
			{
				xtype  : 'panel',
				title  : group,
				padding: '20 50 0 50',
				layout: 'fit',
				html: '<div><div id="'+group+'-sel"></div><div id="'+bigGraphPh+'" style="width: 700px; height: 250px; margin: 10px;"></div><div id="'+smlGraphPh+'" style="width: 400px; height: 100px; margin: 10px;"></div></div>',
				minHeight: 200,
				minWidth: 400,
				listeners: {
					afterrender: {
						scope: this,
						fn: function(){ renderGraph(bigGraphPh, smlGraphPh, rrdData[group]); },
					},
				},
			}
		);
	}
	graphsPanel.removeAll();
	graphsPanel.setTitle( device + ' Performance Graphs');
	console.log( panels );
	graphsPanel.add( panels );
}

function renderGraph(bigGraphPh, smlGraphPh, data) {
 
    function getData(start, end) {
	    var plotData = [];
	    
	    var keys = new Array();
	    for ( key in data ) {
			keys.push(key);
		}
	
		keys.sort(function(a,b){ return b-a });
	
		for (j in data[keys[0]] ) {
			var label = data[keys[0]][j]['label'];
			var plots = data[keys[0]][j]['plots'];
			
			
			if ( start && end ) {
				var filteredPlots = [];
				console.log('Start: '+ start + ' End: ' + end);
				console.log('Building a filtered list');
				
				for ( i in plots ) {
					var timestamp = plots[i][0];
					if ( timestamp >= start && timestamp <= end ) {
						filteredPlots.push(plots[i]);
					}
				
					if (timestamp > end) {
						console.log('Timestamp now greater than end. stop');
						break;
					}
				}
				plots = filteredPlots;
			}
			
			
			var first = data[keys[0]][j]['plots'][0][0];
			console.log( 'First sample is at '+ new Date(first).toString() );
			plotData.push( { label: label, data: plots } );
	    }
    
        return plotData;
    }
    
    console.log('Building graphs:');
    console.log('Big graph container: ' + bigGraphPh);
    console.log('Sml graph container: ' + smlGraphPh);
    var initialData = getData();
    
    var graphOpts = {
		legend: {
			show: true,
			noColumns: 4,
			position: 'nw'
		},
		series: {
			lines: { show: true, },
		},
		xaxis: {
			mode: 'time',
			timeformat: "%d/%m/%y %h:%M",
			ticks: 5,
		},
		yaxis: {
			autoscaleMargin: 0.2,
		},
		selection: { mode: "xy" },
	}

	var plot = $.plot( '#'+bigGraphPh, initialData, graphOpts);
	
	var overviewOpts = {
		legend: { show: false },
		series: {
            lines: { show: true, lineWidth: 1 },
            shadowSize: 0
        },
        xaxis: { 
			ticks: 4, 
            mode: 'time',
            timeformat: "%d/%m/%y %h:%M",
        },
        yaxis: { ticks: 3, },
        grid: { color: "#999" },
        selection: { mode: "xy" },
	}
	
	var overView = $.plot( '#'+smlGraphPh, initialData, overviewOpts);
	
	//Connect the 2 graphs
	$('#'+bigGraphPh).bind("plotselected", function (event, ranges) {
        // clamp the zooming to prevent eternal zoom
        if (ranges.xaxis.to - ranges.xaxis.from < 0.00001)
            ranges.xaxis.to = ranges.xaxis.from + 0.00001;
        if (ranges.yaxis.to - ranges.yaxis.from < 0.00001)
            ranges.yaxis.to = ranges.yaxis.from + 0.00001;
        
        // do the zooming
        plot = $.plot($('#'+bigGraphPh), getData(ranges.xaxis.from, ranges.xaxis.to),
                      $.extend(true, {}, graphOpts, {
                          xaxis: { min: ranges.xaxis.from, max: ranges.xaxis.to },
                          yaxis: { min: ranges.yaxis.from, max: ranges.yaxis.to }
                      }));
        
        // don't fire event on the overview to prevent eternal loop
        overView.setSelection(ranges, true);
    });
    $('#'+smlGraphPh).bind("plotselected", function (event, ranges) {
        plot.setSelection(ranges);
    });
	
	
	
	
}
