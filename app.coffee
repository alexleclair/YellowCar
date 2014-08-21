App = 
	config:
		http:
			port:8090
			host:'0.0.0.0'
		redis: 
			host:'127.0.0.1'
			port:6379
			db:0
			keyPrefix:'yellowcar:'

	express:require('express')
	io:null
	app:null
	server:null
	fs:require('fs')
	redis:require('redis')
	redisClient:null;
	gameId:null
	stats:{}


	init:()->
		App.redisClient = App.redis.createClient(App.config.redis.port, App.config.redis.host);

		App.redisClient.on 'connect', ->

			gameIdKey = App.config.redis.keyPrefix+'id'
			App.redisClient.get gameIdKey, (err, id)->
				if !id?
					id=1
					App.redisClient.set App.config.redis.keyPrefix+'id', id
				App.gameId = id
				App.refreshStats ->
					App.app = App.express()
					App.server = require('http').createServer(App.app);
					App.io = require('socket.io')(App.server);

					App.server.listen App.config.http.port;
					App.app.use App.express.static(__dirname + '/public');
					App.io.on 'connection', App.onConnect
					App.sendStats();

	refreshStats:(callback)->
		id = if id? then id else App.gameId
		key = App.config.redis.keyPrefix+'game:'+id
		App.redisClient.zrevrangebyscore [key, '+inf', '-inf', 'WITHSCORES'], (err, data)->
			App.stats = {}
			for i in [0...data.length] by 2
				App.stats[data[i]] = 1*data[i+1]

			if callback?
				callback();
	onConnect:(socket)->
		App.sendStats();

		socket.on 'vote',  (who)->
			value = if App.stats? && App.stats[who]? then App.stats[who] else 0;
			value = 1*value + 1; 
			App.stats[who] = value;
			App.redisClient.zadd [App.config.redis.keyPrefix+'game:'+App.gameId, value, who], ()->
				#Dummy.
			App.sendStats();

		socket.on 'newgame',  ()->
			App.redisClient.incr App.config.redis.keyPrefix+'id', (err, response)->
				App.gameId = response
				App.refreshStats ()->
					App.sendStats();

	sendStats:()->
		stats = []
		for who,score of App.stats
			stats.push 
				name: who,
				score: score
		stats.sort (a,b)->
			return b.score - a.score;
		App.io.emit 'stats', stats

	sendError:(socket, text)->
		if socket? && socket.emit?
			socket.emit('problem', text);


App.init();