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
	
	//Blast any old graph data
	$['cache'] = {};
	GH['graphdata'] = {};

    //clear any graphs previously on display.
	this.getGraphsRef().removeAll();
	
	//remove unfrendly chars from the device
	device = device.replace(/\//g,'_');
	
	//Get the graphdata from the server.
	Ext.Ajax.request({
		url    : '/rest/graphdata/'+target+'/'+category+'/'+device,
		scope  : this,
		success: buildGraphs, 
    });

	function buildGraphs (response) {
		
		//Scope in some variables
		var rrdData = response.responseText;
		var target  = target;
		var device  = device;
		var graphsPanel = this.getGraphsRef();
	
		var panels = [];
		
		resonse = undefined;
		rrdData = Ext.JSON.decode(rrdData)['data'];
		
		//each 'group' represents one graph on the page.
		for (group in rrdData) {
			var bigGraphPh = group;
			var smlGraphPh = group+'-ov';
			
			//Having to stash the data somewhere globally accessable seems
			//yucky however I cant find a good way of passing it to the 
			//call back.
			GH['graphdata'][group] = {};  //Create the obj
			GH['graphdata'][group]['settings'] = rrdData[group]['settings'];
			delete rrdData[group]['settings']; //the rest of rrdData is actual data
			GH['graphdata'][group]['data'] = rrdData[group]; //store the remainder of rrdData
			
	        panels.push(
				{
					xtype  : 'panel',
					title  : group,
					margin : '10 auto 10 auto',
					layout: 'fit',
					html: '<div style = "float: left;">                                                                            \
					           <div id="'+bigGraphPh+'" style="width: 700px; height: 250px; margin: 10px;"></div>                  \
					           <div style = "float: left;">                                                                        \
						           <div id="'+smlGraphPh+'" style="float: left; width: 400px; height: 100px; margin: 10px;"></div> \
						           <div id="'+group+'-frm" style = "float: left; margin: 10px;">                                   \
						               Resolution:<br />                                                                           \
						               <select id="'+group+'-sel" onchange="renderGraph(\''+group+'\', null, true)"></select>      \
						               <br /><br />                                                                                \
						               <button type="button" onclick="renderGraph(\''+group+'\', null, true)">Reset Area</button>  \
						           </div>                                                                                          \
						       </div>                                                                                              \
					       </div>',
					minHeight: 200,
					minWidth: 400,
					listeners: {
						afterrender: {
							scope: this,
							fn: renderGraph,
						},
					},
				}
			);
		}
		graphsPanel.setTitle( device + ' Performance Graphs');
		graphsPanel.add( panels );
	}
}

//call back fired after a graph pannel loads.  Is responcible for 
//rendering a graph inside the panel
function renderGraph(panel, eopts, rraChange) {
    
    //The group can be had from the panels title or just the panel var 
    //if this is a graph update and not the initial load.
    var group = panel.title || panel;
    
    //retreive the data for this group from the 'global' space (yuck)
	var settings = GH['graphdata'][group]['settings'];
	var data = GH['graphdata'][group]['data'];
	
	//Each key is the time of the first metric val in the series
    var rraKeys = new Array();
    for ( key in data ) {
		rraKeys.push(key);
	}
	
	//Sort decending so the most recent time is on top.
	rraKeys.sort(function(a,b){ return b-a });

    //On the initial load (ie not a time series change) build the list
    //of options to go into the time series dropdown.
    if ( !rraChange ){
		for (key in rraKeys) {
			//create an option object
			var opt   = document.createElement("option");
			opt.text  = new Date(rraKeys[key]*1000).toString();
			opt.value = key;
	
			//add the option to the select
			var select = document.getElementById( group+'-sel' );
			select.add(opt);
	    }
	}

    //Determine the placeholder divs for the main and preveiw graph.
    var bigGraphPh = group;
    var smlGraphPh = group + '-ov';
    
    //Calculate the data
    var initialData = getData();
    
    //work out some display opts
    var fill;
    var stack;
    if (settings['fill']) {
		fill = true;
	}
	if (settings['stack']) {
		stack = true;
	}
    
    //Graph display options
    var graphOpts = {
		legend: {
			show: true,
			noColumns: 4,
			position: 'nw'
		},
		xaxis: {
			mode: 'time',
			timeformat: "%d/%m/%y %h:%M",
			ticks: 5,
		},
		selection: { mode: "xy" },
		series: {
			lines: {
				show:  true,
				fill:  fill,
			},
			stack: stack,
		}
	}
	
	//Plot the main graph
	var plot = $.plot( '#'+bigGraphPh, initialData, graphOpts );
	
	//Preview graph display options
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
		series: {
			lines: {
				show:  true,
				fill:  fill,
			},
			stack: stack,
		}
	}
	
	//Plot the preview graph
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
    
	function getData(start, end) {
	    //function to build the data set    
	
	    var plotData  = [];
	    var rraKeyIdx = 0;
	    
	    if (rraChange) {
			//This was prompted by a res change. Select the new rra key
			var select = document.getElementById( group+'-sel' );
			rraKeyIdx = select.selectedIndex;
		}
	
		for (j in data[rraKeys[rraKeyIdx]] ) {
			var label = data[rraKeys[rraKeyIdx]][j]['label'];
			var plots = data[rraKeys[rraKeyIdx]][j]['plots'];
			
			if ( start && end ) {
				var filteredPlots = [];
				
				for ( i in plots ) {
					var timestamp = plots[i][0];
					if ( timestamp >= start && timestamp <= end ) {
						filteredPlots.push(plots[i]);
					}
				
					if (timestamp > end) {
						break;
					}
				}
				plots = filteredPlots;
			}
			
			//var first = data[rraKeys[0]][j]['plots'][0][0];
			plotData.push( { label: label, data: plots } );
	    }
	
		return plotData;
	}
}


